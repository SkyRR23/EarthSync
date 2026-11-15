[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [ValidateSet('setup','start','stop','test','logs','status','reset-demo')]
    [string]$Action = 'start',
    [switch]$NoBrowser,
    [switch]$Rebuild,
    [switch]$Full,
    [switch]$Yes
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$venvPython = Join-Path $repo '.venv\Scripts\python.exe'
$pythonExe = $null
if (Test-Path -LiteralPath $venvPython) { $pythonExe = $venvPython }
if (-not $pythonExe) {
    foreach ($candidate in @('python','python3')) {
        $found = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($found) {
            & $found.Source -c 'import sys; sys.exit(0 if sys.version_info >= (3,12) else 1)' 2>$null
            if ($LASTEXITCODE -eq 0) { $pythonExe = $found.Source; break }
        }
    }
}
if (-not $pythonExe) {
    $launcher = Get-Command py -ErrorAction SilentlyContinue
    if ($launcher) {
        $resolved = & $launcher.Source -3.12 -c 'import sys; print(sys.executable)' 2>$null
        if ($LASTEXITCODE -eq 0) { $pythonExe = $resolved.Trim() }
    }
}
if (-not $pythonExe) { throw 'Python 3.12+ missing. Install Python from python.org with Add Python to PATH, then reopen PowerShell.' }
$arguments = @((Join-Path $PSScriptRoot 'earthsync.py'), $Action)
if ($NoBrowser) { $arguments += '--no-browser' }
if ($Rebuild) { $arguments += '--rebuild' }
if ($Full) { $arguments += '--full' }
if ($Yes) { $arguments += '--yes' }
& $pythonExe @arguments
if ($LASTEXITCODE -ne 0) { throw "EarthSync $Action failed (exit $LASTEXITCODE). See .earthsync-runtime logs." }
