#requires -Version 5.1
#requires -RunAsAdministrator
#requires -Modules Hyper-V
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$ServerIso,
    [Parameter(Mandatory)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$ClientIso,
    [string]$LabRoot = 'C:\HyperV\ReedLab',
    [switch]$CreateNat
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\modules\ReedLab\ReedLab.psd1') -Force
Assert-ReedLabAdministrator
$config = Get-ReedLabConfig

$resolvedLabRoot = [IO.Path]::GetFullPath($LabRoot).TrimEnd('\')
if ($resolvedLabRoot -match '^[A-Za-z]:$') {
    throw 'LabRoot cannot be the root of a drive.'
}
$LabRoot = $resolvedLabRoot

$switchName = 'ReedLab-Internal'
$natName = 'ReedLab-NAT'

Write-ReedLabStep 'Preparing the isolated Hyper-V network'
$switch = Get-VMSwitch -Name $switchName -ErrorAction SilentlyContinue
if (-not $switch -and $PSCmdlet.ShouldProcess($switchName, 'Create an internal Hyper-V switch')) {
    $switch = New-VMSwitch -Name $switchName -SwitchType Internal
} elseif ($switch -and $switch.SwitchType -ne 'Internal') {
    throw "$switchName exists but is not an internal switch."
}

if ($CreateNat -and $switch) {
    $adapter = Get-NetAdapter -Name "vEthernet ($switchName)" -ErrorAction Stop
    $conflictingGateway = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -eq $config.Network.Gateway -and $_.InterfaceIndex -ne $adapter.ifIndex }
    if ($conflictingGateway) {
        throw "$($config.Network.Gateway) is already assigned to another host interface."
    }
    $gateway = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object IPAddress -eq $config.Network.Gateway
    if (-not $gateway -and $PSCmdlet.ShouldProcess($adapter.Name, "Assign $($config.Network.Gateway)/24")) {
        New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $config.Network.Gateway -PrefixLength 24 | Out-Null
    }

    $nat = Get-NetNat -Name $natName -ErrorAction SilentlyContinue
    $conflictingNat = Get-NetNat -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne $natName -and $_.InternalIPInterfaceAddressPrefix -eq $config.Network.Prefix }
    if ($conflictingNat) {
        throw "$($config.Network.Prefix) is already used by NAT '$($conflictingNat.Name)'."
    }
    if (-not $nat -and $PSCmdlet.ShouldProcess($natName, "Create NAT for $($config.Network.Prefix)")) {
        New-NetNat -Name $natName -InternalIPInterfaceAddressPrefix $config.Network.Prefix | Out-Null
    } elseif ($nat -and $nat.InternalIPInterfaceAddressPrefix -ne $config.Network.Prefix) {
        throw "$natName exists with a different network prefix."
    }
}

$vmDefinitions = @(
    @{ Name = $config.Computers.DomainController.Name; Memory = 4GB; Minimum = 2GB; Disk = 80GB; Iso = $ServerIso; Client = $false }
    @{ Name = $config.Computers.FileServer.Name;       Memory = 4GB; Minimum = 2GB; Disk = 80GB; Iso = $ServerIso; Client = $false }
    @{ Name = $config.Computers.Client01.Name;         Memory = 6GB; Minimum = 4GB; Disk = 64GB; Iso = $ClientIso; Client = $true }
    @{ Name = $config.Computers.Client02.Name;         Memory = 6GB; Minimum = 4GB; Disk = 64GB; Iso = $ClientIso; Client = $true }
)

foreach ($definition in $vmDefinitions) {
    $vmPath = Join-Path $LabRoot $definition.Name
    $diskPath = Join-Path $vmPath "$($definition.Name).vhdx"
    $vm = Get-VM -Name $definition.Name -ErrorAction SilentlyContinue

    if (-not $vm -and $PSCmdlet.ShouldProcess($definition.Name, 'Create Generation 2 lab VM')) {
        New-Item -ItemType Directory -Path $vmPath -Force | Out-Null
        New-VHD -Path $diskPath -SizeBytes $definition.Disk -Dynamic | Out-Null
        $vm = New-VM -Name $definition.Name -Generation 2 -MemoryStartupBytes $definition.Memory -VHDPath $diskPath -Path $vmPath -SwitchName $switchName
        Set-VM -VM $vm -ProcessorCount 2 -AutomaticCheckpointsEnabled $true -AutomaticStartAction Nothing -AutomaticStopAction ShutDown
        Set-VMMemory -VM $vm -DynamicMemoryEnabled $true -MinimumBytes $definition.Minimum -MaximumBytes 8GB
        Set-VMFirmware -VM $vm -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows
        if ($definition.Client) {
            Set-VMKeyProtector -VM $vm -NewLocalKeyProtector
            Enable-VMTPM -VM $vm
        }
        Add-VMDvdDrive -VM $vm -Path $definition.Iso | Out-Null
        $dvd = Get-VMDvdDrive -VM $vm
        Set-VMFirmware -VM $vm -FirstBootDevice $dvd
    }
}

Write-Host 'Hyper-V shell created. Install Windows interactively, then follow docs/build-guide.md.' -ForegroundColor Green
