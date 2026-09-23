#Requires -Version 7
<#
The unattended loop: one issue task per iteration, fresh context, as the organisation's
GitHub App. Reads loop.local.json beside this script (gitignored):
  { "appId": 0, "installationId": 0, "keyPath": "...pem", "base": "D:\\GitRepos\\Claude" }
Run attended first:  .\loop.ps1 -Once
Stop a running or scheduled loop:  New-Item <base>\state\stop-requested
On a usage limit the loop schedules itself for the reset time as a Windows scheduled task.
Every session run appends one JSON line to <base>\state\token-usage.jsonl (tokens, cost,
per-model split, peak context, subagent census, limit utilisation), so a cost question is
one pipeline:  Get-Content <base>\state\token-usage.jsonl | ConvertFrom-Json | Measure-Object cost -Sum
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
$usageFile = Join-Path $base "state" "token-usage.jsonl"
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

# The next unticked task's tag decides the model and the effort: [tier: sonnet] or
# [tier: opus, effort: max]; effort is high unless the tag says otherwise. Session-tier
# work is not the loop's.
function Get-TaskTag([string]$body) {
    $in = $false
    foreach ($line in $body -split "`n") {
        $t = $line.Trim()
        if ($t.StartsWith("### ")) { $in = ($t -eq "### Plan"); continue }
        if ($in -and $t.StartsWith("- [ ]")) {
            if ($t -match '\[tier:\s*(haiku|sonnet|opus|session)(?:,\s*effort:\s*(low|medium|high|max))?\]') {
                return @($Matches[1], $(if ($Matches.ContainsKey(2)) { $Matches[2] } else { "high" }))
            }
            return @("sonnet", "high")
        }
    }
    @("sonnet", "high")
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

function Get-RetryTime([string]$text, $rateLimit) {
    if ($rateLimit -and (Get-Field $rateLimit resetsAt)) {
        return [DateTimeOffset]::FromUnixTimeSeconds([int64]$rateLimit.resetsAt).LocalDateTime.AddMinutes(2)
    }
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

# Strict mode throws on a property the CLI's JSON did not send; absent reads as null.
function Get-Field($object, [string]$name) {
    if ($null -ne $object -and $object.PSObject.Properties[$name]) { $object.$name } else { $null }
}

# stream-json rather than text: the log keeps every message with its own usage, and the
# result line carries the session ID, token counts, cost and per-model usage. Peak context
# is the largest prompt any assistant message paid for, which is what tells a bloated
# context from a long task when a run costs more than expected.
function Invoke-Session([string]$dir, [string]$prompt, [string]$model, [string]$effort, [string]$logPath) {
    $env:WORK_IDENTITY = $identity
    $started = Get-Date
    Push-Location $dir
    try {
        $lines = @(& claude -p $prompt --model $model --effort $effort --dangerously-skip-permissions --output-format stream-json --verbose 2>&1 |
            ForEach-Object { "$_" } | Tee-Object -FilePath $logPath)
    }
    finally { Pop-Location }
    $session = Read-Stream $lines
    $session.Seconds = [int]((Get-Date) - $started).TotalSeconds
    $script:lastRateLimit = $session.RateLimit
    $session
}

function Read-Stream([string[]]$lines) {
    $session = @{ Result = $null; Text = ($lines -join "`n"); Raw = ($lines -join "`n"); PeakContext = [int64]0; RateLimit = $null; Seconds = 0 }
    foreach ($line in $lines) {
        if (-not $line.StartsWith("{")) { continue }
        try { $message = $line | ConvertFrom-Json } catch { continue }
        switch (Get-Field $message type) {
            "assistant" {
                $usage = Get-Field (Get-Field $message message) usage
                $context = [int64](Get-Field $usage input_tokens) + [int64](Get-Field $usage cache_read_input_tokens) + [int64](Get-Field $usage cache_creation_input_tokens)
                if ($context -gt $session.PeakContext) { $session.PeakContext = $context }
            }
            "rate_limit_event" { $session.RateLimit = Get-Field $message rate_limit_info }
            "result" {
                $session.Result = $message
                if (Get-Field $message result) { $session.Text = $message.result }
            }
        }
    }
    $session
}

# Which model actually served each subagent, from the assistant messages' own model field:
# a pinned dispatch can be served by another model and nothing else records it. Only that
# field counts, because a transcript quotes model names in prompts and tool output too.
# Counts are transcripts per model, found by session ID under whichever project directory
# holds it.
function Get-SubagentModels([string]$sessionId) {
    $models = @{}
    if (-not $sessionId) { return $models }
    $root = Get-ChildItem (Join-Path $env:USERPROFILE ".claude\projects") -Directory -Depth 1 -Filter $sessionId -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $root) { return $models }
    foreach ($file in Get-ChildItem $root.FullName -Recurse -Filter 'agent-*.jsonl') {
        $seen = @{}
        foreach ($line in Get-Content $file.FullName) {
            if (-not $line.StartsWith('{"') -or $line -notmatch '"type":"assistant"') { continue }
            try { $message = $line | ConvertFrom-Json } catch { continue }
            if ((Get-Field $message type) -ne "assistant") { continue }
            $name = Get-Field (Get-Field $message message) model
            if ($name) { $seen[$name] = $true }
        }
        foreach ($name in $seen.Keys) { $models[$name] = 1 + $(if ($models.ContainsKey($name)) { $models[$name] } else { 0 }) }
    }
    $models
}

# One JSON line per session run, every repository in one file. Each run is its own
# session, so a line is a complete figure: summing lines never double-counts.
function Write-Usage([int]$number, [int]$iteration, [string]$tier, [string]$model, [string]$effort, [string]$outcome, $session, [string]$logPath) {
    $result = $session.Result
    $usage = Get-Field $result usage
    $models = [ordered]@{}
    $modelUsage = Get-Field $result modelUsage
    if ($modelUsage) {
        foreach ($p in $modelUsage.PSObject.Properties | Sort-Object Name) {
            $models[$p.Name] = [ordered]@{ in = [int64](Get-Field $p.Value inputTokens); cache_write = [int64](Get-Field $p.Value cacheCreationInputTokens)
                                           cache_read = [int64](Get-Field $p.Value cacheReadInputTokens); out = [int64](Get-Field $p.Value outputTokens)
                                           cost = [math]::Round([double](Get-Field $p.Value costUSD), 4) }
        }
    }
    $sessionId = [string](Get-Field $result session_id)
    $windows = Get-Field $session.RateLimit unifiedWindows
    $record = [ordered]@{
        at = (Get-Date).ToString('s'); repo = $Repo; issue = $number; iteration = $iteration
        tier = $tier; model = $model; effort = $effort; outcome = $outcome; seconds = $session.Seconds
        session_id = $sessionId; turns = [int](Get-Field $result num_turns)
        in = [int64](Get-Field $usage input_tokens); cache_write = [int64](Get-Field $usage cache_creation_input_tokens)
        cache_read = [int64](Get-Field $usage cache_read_input_tokens); out = [int64](Get-Field $usage output_tokens)
        thinking = [int64](Get-Field (Get-Field $usage output_tokens_details) thinking_tokens)
        peak_context = $session.PeakContext; cost = [math]::Round([double](Get-Field $result total_cost_usd), 4)
        models = $models
        subagents_spawned = [int](Get-Field (Get-Field $result subagent_stats) spawned)
        subagent_models = Get-SubagentModels $sessionId
        five_hour = [double](Get-Field (Get-Field $windows five_hour) utilization)
        seven_day = [double](Get-Field (Get-Field $windows seven_day) utilization)
        log = $logPath
    }
    try { ($record | ConvertTo-Json -Compress -Depth 4) | Add-Content $usageFile } catch { Log "usage record not written: $($_.Exception.Message)" }
    Log ("#{0}: {1} on {2}: {3} turns, {4}s, in={5} cache_read={6} out={7} peak={8}k cost=`${9} 5h={10}% 7d={11}%" -f $number, $outcome, $model,
        $record.turns, $record.seconds, ($record.in + $record.cache_write), $record.cache_read, $record.out, [int]($record.peak_context / 1000), $record.cost,
        [int]($record.five_hour * 100), [int]($record.seven_day * 100))
}

function Get-Marker([string]$text) {
    if ($text -match '(?im)(reached|hit)\s.*\blimit\b|usage limit|rate limit') { return @("PAUSE", $text) }
    $lines = @($text -split "`n" | Where-Object { $_.Trim() })
    if ($lines.Count -gt 0 -and $lines[-1].Trim() -match '^LOOP:\s*(DONE|ROUTE-UP|HUMAN)\b\s*(.*)$') { return @($Matches[1], $Matches[2]) }
    @("NONE", "")
}

# One session, its marker, and its usage record.
function Invoke-Task([int]$number, [int]$iteration, [string]$worktree, $issue, [string]$learnings, [string]$notes, [string]$tier, [string]$model, [string]$effort, [string]$logPath) {
    $session = Invoke-Session $worktree (Build-Prompt $issue $learnings $notes) $model $effort $logPath
    $marker, $detail = Get-Marker $session.Text
    Write-Usage $number $iteration $tier $model $effort $marker $session $logPath
    @($session, $marker, $detail)
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
    if ($pick.claimed_by -ne $identity) {
        Push-Location $repoDir
        try { $claim = & work claim $number 2>&1; $lost = $LASTEXITCODE -ne 0 } finally { Pop-Location }
        if ($lost) { Log "#${number}: $claim; picking again next iteration"; return "continue" }
    }
    Log "#${number}: $($issue.title)"

    $tier, $effort = if ($pick.planned) { Get-TaskTag $issue.body } else { @("sonnet", "high") }
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
    $session, $marker, $detail = Invoke-Task $number $state.iterations $worktree $issue $learnings $state.notes $tier $tier $effort $log

    if ($marker -eq "ROUTE-UP") {
        $up = Next-Tier $tier
        if ($up) {
            Log "#${number}: routing up to $up"
            $state.notes = $detail
            $session, $marker, $detail = Invoke-Task $number $state.iterations $worktree $issue $learnings $state.notes $tier $up $effort "$log.escalated"
        }
        if ($marker -eq "ROUTE-UP") { $marker = "HUMAN"; $detail = "failed after routing up: $detail" }
    }

    $lastLines = ($session.Text -split "`n" | Select-Object -Last 40) -join "`n"
    if ($marker -eq "PAUSE") {
        $state.notes = $lastLines
        Write-State $number $state
        return "pause:" + $detail
    }

    # The gutter detector: the same failing test, or the same files churned with no box ticked,
    # three iterations running; or a placeholder that passes. Test names are read from the
    # raw stream, where tool output is JSON-escaped, so the name stops at a backslash.
    $failing = @([regex]::Matches($session.Raw, '--- FAIL: ([^\s\\"]+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $changed = @(& git.exe -C $worktree diff --name-only origin/development | Sort-Object)
    Push-Location $repoDir; & work refresh 2>&1 | Out-Null; Pop-Location
    $after = Get-Content (Join-Path $repoDir "issues.jsonl") | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object number -eq $number
    $ticked = $after -and ([regex]::Matches($after.body, '- \[x\]')).Count -gt $ticksBefore
    $state.failingTests = @($state.failingTests + , $failing | Select-Object -Last 3)
    $state.changedFiles = @($state.changedFiles + , $changed | Select-Object -Last 3)
    if ($ticked) { $state.ticks++; $state.notes = "" } else { $state.notes = $lastLines }
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
$script:lastRateLimit = $null
$loopState = Read-LoopState
try {
    $env:GH_TOKEN = New-InstallationToken
    Ensure-Clone $repoDir "https://github.com/$Owner/$Repo.git"
    Ensure-Clone $wikiDir "https://github.com/$Owner/$Repo.wiki.git"
    Invoke-Git $repoDir fetch --quiet --prune origin | Out-Null
    Invoke-Git $repoDir checkout --quiet development | Out-Null
    Invoke-Git $repoDir reset --quiet --hard origin/development | Out-Null
    Invoke-Git $wikiDir fetch --quiet origin | Out-Null
    Invoke-Git $wikiDir reset --quiet --hard origin/master | Out-Null

    for ($iteration = 1; $iteration -le $MaxIterations; $iteration++) {
        if (Test-Path $stopFile) { Log "stop requested; ending"; break }
        if ($iteration % 4 -eq 0) { $env:GH_TOKEN = New-InstallationToken }
        $result = Invoke-Iteration $iteration
        $loopState.consecutiveFailures = 0
        Write-LoopState $loopState
        if ($result -eq "empty") { Log "nothing to do"; break }
        if ($result.StartsWith("pause:")) {
            $at = Get-RetryTime $result.Substring(6) $script:lastRateLimit
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
