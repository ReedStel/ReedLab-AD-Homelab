#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Server', 'Workstation')]
    [string]$Role,

    [PSCredential]$Credential,
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\LabConfig.psd1'),
    [switch]$Restart
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\modules\ReedLab\ReedLab.psd1') -Force

Assert-ReedLabAdministrator
$config = Get-ReedLabConfig -Path $ConfigPath
Assert-ReedLabSafety -Config $config -AllowWorkgroup

$allowedNames = if ($Role -eq 'Server') {
    @($config.Computers.FileServer.Name)
} else {
    @($config.Computers.Client01.Name, $config.Computers.Client02.Name)
}
if ($env:COMPUTERNAME -notin $allowedNames) {
    throw "Computer name must be $($allowedNames -join ' or ') for the selected role."
}

$computer = Get-CimInstance Win32_ComputerSystem
if ($computer.PartOfDomain) {
    Write-Host "$env:COMPUTERNAME is already joined to $($computer.Domain)."
    return
}

if (-not $Credential -and -not $WhatIfPreference) {
    $Credential = Get-Credential -Message "Enter a $($config.Domain.Fqdn) account allowed to join computers"
}

$adapters = @(Get-NetAdapter -Physical | Where-Object Status -eq Up)
if ($adapters.Count -ne 1) {
    throw "Expected exactly one active physical adapter; found $($adapters.Count). Configure DNS manually if this is intentional."
}

if ($PSCmdlet.ShouldProcess($adapters[0].Name, "Set DNS to $($config.Network.DnsServer)")) {
    Set-DnsClientServerAddress -InterfaceIndex $adapters[0].ifIndex -ServerAddresses $config.Network.DnsServer
}

$targetOu = if ($Role -eq 'Server') {
    "OU=Servers,OU=ReedLab,$($config.Domain.DistinguishedName)"
} else {
    "OU=Workstations,OU=ReedLab,$($config.Domain.DistinguishedName)"
}

if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Join $($config.Domain.Fqdn) in $targetOu")) {
    Add-Computer -DomainName $config.Domain.Fqdn -OUPath $targetOu -Credential $Credential -Force
}

if ($Restart -and $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Restart to complete the domain join')) {
    Restart-Computer -Force
} else {
    Write-Warning 'Restart this VM to complete the domain join.'
}
