#Requires -Version 7
<#
The unattended loop: one issue task per iteration, fresh context, as the organisation's
GitHub App. Reads loop.local.json beside this script (gitignored):
  { "appId": 0, "installationId": 0, "keyPath": "...pem", "base": "D:\\GitRepos\\Claude" }
Run attended first:  .\loop.ps1 -Once
#>
param(
    [string]$Repo = "HeliosAdvance",
    [string]$Owner = "HeliosBBS",
    [switch]$Once,
    [int]$MaxIterations = 50,
    [string]$Model = "sonnet",
    [string]$EscalationModel = "opus"
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$config = Get-Content (Join-Path $PSScriptRoot "loop.local.json") -Raw | ConvertFrom-Json
$base = $config.base
$identity = "phaethusa[bot]"
$email = "$($config.appId)+phaethusa[bot]@users.noreply.github.com"
$repoDir = Join-Path $base $Repo
$wikiDir = Join-Path $base "$Repo.wiki"
$stateDir = Join-Path $base "state" $Repo
$null = New-Item -ItemType Directory -Force $base, $stateDir

function Log([string]$message) { Write-Host "[loop $(Get-Date -Format HH:mm:ss)] $message" }

function Base64Url([byte[]]$bytes) {
    [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

# A one-hour installation token, minted from the App's key; the session only ever sees the token.
function New-InstallationToken {
    $rsa = [System.Security.Cryptography.RSA]::Create()
    $rsa.ImportFromPem((Get-Content $config.keyPath -Raw))
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $header = Base64Url ([Text.Encoding]::UTF8.GetBytes('{"alg":"RS256","typ":"JWT"}'))
    $payload = Base64Url ([Text.Encoding]::UTF8.GetBytes("{`"iat`":$($now - 60),`"exp`":$($now + 540),`"iss`":`"$($config.appId)`"}"))
    $signature = Base64Url ($rsa.SignData([Text.Encoding]::UTF8.GetBytes("$header.$payload"),
            [Security.Cryptography.HashAlgorithmName]::SHA256,
            [Security.Cryptography.RSASignaturePadding]::Pkcs1))
    $jwt = "$header.$payload.$signature"
    $response = Invoke-RestMethod -Method Post -Uri "https://api.github.com/app/installations/$($config.installationId)/access_tokens" `
        -Headers @{ Authorization = "Bearer $jwt"; Accept = "application/vnd.github+json" }
    $response.token
}

function Invoke-Git { param([string]$dir, [Parameter(ValueFromRemainingArguments)][string[]]$args)
    $out = & git.exe -C $dir @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed in ${dir}: $out" }
    $out
}

# Clones read the token from the environment through a credential helper; nothing is written to disk.
function Ensure-Clone([string]$dir, [string]$url) {
    if (-not (Test-Path (Join-Path $dir ".git"))) {
        Log "cloning $url"
        & git clone --quiet $url $dir 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "clone of $url failed" }
    }
    Invoke-Git $dir config user.name $identity | Out-Null
    Invoke-Git $dir config user.email $email | Out-Null
    Invoke-Git $dir config credential.helper '!f() { echo username=x-access-token; echo password=$GH_TOKEN; }; f' | Out-Null
}

function Slug([string]$title) {
    $s = ($title.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ($s.Length -gt 40) { $s = $s.Substring(0, 40).Trim('-') }
    $s
}

function Set-Human([int]$number, [string]$reason) {
    Log "#${number}: human action required: $reason"
    & gh issue edit $number -R "$Owner/$Repo" --add-label human-action-required --remove-label claimed | Out-Null
    & gh issue comment $number -R "$Owner/$Repo" --body "Loop stopped: $reason" | Out-Null
}

function Read-State([int]$number) {
    $path = Join-Path $stateDir "$number.json"
    if (Test-Path $path) { Get-Content $path -Raw | ConvertFrom-Json }
    else { [pscustomobject]@{ iterations = 0; failingTests = @(); changedFiles = @(); ticks = 0; notes = "" } }
}

function Write-State([int]$number, $state) {
    $state | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $stateDir "$number.json")
}

function Build-Prompt($issue, [string]$learnings, [string]$notes) {
    @"
You are Phaethusa, the unattended loop, working in the worktree for issue #$($issue.number) of $Owner/$Repo.
Read the issue, then the learnings. Do exactly one of these, then stop:
- If the issue's Plan section has no checklist, run the feature-plan skill and write the plan into the issue.
- Otherwise run the feature-build skill for the first unticked task only.

Rules: one task per session. Commit and push only when ``make check`` is green. Tick the box with
``work tick``. Append a one-line learning to ``$wikiDir\Learnings.md`` (commit and push there) if
you learned a sign. Never edit features/, CONSTITUTION.md or the licence files. Never ask a
question: if a task needs judgment the plan is wrong. Reference the issue as #$($issue.number)
in commits; never write Closes until every box is ticked, then open the pull request.

End your output with exactly one line, and nothing after it:
  LOOP: DONE                 the task landed (or the plan is in the issue)
  LOOP: ROUTE-UP <notes>     tests failed twice with different fixes, or the diff outgrew the task
  LOOP: HUMAN <reason>       a decision, a broken baseline, or an unplanned security-sensitive path

## Issue #$($issue.number): $($issue.title)
$($issue.url)

$($issue.body)

## Learnings
$learnings

## Notes from the previous attempt
$notes
"@
}

function Invoke-Session([string]$dir, [string]$prompt, [string]$model, [string]$logPath) {
    $env:WORK_IDENTITY = $identity
    Push-Location $dir
    try {
        & claude -p $prompt --model $model --effort high --dangerously-skip-permissions --output-format text 2>&1 |
            Tee-Object -FilePath $logPath
    }
    finally { Pop-Location }
}

function Get-Marker([string[]]$lines) {
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $line = $lines[$i].Trim()
        if ($line -match '^LOOP:\s*(DONE|ROUTE-UP|HUMAN)\b\s*(.*)$') { return @($Matches[1], $Matches[2]) }
        if ($line -match "usage limit|rate limit|hit your limit") { return @("PAUSE", $line) }
        if ($line) { break }
    }
    @("NONE", "")
}

# ---- main ----
$env:GH_TOKEN = New-InstallationToken
Ensure-Clone $repoDir "https://github.com/$Owner/$Repo.git"
Ensure-Clone $wikiDir "https://github.com/$Owner/$Repo.wiki.git"
Invoke-Git $repoDir fetch --quiet --prune origin | Out-Null
Invoke-Git $repoDir checkout --quiet development | Out-Null
Invoke-Git $repoDir reset --quiet --hard origin/development | Out-Null
Invoke-Git $wikiDir pull --quiet --ff-only | Out-Null

for ($iteration = 1; $iteration -le $MaxIterations; $iteration++) {
    if ($iteration % 4 -eq 0) { $env:GH_TOKEN = New-InstallationToken }
    Push-Location $repoDir
    try {
        & work refresh 2>&1 | Out-Null
        $json = & work next --loop 2>$null
        if ($LASTEXITCODE -eq 3) { Log "nothing to do"; break }
        if ($LASTEXITCODE -ne 0) { throw "work next failed" }
    }
    finally { Pop-Location }
    $pick = $json | ConvertFrom-Json
    $number = [int]$pick.number
    $issue = Get-Content (Join-Path $repoDir "issues.jsonl") | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object number -eq $number
    if ($pick.claimed_by -ne $identity) { Push-Location $repoDir; & work claim $number | Out-Null; Pop-Location }
    Log "#${number}: $($issue.title)"

    $branch = "issue-$number-$(Slug $issue.title)"
    $worktree = Join-Path $base "$Repo.wt" $branch
    if (-not (Test-Path $worktree)) {
        $remote = & git -C $repoDir ls-remote --heads origin $branch
        $start = if ($remote) { "origin/$branch" } else { "origin/development" }
        Invoke-Git $repoDir worktree add --quiet -B $branch $worktree $start | Out-Null
    }

    $state = Read-State $number
    $state.iterations++
    $log = Join-Path $stateDir "$number-$($state.iterations).log"

    Push-Location $worktree
    try {
        & make bootstrap 2>&1 | Out-Null
        $baseline = & make check 2>&1
        if ($LASTEXITCODE -ne 0) {
            Set-Content "$log.baseline" $baseline
            Set-Human $number "make check is red on the baseline before any change; see the loop log"
            Write-State $number $state
            if ($Once) { break } else { continue }
        }
    }
    finally { Pop-Location }

    $learnings = Get-Content (Join-Path $wikiDir "Learnings.md") -Raw
    $ticksBefore = ([regex]::Matches($issue.body, '- \[x\]')).Count
    $output = Invoke-Session $worktree (Build-Prompt $issue $learnings $state.notes) $Model $log
    $marker, $detail = Get-Marker @($output)

    if ($marker -eq "ROUTE-UP") {
        Log "#${number}: routing up to $EscalationModel"
        $state.notes = $detail
        $output = Invoke-Session $worktree (Build-Prompt $issue $learnings $state.notes) $EscalationModel "$log.escalated"
        $marker, $detail = Get-Marker @($output)
        if ($marker -eq "ROUTE-UP") { $marker = "HUMAN"; $detail = "failed at $EscalationModel too: $detail" }
    }

    # The gutter detector: the same failing test, or the same files churned with no box ticked,
    # three iterations running; or a placeholder that passes.
    $failing = @([regex]::Matches(($output -join "`n"), '--- FAIL: (\S+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $changed = @(& git -C $worktree diff --name-only origin/development | Sort-Object)
    Push-Location $repoDir; & work refresh 2>&1 | Out-Null; Pop-Location
    $after = Get-Content (Join-Path $repoDir "issues.jsonl") | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object number -eq $number
    $ticked = $after -and ([regex]::Matches($after.body, '- \[x\]')).Count -gt $ticksBefore
    $state.failingTests = @($state.failingTests + , $failing | Select-Object -Last 3)
    $state.changedFiles = @($state.changedFiles + , $changed | Select-Object -Last 3)
    if ($ticked) { $state.ticks++; $state.notes = "" } else { $state.notes = ($output | Select-Object -Last 40) -join "`n" }
    $sameTest = $failing.Count -gt 0 -and $state.failingTests.Count -eq 3 -and (@($state.failingTests | ForEach-Object { $_ -join "," } | Sort-Object -Unique).Count -eq 1)
    $sameFiles = -not $ticked -and $changed.Count -gt 0 -and $state.changedFiles.Count -eq 3 -and (@($state.changedFiles | ForEach-Object { $_ -join "," } | Sort-Object -Unique).Count -eq 1)
    $placeholder = (& git -C $worktree diff origin/development) -match 'TODO|not implemented'
    if ($marker -ne "HUMAN" -and ($sameTest -or $sameFiles -or $placeholder)) {
        $marker = "HUMAN"
        $detail = if ($sameTest) { "the same test has failed three iterations running: $($failing -join ', ')" }
                  elseif ($sameFiles) { "the same files changed three iterations running with no task ticked" }
                  else { "the diff contains a placeholder" }
    }
    Write-State $number $state

    switch ($marker) {
        "DONE"  { Log "#${number}: done for this iteration" }
        "HUMAN" { Set-Human $number $detail }
        "PAUSE" {
            Log "usage limit reached; state written"
            Write-Output $detail
            Write-Output "LOOP-PAUSE"
            exit 75
        }
        default { Set-Human $number "the session ended without a LOOP line; see the loop log" }
    }
    if ($Once) { break }
}
Log "loop ended"
