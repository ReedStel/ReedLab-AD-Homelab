#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\LabConfig.psd1')
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\modules\ReedLab\ReedLab.psd1') -Force

Assert-ReedLabAdministrator
$config = Get-ReedLabConfig -Path $ConfigPath
Assert-ReedLabSafety -Config $config
if ($env:COMPUTERNAME -ne $config.Computers.DomainController.Name) {
    throw "Run this script only on $($config.Computers.DomainController.Name)."
}

Write-ReedLabStep 'Installing and authorizing DHCP Server'
if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Install DHCP Server and management tools')) {
    $feature = Install-WindowsFeature DHCP -IncludeManagementTools
    if (-not $feature.Success) { throw 'DHCP feature installation failed.' }
}
if (-not (Get-Module -ListAvailable -Name DhcpServer)) {
    if ($WhatIfPreference) {
        Write-Warning 'DhcpServer is not installed yet; the preview stops after the feature-install action.'
        return
    }
    throw 'The DhcpServer module is unavailable after feature installation.'
}
Import-Module DhcpServer

if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Create DHCP security groups and restart the service')) {
    & netsh.exe dhcp add securitygroups | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "DHCP security-group setup failed with exit code $LASTEXITCODE." }
    Restart-Service DHCPServer -Force
}

$dcFqdn = "$($config.Computers.DomainController.Name).$($config.Domain.Fqdn)"
$authorized = Get-DhcpServerInDC | Where-Object DnsName -eq $dcFqdn
if (-not $authorized -and $PSCmdlet.ShouldProcess($dcFqdn, 'Authorize DHCP server in Active Directory')) {
    Add-DhcpServerInDC -DnsName $dcFqdn -IPAddress $config.Computers.DomainController.Address
}

$scope = Get-DhcpServerv4Scope -ScopeId $config.Network.DhcpScopeId -ErrorAction SilentlyContinue
if (-not $scope -and $PSCmdlet.ShouldProcess($config.Network.Prefix, 'Create ReedLab DHCP scope')) {
    $newScope = @{
        Name       = 'ReedLab Clients'
        StartRange = $config.Network.DhcpStart
        EndRange   = $config.Network.DhcpEnd
        SubnetMask = $config.Network.SubnetMask
        State      = 'Active'
    }
    Add-DhcpServerv4Scope @newScope | Out-Null
} elseif ($scope -and ($scope.StartRange -ne $config.Network.DhcpStart -or $scope.EndRange -ne $config.Network.DhcpEnd)) {
    throw 'The existing DHCP scope uses a different address range. Refusing to overwrite it.'
}

if ($PSCmdlet.ShouldProcess($config.Network.DhcpScopeId, 'Set gateway, DNS server, and DNS suffix options')) {
    $scopeOptions = @{
        ScopeId   = $config.Network.DhcpScopeId
        Router    = $config.Network.Gateway
        DnsServer = $config.Network.DnsServer
        DnsDomain = $config.Domain.Fqdn
    }
    Set-DhcpServerv4OptionValue @scopeOptions
}

$reverseZoneName = '0.50.10.in-addr.arpa'
$reverseZone = Get-DnsServerZone -Name $reverseZoneName -ErrorAction SilentlyContinue
if (-not $reverseZone -and $PSCmdlet.ShouldProcess($reverseZoneName, 'Create an AD-integrated reverse lookup zone')) {
    Add-DnsServerPrimaryZone -NetworkId $config.Network.Prefix -ReplicationScope Domain -DynamicUpdate Secure | Out-Null
}

Write-Host 'DHCP scope and reverse DNS zone configured for the isolated ReedLab subnet.' -ForegroundColor Green
