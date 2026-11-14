param(
    [Parameter(Mandatory=$true)][string]$State,
    [Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments
)
$ErrorActionPreference = 'Stop'
$State = [IO.Path]::GetFullPath($State)
# This is a dedicated operations directory, never a user's home/shared folder.
if ((Test-Path -LiteralPath $State) -and
    (Get-ChildItem -LiteralPath $State -Force | Select-Object -First 1) -and
    -not (Test-Path -LiteralPath (Join-Path $State 'manifest.json'))) {
    throw 'Use a new empty state directory or an existing staging manifest; refusing to change ACLs on an unrelated folder'
}
[IO.Directory]::CreateDirectory($State) | Out-Null
$item = Get-Item -LiteralPath $State -Force
if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'State cannot be a reparse point' }
$acl = New-Object System.Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true, $false)
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
foreach ($account in @($identity, 'NT AUTHORITY\SYSTEM')) {
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($account, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    $acl.AddAccessRule($rule)
}
Set-Acl -LiteralPath $State -AclObject $acl
& py -3.12 (Join-Path $PSScriptRoot 'staging.py') @Arguments --state $State
exit $LASTEXITCODE
