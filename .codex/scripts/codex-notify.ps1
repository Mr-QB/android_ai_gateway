# SETUP_AGENT_PROJECT_NTFY_WRAPPER
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$projectName = Split-Path -Leaf $projectRoot
$codexExitCode = 127

try {
    $codexCommand = Get-Command codex -CommandType Application -All -ErrorAction Stop | Select-Object -First 1
    & $codexCommand.Source @args
    $codexExitCode = $LASTEXITCODE
} catch {
    [Console]::Error.WriteLine('codex-notify: could not run Codex: ' + $_.Exception.Message)
    exit 127
}

if ($env:CODEX_NTFY_DISABLE -eq '1') {
    exit $codexExitCode
}

$endpoint = $env:CODEX_NTFY_URL
if ([string]::IsNullOrWhiteSpace($endpoint)) {
    $endpoint = 'https://ntfy.sh/codex_x99'
}

if ($codexExitCode -eq 0) {
    $title = 'Codex finished'
    $message = "Project: $projectName`nCodex session completed successfully."
} else {
    $title = 'Codex failed'
    $message = "Project: $projectName`nCodex exited with code $codexExitCode."
}

try {
    $curlCommand = Get-Command curl -CommandType Application -All -ErrorAction Stop | Select-Object -First 1
    & $curlCommand.Source --fail --silent --max-time 5 `
        -H "Title: $title" --data-binary $message $endpoint | Out-Null
    if ($LASTEXITCODE -ne 0) {
        [Console]::Error.WriteLine('codex-notify: ntfy request failed; Codex exit status is unchanged.')
    }
} catch {
    [Console]::Error.WriteLine('codex-notify: notification failed; Codex exit status is unchanged.')
}

exit $codexExitCode
