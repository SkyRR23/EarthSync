[CmdletBinding()]
param([switch]$NoBrowser, [switch]$Rebuild)
& (Join-Path $PSScriptRoot 'scripts\local\earthsync.ps1') start -NoBrowser:$NoBrowser -Rebuild:$Rebuild
