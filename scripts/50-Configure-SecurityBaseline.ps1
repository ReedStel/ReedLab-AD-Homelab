#requires -Version 5.1
#requires -Modules ActiveDirectory, GroupPolicy
#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\LabConfig.psd1'),
    [switch]$ExtendLapsSchema
)

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
Import-Module GroupPolicy
Import-Module (Join-Path $PSScriptRoot '..\modules\ReedLab\ReedLab.psd1') -Force

Assert-ReedLabAdministrator
$config = Get-ReedLabConfig -Path $ConfigPath
Assert-ReedLabSafety -Config $config

if ($env:COMPUTERNAME -ne $config.Computers.DomainController.Name) {
    throw "Run this script only on $($config.Computers.DomainController.Name)."
}

$domainDn = $config.Domain.DistinguishedName
$reedLabOu = "OU=ReedLab,$domainDn"
$workstationsOu = "OU=Workstations,$reedLabOu"
$serversOu = "OU=Servers,$reedLabOu"

function Set-GpoDword {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Name, [string]$Key, [string]$ValueName, [int]$Value)
    if ($PSCmdlet.ShouldProcess("$Name :: $Key\$ValueName", "Set DWORD to $Value")) {
        Set-GPRegistryValue -Name $Name -Key $Key -ValueName $ValueName -Type DWord -Value $Value | Out-Null
    }
}

function Set-GpoString {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Name, [string]$Key, [string]$ValueName, [string]$Value)
    if ($PSCmdlet.ShouldProcess("$Name :: $Key\$ValueName", 'Set string policy value')) {
        Set-GPRegistryValue -Name $Name -Key $Key -ValueName $ValueName -Type String -Value $Value | Out-Null
    }
}

Write-ReedLabStep 'Creating and linking security GPOs'
$workstationGpo = 'ReedLab - Workstation Baseline'
$serverGpo = 'ReedLab - Server Baseline'
$auditGpo = 'ReedLab - Audit and PowerShell Logging'
$lapsGpo = 'ReedLab - Windows LAPS'
$lapsReader = "$($config.Domain.NetBIOS)\GG_LAPS_Readers"

Ensure-ReedLabGpo -Name $workstationGpo -Target $workstationsOu -Description 'UAC, Defender PUA protection, and SMBv1 controls' -WhatIf:$WhatIfPreference | Out-Null
Ensure-ReedLabGpo -Name $serverGpo -Target $serversOu -Description 'UAC and SMBv1 controls for member servers' -WhatIf:$WhatIfPreference | Out-Null
Ensure-ReedLabGpo -Name $auditGpo -Target $reedLabOu -Description 'PowerShell visibility and command-line process auditing' -WhatIf:$WhatIfPreference | Out-Null
Ensure-ReedLabGpo -Name $lapsGpo -Target $workstationsOu -Description 'Windows LAPS backed by Active Directory' -WhatIf:$WhatIfPreference | Out-Null
Ensure-ReedLabGpo -Name $lapsGpo -Target $serversOu -Description 'Windows LAPS backed by Active Directory' -WhatIf:$WhatIfPreference | Out-Null

$systemPolicy = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System'
$smbPolicy = 'HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'
foreach ($gpo in $workstationGpo, $serverGpo) {
    Set-GpoDword -Name $gpo -Key $systemPolicy -ValueName EnableLUA -Value 1
    Set-GpoDword -Name $gpo -Key $systemPolicy -ValueName ConsentPromptBehaviorAdmin -Value 2
    Set-GpoDword -Name $gpo -Key $systemPolicy -ValueName PromptOnSecureDesktop -Value 1
    Set-GpoDword -Name $gpo -Key $smbPolicy -ValueName SMB1 -Value 0
}

Set-GpoDword -Name $workstationGpo -Key 'HKLM\Software\Policies\Microsoft\Windows Defender\MpEngine' -ValueName MPEnablePus -Value 1
Set-GpoDword -Name $auditGpo -Key 'HKLM\Software\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' -ValueName EnableScriptBlockLogging -Value 1
Set-GpoDword -Name $auditGpo -Key 'HKLM\Software\Policies\Microsoft\Windows\PowerShell\ModuleLogging' -ValueName EnableModuleLogging -Value 1
Set-GpoString -Name $auditGpo -Key 'HKLM\Software\Policies\Microsoft\Windows\PowerShell\ModuleLogging\ModuleNames' -ValueName '*' -Value '*'
Set-GpoDword -Name $auditGpo -Key 'HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System\Audit' -ValueName ProcessCreationIncludeCmdLine_Enabled -Value 1

$lapsPolicy = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\LAPS'
Set-GpoDword -Name $lapsGpo -Key $lapsPolicy -ValueName BackupDirectory -Value 2
Set-GpoDword -Name $lapsGpo -Key $lapsPolicy -ValueName PasswordAgeDays -Value $config.Security.LapsPasswordAgeDays
Set-GpoDword -Name $lapsGpo -Key $lapsPolicy -ValueName PasswordLength -Value $config.Security.LapsPasswordLength
Set-GpoDword -Name $lapsGpo -Key $lapsPolicy -ValueName PasswordComplexity -Value 4
Set-GpoDword -Name $lapsGpo -Key $lapsPolicy -ValueName ADPasswordEncryptionEnabled -Value 1
Set-GpoString -Name $lapsGpo -Key $lapsPolicy -ValueName ADPasswordEncryptionPrincipal -Value $lapsReader
Set-GpoDword -Name $lapsGpo -Key $lapsPolicy -ValueName PasswordExpirationProtectionEnabled -Value 1

if (-not (Get-Command Update-LapsADSchema -ErrorAction SilentlyContinue)) {
    Write-Warning 'The Windows LAPS PowerShell module is unavailable. Install current Windows updates/RSAT, then rerun with -ExtendLapsSchema.'
    return
}

if ($ExtendLapsSchema -and $PSCmdlet.ShouldProcess($config.Domain.Fqdn, 'Extend the AD schema for Windows LAPS')) {
    Update-LapsADSchema -Confirm:$false
}

$schemaNc = (Get-ADRootDSE).schemaNamingContext
$lapsAttribute = Get-ADObject -SearchBase $schemaNc -LDAPFilter '(lDAPDisplayName=msLAPS-PasswordExpirationTime)' -ErrorAction SilentlyContinue
if (-not $lapsAttribute) {
    Write-Warning 'LAPS schema attributes are not present. Rerun with -ExtendLapsSchema using a Schema Admin account.'
    return
}

foreach ($ou in $workstationsOu, $serversOu) {
    if ($PSCmdlet.ShouldProcess($ou, 'Delegate Windows LAPS self-write, read, and auditing permissions')) {
        Set-LapsADComputerSelfPermission -Identity $ou -Confirm:$false | Out-Null
        Set-LapsADReadPasswordPermission -Identity $ou -AllowedPrincipals $lapsReader -Confirm:$false | Out-Null
        Set-LapsADAuditing -Identity $ou -AuditedPrincipals $lapsReader -AuditType Success -Confirm:$false | Out-Null
    }
}

Write-Host 'Security GPO and Windows LAPS configuration completed.' -ForegroundColor Green
