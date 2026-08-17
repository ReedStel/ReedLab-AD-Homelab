#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('DomainController', 'FileServer', 'Client')]
    [string]$Role,

    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\LabConfig.psd1'),

    [switch]$Strict
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\modules\ReedLab\ReedLab.psd1') -Force

Assert-ReedLabAdministrator
$config = Get-ReedLabConfig -Path $ConfigPath
Assert-ReedLabSafety -Config $config -AllowWorkgroup

$results = [System.Collections.Generic.List[object]]::new()
function Add-Check {
    param([string]$Check, [bool]$Passed, [string]$Detail)
    $results.Add([pscustomobject]@{
        Check  = $Check
        Status = $(if ($Passed) { 'PASS' } else { 'FAIL' })
        Detail = $Detail
    })
}

$computer = Get-CimInstance Win32_ComputerSystem
$os = Get-CimInstance Win32_OperatingSystem
$systemDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"

$allowedNames = switch ($Role) {
    'DomainController' { @($config.Computers.DomainController.Name) }
    'FileServer'       { @($config.Computers.FileServer.Name) }
    'Client'           { @($config.Computers.Client01.Name, $config.Computers.Client02.Name) }
}

Add-Check 'Computer name' ($env:COMPUTERNAME -in $allowedNames) "Expected: $($allowedNames -join ' or '); actual: $env:COMPUTERNAME"
Add-Check 'Memory' ($computer.TotalPhysicalMemory -ge 4GB) ("{0:N1} GB installed; 4 GB minimum" -f ($computer.TotalPhysicalMemory / 1GB))
Add-Check 'Free disk' ($systemDrive.FreeSpace -ge 35GB) ("{0:N1} GB free; 35 GB minimum" -f ($systemDrive.FreeSpace / 1GB))

$isServer = $os.ProductType -ne 1
if ($Role -eq 'Client') {
    Add-Check 'Operating system role' (-not $isServer) "$($os.Caption)"
} else {
    Add-Check 'Operating system role' $isServer "$($os.Caption)"
}

$addresses = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object PrefixOrigin -ne 'WellKnown' | Select-Object -ExpandProperty IPAddress)
$expectedAddress = switch ($Role) {
    'DomainController' { $config.Computers.DomainController.Address }
    'FileServer'       { $config.Computers.FileServer.Address }
    'Client'           { $null }
}
if ($expectedAddress) {
    Add-Check 'Static IPv4 address' ($expectedAddress -in $addresses) "Expected $expectedAddress; found $($addresses -join ', ')"
} else {
    Add-Check 'IPv4 address' ($addresses.Count -gt 0) "Found $($addresses -join ', ')"
}

$dnsServers = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object ServerAddresses | Where-Object { $_ })
if ($Role -ne 'DomainController') {
    Add-Check 'DNS points to DC' ($config.Network.DnsServer -in $dnsServers) "Expected $($config.Network.DnsServer); found $($dnsServers -join ', ')"
}

$results | Format-Table -AutoSize
$failures = @($results | Where-Object Status -eq 'FAIL')
if ($Strict -and $failures.Count -gt 0) {
    throw "$($failures.Count) prerequisite check(s) failed. Correct them before deployment."
}
