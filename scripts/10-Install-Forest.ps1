#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Security.SecureString]$DirectoryServicesRestoreModePassword,
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\LabConfig.psd1'),
    [switch]$Restart
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\modules\ReedLab\ReedLab.psd1') -Force

Assert-ReedLabAdministrator
$config = Get-ReedLabConfig -Path $ConfigPath
Assert-ReedLabSafety -Config $config -AllowWorkgroup

if ($env:COMPUTERNAME -ne $config.Computers.DomainController.Name) {
    throw "Rename this disposable VM to $($config.Computers.DomainController.Name) before creating the forest."
}

$computer = Get-CimInstance Win32_ComputerSystem
if ($computer.PartOfDomain) {
    if ($computer.Domain -eq $config.Domain.Fqdn) {
        Write-Host "$env:COMPUTERNAME is already joined to $($config.Domain.Fqdn). Nothing to do."
        return
    }
    throw "This VM is already joined to $($computer.Domain)."
}

if (-not $DirectoryServicesRestoreModePassword -and -not $WhatIfPreference) {
    $DirectoryServicesRestoreModePassword = Read-Host 'Enter a strong DSRM password (it will not be displayed)' -AsSecureString
}

Write-ReedLabStep 'Installing AD DS and management tools'
if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Install AD-Domain-Services and RSAT-ADDS features')) {
    $feature = Install-WindowsFeature AD-Domain-Services, RSAT-ADDS -IncludeManagementTools
    if (-not $feature.Success) {
        throw 'Windows feature installation did not complete successfully.'
    }
}

if (-not (Get-Module -ListAvailable -Name ADDSDeployment)) {
    if ($WhatIfPreference) {
        Write-Warning 'ADDSDeployment is not installed yet; the preview stops after the feature-install action.'
        return
    }
    throw 'The ADDSDeployment module is unavailable after feature installation.'
}

Import-Module ADDSDeployment
Write-ReedLabStep "Creating the $($config.Domain.Fqdn) forest"
if ($PSCmdlet.ShouldProcess($config.Domain.Fqdn, 'Install a new AD DS forest')) {
    $parameters = @{
        DomainName                    = $config.Domain.Fqdn
        DomainNetbiosName             = $config.Domain.NetBIOS
        DomainMode                    = $config.Domain.DomainMode
        ForestMode                    = $config.Domain.ForestMode
        InstallDns                    = $true
        SafeModeAdministratorPassword = $DirectoryServicesRestoreModePassword
        NoRebootOnCompletion           = $true
        Force                         = $true
    }
    Install-ADDSForest @parameters
}

if ($Restart -and $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Restart to complete forest installation')) {
    Restart-Computer -Force
} else {
    Write-Warning 'Restart the VM before running 20-Build-Directory.ps1.'
}
