$ErrorActionPreference = 'Stop'

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$pythonExecutable = $null
$pythonPrefix = @()

foreach ($candidate in @('python', 'py')) {
    $command = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        continue
    }
    if ($candidate -eq 'py') {
        $prefix = @('-3')
    }
    else {
        $prefix = @()
    }
    & $command.Source @prefix -c 'import sys; raise SystemExit(sys.version_info < (3, 11))'
    if ($LASTEXITCODE -eq 0) {
        $pythonExecutable = $command.Source
        $pythonPrefix = $prefix
        break
    }
}

if ($null -eq $pythonExecutable) {
    [Console]::Error.WriteLine('ai-config requires Python 3.11 or newer.')
    exit 1
}

if ([string]::IsNullOrWhiteSpace($env:PYTHONPATH)) {
    $env:PYTHONPATH = $scriptDirectory
}
else {
    $env:PYTHONPATH = $scriptDirectory + [IO.Path]::PathSeparator + $env:PYTHONPATH
}
$env:AI_CONFIG_ENTRYPOINT = '.\ai-config.ps1'

& $pythonExecutable @pythonPrefix -m ai_config @args
exit $LASTEXITCODE
