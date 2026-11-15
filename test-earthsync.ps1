[CmdletBinding()]
param([switch]$Full)
& (Join-Path $PSScriptRoot 'scripts\local\earthsync.ps1') test -Full:$Full
