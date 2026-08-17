#requires -Version 5.1
#requires -Modules ActiveDirectory, GroupPolicy
[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\LabConfig.psd1'),
    [string]$UsersPath = (Join-Path $PSScriptRoot '..\data\Users.csv'),
    [string]$SharesPath = (Join-Path $PSScriptRoot '..\data\Shares.csv'),
    [string]$ExportPath,
    [switch]$SkipSampleUsers,
    [switch]$FailOnError
)

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
Import-Module GroupPolicy
Import-Module (Join-Path $PSScriptRoot '..\modules\ReedLab\ReedLab.psd1') -Force

$config = Get-ReedLabConfig -Path $ConfigPath
Assert-ReedLabSafety -Config $config
$checks = [System.Collections.Generic.List[object]]::new()

function Add-Validation {
    param([string]$Area, [string]$Check, [bool]$Passed, [string]$Detail)
    $checks.Add([pscustomobject]@{
        Area   = $Area
        Check  = $Check
        Result = $(if ($Passed) { 'PASS' } else { 'FAIL' })
        Detail = $Detail
    })
}

$domain = Get-ADDomain
Add-Validation 'Directory' 'Domain identity' ($domain.DNSRoot -eq $config.Domain.Fqdn) $domain.DNSRoot

foreach ($ou in $config.OrganizationalUnits) {
    $dn = "OU=$($ou.Name),$($ou.Parent)"
    $exists = [bool](Get-ADOrganizationalUnit -Identity $dn -ErrorAction SilentlyContinue)
    Add-Validation 'Directory' "OU $($ou.Name)" $exists $dn
}

$requiredGroups = @(
    'GG_Engineering_Users', 'GG_Operations_Users', 'GG_Finance_Users', 'GG_People_Users',
    'GG_All_Users', 'GG_Server_Admins', 'GG_Tier0_Admins', 'GG_LAPS_Readers'
)
$shareDefinitions = @(Import-Csv -LiteralPath $SharesPath)
$requiredGroups += @($shareDefinitions | ForEach-Object { $_.ReadGroup; $_.ModifyGroup })
foreach ($name in $requiredGroups) {
    $exists = [bool](Get-ADGroup -Identity $name -ErrorAction SilentlyContinue)
    Add-Validation 'Access' "Group $name" $exists $name
}

foreach ($department in 'Engineering', 'Operations', 'Finance', 'People') {
    $target = "DL_${department}_Modify"
    $member = "GG_${department}_Users"
    $nested = [bool](Get-ADGroupMember -Identity $target -ErrorAction SilentlyContinue | Where-Object Name -eq $member)
    Add-Validation 'Access' "$member nested in $target" $nested "$member -> $target"
}
$commonNested = [bool](Get-ADGroupMember -Identity DL_Common_Read -ErrorAction SilentlyContinue | Where-Object Name -eq 'GG_All_Users')
Add-Validation 'Access' 'All users have Common read role' $commonNested 'GG_All_Users -> DL_Common_Read'

if (-not $SkipSampleUsers) {
    foreach ($sample in (Import-Csv -LiteralPath $UsersPath)) {
        $user = Get-ADUser -Identity $sample.SamAccountName -ErrorAction SilentlyContinue
        Add-Validation 'Directory' "Fictional user $($sample.SamAccountName)" ([bool]$user) $sample.Department
    }
}

$expectedComputers = @(
    @{ Name = $config.Computers.FileServer.Name; Ou = 'Servers' }
    @{ Name = $config.Computers.Client01.Name; Ou = 'Workstations' }
    @{ Name = $config.Computers.Client02.Name; Ou = 'Workstations' }
)
foreach ($expected in $expectedComputers) {
    $computer = Get-ADComputer -Identity $expected.Name -ErrorAction SilentlyContinue
    $inCorrectOu = $computer -and $computer.DistinguishedName -like "CN=$($expected.Name),OU=$($expected.Ou),OU=ReedLab,*"
    Add-Validation 'Directory' "Computer $($expected.Name) OU" ([bool]$inCorrectOu) $expected.Ou
}

$requiredGpos = @(
    'ReedLab - Workstation Baseline',
    'ReedLab - Server Baseline',
    'ReedLab - Audit and PowerShell Logging',
    'ReedLab - Windows LAPS',
    'ReedLab - Event Forwarding'
)
foreach ($name in $requiredGpos) {
    $exists = [bool](Get-GPO -Name $name -ErrorAction SilentlyContinue)
    Add-Validation 'Policy' $name $exists $name
}

$policy = Get-ADDefaultDomainPasswordPolicy
Add-Validation 'Security' 'Minimum password length' ($policy.MinPasswordLength -ge $config.Security.MinimumPasswordLength) "$($policy.MinPasswordLength) characters"
Add-Validation 'Security' 'Account lockout threshold' ($policy.LockoutThreshold -eq $config.Security.LockoutThreshold) "$($policy.LockoutThreshold) attempts"

$schemaNc = (Get-ADRootDSE).schemaNamingContext
$lapsPresent = [bool](Get-ADObject -SearchBase $schemaNc -LDAPFilter '(lDAPDisplayName=msLAPS-PasswordExpirationTime)' -ErrorAction SilentlyContinue)
Add-Validation 'Security' 'Windows LAPS schema' $lapsPresent 'msLAPS-PasswordExpirationTime'

$fileServer = $config.EventForwarding.CollectorFqdn
$dnsResolved = [bool](Resolve-DnsName $fileServer -ErrorAction SilentlyContinue)
Add-Validation 'Network' 'File server DNS' $dnsResolved $fileServer
if ($dnsResolved) {
    $smb = Test-NetConnection $fileServer -Port 445 -InformationLevel Quiet
    $wec = Test-NetConnection $fileServer -Port 5985 -InformationLevel Quiet
    Add-Validation 'Network' 'SMB reachable' $smb "$fileServer`:445"
    Add-Validation 'Monitoring' 'WinRM/WEC reachable' $wec "$fileServer`:5985"
}

$checks | Format-Table -AutoSize -Wrap
if ($ExportPath) {
    $checks | Export-Csv -LiteralPath $ExportPath -NoTypeInformation -Encoding UTF8
    Write-Host "Validation report exported to $ExportPath" -ForegroundColor Cyan
}

$failures = @($checks | Where-Object Result -eq 'FAIL')
Write-Host "`n$($checks.Count - $failures.Count)/$($checks.Count) checks passed." -ForegroundColor $(if ($failures.Count) { 'Yellow' } else { 'Green' })
if ($FailOnError -and $failures.Count) {
    throw "$($failures.Count) validation check(s) failed."
}
