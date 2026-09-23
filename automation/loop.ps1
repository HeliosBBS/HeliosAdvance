#Requires -Version 7
<#
The unattended loop: one issue task per iteration, fresh context, as the organisation's
GitHub App. Reads loop.local.json beside this script (gitignored):
  { "appId": 0, "installationId": 0, "keyPath": "...pem", "base": "D:\\GitRepos\\Claude" }
Run attended first:  .\loop.ps1 -Once
Stop a running or scheduled loop:  New-Item <base>\state\stop-requested
On a usage limit the loop schedules itself for the reset time as a Windows scheduled task.
#>
param(
    [string]$Repo = "HeliosAdvance",
    [string]$Owner = "HeliosBBS",
    [switch]$Once,
    [int]$MaxIterations = 50,
    [int]$MaxConsecutiveFailures = 3,
    [string]$TaskName = "HeliosLoop"
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
$stopFile = Join-Path $base "state" "stop-requested"
$loopStateFile = Join-Path $base "state" "loop.json"
$tiers = @("haiku", "sonnet", "opus")
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
        & git.exe clone --quiet $url $dir 2>&1 | Out-Null
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

function Read-LoopState {
    if (Test-Path $loopStateFile) { Get-Content $loopStateFile -Raw | ConvertFrom-Json }
    else { [pscustomobject]@{ consecutiveFailures = 0 } }
}

function Write-LoopState($state) { $state | ConvertTo-Json | Set-Content $loopStateFile }

# The next unticked task's tier decides the model; session-tier work is not the loop's.
function Get-TaskTier([string]$body) {
    $in = $false
    foreach ($line in $body -split "`n") {
        $t = $line.Trim()
        if ($t.StartsWith("### ")) { $in = ($t -eq "### Plan"); continue }
        if ($in -and $t.StartsWith("- [ ]")) {
            if ($t -match '\[tier:\s*(haiku|sonnet|opus|session)\]') { return $Matches[1] }
            return "sonnet"
        }
    }
    "sonnet"
}

function Next-Tier([string]$tier) {
    $i = [array]::IndexOf($tiers, $tier)
    if ($i -lt 0 -or $i -ge $tiers.Count - 1) { return $null }
    $tiers[$i + 1]
}

# ---- usage limits: parse the reset time out of the message and come back then ----
# "Aug 18, 11pm" is year-less and bare Parse misreads the hour as a two-digit year,
# so the explicit shapes are tried first.
function Get-ResetDateTime([string]$text) {
    $m = [regex]::Match($text, '(?im)(?:reached|hit).*?limit.*?resets?(?:\s+at)?\s+(?<reset>[^()\r\n]+?)(?:\s*\([^)]+\))?[.\s]*$')
    if (-not $m.Success) { return $null }
    $resetText = $m.Groups['reset'].Value.Trim()
    $now = Get-Date
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $parsed = $null
    foreach ($fmt in @('htt', 'h:mmtt', 'HH:mm')) {
        try { $parsed = $now.Date + [datetime]::ParseExact($resetText, $fmt, $culture).TimeOfDay; break } catch { }
    }
    if (-not $parsed) {
        foreach ($fmt in @('MMM d, htt', 'MMM d, h:mmtt', 'MMMM d, htt', 'MMMM d, h:mmtt')) {
            try { $parsed = [datetime]::ParseExact("$resetText $($now.Year)", "$fmt yyyy", $culture); break } catch { }
        }
    }
    if (-not $parsed) { try { $parsed = [datetime]::Parse($resetText, $culture) } catch { return $null } }
    if ($parsed -le $now -and $parsed -gt $now.AddDays(-1)) { $parsed = $parsed.AddDays(1) }
    if ($parsed -le $now -or $parsed -gt $now.AddDays(10)) { return $null }
    $parsed
}

function Get-RetryTime([string]$text) {
    $at = Get-ResetDateTime $text
    if ($at) { return $at.AddMinutes(2) }
    $now = Get-Date
    if ($text -match '(?i)week|fable') {
        $days = (1 + 7 - [int]$now.DayOfWeek) % 7
        if ($days -eq 0) { $days = 7 }
        return $now.Date.AddDays($days).AddHours(23).AddMinutes(2)
    }
    $now.AddHours(5).AddMinutes(2)
}

# schtasks.exe rather than the ScheduledTasks module: it works from a non-elevated
# interactive session and survives a reboot; the task is one fixed name, replaced each time.
function Set-RetryTask([datetime]$at) {
    $pwsh = (Get-Process -Id $PID).Path
    $action = "`"$pwsh`" -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Repo $Repo"
    $out = & schtasks.exe /Create /TN $TaskName /TR $action /SC ONCE /SD $at.ToString('MM/dd/yyyy') /ST $at.ToString('HH:mm') /RL HIGHEST /IT /RU $env:USERNAME /F 2>&1
    if ($LASTEXITCODE -eq 0) { Log "retry scheduled for $($at.ToString('yyyy-MM-dd HH:mm'))" }
    else { Log "schtasks failed: $out" }
}

function Remove-RetryTask { & schtasks.exe /Delete /TN $TaskName /F 2>&1 | Out-Null }

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
    $text = $lines -join "`n"
    if ($text -match '(?im)(reached|hit)\s.*\blimit\b|usage limit|rate limit') { return @("PAUSE", $text) }
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $line = $lines[$i].Trim()
        if ($line -match '^LOOP:\s*(DONE|ROUTE-UP|HUMAN)\b\s*(.*)$') { return @($Matches[1], $Matches[2]) }
        if ($line) { break }
    }
    @("NONE", "")
}

function Invoke-Iteration([int]$iteration) {
    Push-Location $repoDir
    try {
        & work refresh 2>&1 | Out-Null
        $json = & work next --loop 2>$null
        if ($LASTEXITCODE -eq 3) { return "empty" }
        if ($LASTEXITCODE -ne 0) { throw "work next failed" }
    }
    finally { Pop-Location }
    $pick = $json | ConvertFrom-Json
    $number = [int]$pick.number
    $issue = Get-Content (Join-Path $repoDir "issues.jsonl") | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object number -eq $number
    if ($pick.claimed_by -ne $identity) { Push-Location $repoDir; & work claim $number | Out-Null; Pop-Location }
    Log "#${number}: $($issue.title)"

    $tier = if ($pick.planned) { Get-TaskTier $issue.body } else { "sonnet" }
    if ($tier -eq "session") { Set-Human $number "the next task is session-tier: it needs an interactive session with the developer"; return "continue" }

    $branch = "feature/issue-$number-$(Slug $issue.title)"
    $worktree = Join-Path $base "$Repo.wt" ($branch -replace '/', '-')
    if (-not (Test-Path $worktree)) {
        $remote = & git.exe -C $repoDir ls-remote --heads origin $branch
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
            return "continue"
        }
    }
    finally { Pop-Location }

    $learnings = Get-Content (Join-Path $wikiDir "Learnings.md") -Raw
    $ticksBefore = ([regex]::Matches($issue.body, '- \[x\]')).Count
    Log "#${number}: running on $tier"
    $output = Invoke-Session $worktree (Build-Prompt $issue $learnings $state.notes) $tier $log
    $marker, $detail = Get-Marker @($output)

    if ($marker -eq "ROUTE-UP") {
        $up = Next-Tier $tier
        if ($up) {
            Log "#${number}: routing up to $up"
            $state.notes = $detail
            $output = Invoke-Session $worktree (Build-Prompt $issue $learnings $state.notes) $up "$log.escalated"
            $marker, $detail = Get-Marker @($output)
        }
        if ($marker -eq "ROUTE-UP") { $marker = "HUMAN"; $detail = "failed after routing up: $detail" }
    }

    if ($marker -eq "PAUSE") {
        $state.notes = ($output | Select-Object -Last 40) -join "`n"
        Write-State $number $state
        return "pause:" + $detail
    }

    # The gutter detector: the same failing test, or the same files churned with no box ticked,
    # three iterations running; or a placeholder that passes.
    $failing = @([regex]::Matches(($output -join "`n"), '--- FAIL: (\S+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $changed = @(& git.exe -C $worktree diff --name-only origin/development | Sort-Object)
    Push-Location $repoDir; & work refresh 2>&1 | Out-Null; Pop-Location
    $after = Get-Content (Join-Path $repoDir "issues.jsonl") | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object number -eq $number
    $ticked = $after -and ([regex]::Matches($after.body, '- \[x\]')).Count -gt $ticksBefore
    $state.failingTests = @($state.failingTests + , $failing | Select-Object -Last 3)
    $state.changedFiles = @($state.changedFiles + , $changed | Select-Object -Last 3)
    if ($ticked) { $state.ticks++; $state.notes = "" } else { $state.notes = ($output | Select-Object -Last 40) -join "`n" }
    $sameTest = $failing.Count -gt 0 -and $state.failingTests.Count -eq 3 -and (@($state.failingTests | ForEach-Object { $_ -join "," } | Sort-Object -Unique).Count -eq 1)
    $sameFiles = -not $ticked -and $changed.Count -gt 0 -and $state.changedFiles.Count -eq 3 -and (@($state.changedFiles | ForEach-Object { $_ -join "," } | Sort-Object -Unique).Count -eq 1)
    $placeholder = (& git.exe -C $worktree diff origin/development) -match 'TODO|not implemented'
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
        default { Set-Human $number "the session ended without a LOOP line; see the loop log" }
    }
    "continue"
}

# ---- main ----
if (Test-Path $stopFile) { Remove-RetryTask; Log "stop requested ($stopFile); not running"; exit 0 }
Remove-RetryTask
$loopState = Read-LoopState
try {
    $env:GH_TOKEN = New-InstallationToken
    Ensure-Clone $repoDir "https://github.com/$Owner/$Repo.git"
    Ensure-Clone $wikiDir "https://github.com/$Owner/$Repo.wiki.git"
    Invoke-Git $repoDir fetch --quiet --prune origin | Out-Null
    Invoke-Git $repoDir checkout --quiet development | Out-Null
    Invoke-Git $repoDir reset --quiet --hard origin/development | Out-Null
    Invoke-Git $wikiDir pull --quiet --ff-only | Out-Null

    for ($iteration = 1; $iteration -le $MaxIterations; $iteration++) {
        if (Test-Path $stopFile) { Log "stop requested; ending"; break }
        if ($iteration % 4 -eq 0) { $env:GH_TOKEN = New-InstallationToken }
        $result = Invoke-Iteration $iteration
        $loopState.consecutiveFailures = 0
        Write-LoopState $loopState
        if ($result -eq "empty") { Log "nothing to do"; break }
        if ($result.StartsWith("pause:")) {
            $at = Get-RetryTime $result.Substring(6)
            Log "usage limit reached; state written"
            Set-RetryTask $at
            Write-Output ($result.Substring(6) -split "`n" | Where-Object { $_ -match '(?i)limit' } | Select-Object -First 1)
            Write-Output "LOOP-PAUSE"
            exit 75
        }
        if ($Once) { break }
    }
    Log "loop ended"
}
catch {
    $loopState.consecutiveFailures++
    Write-LoopState $loopState
    Log "unexpected error: $($_.Exception.Message)"
    if ($loopState.consecutiveFailures -ge $MaxConsecutiveFailures) {
        Log "$($loopState.consecutiveFailures) consecutive failures; stopping without a retry. Investigate, then run again."
        exit 70
    }
    if (-not $Once) { Set-RetryTask (Get-Date).AddMinutes(15) }
    exit 70
}
