Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-ReedLabStep {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Message)

    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Get-ReedLabConfig {
    [CmdletBinding()]
    param(
        [string]$Path = (Join-Path $PSScriptRoot '..\..\config\LabConfig.psd1')
    )

    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    $config = Import-PowerShellDataFile -LiteralPath $resolvedPath

    if ($config.Domain.Fqdn -ne 'corp.reedlab.test') {
        throw "Safety check failed: this project is locked to corp.reedlab.test."
    }
    if ($config.Network.Prefix -ne '10.50.0.0/24') {
        throw "Safety check failed: this project is locked to the isolated 10.50.0.0/24 lab network."
    }

    return $config
}

function Assert-ReedLabAdministrator {
    [CmdletBinding()]
    param()

    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'This deployment command must run on Windows.'
    }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Open PowerShell as Administrator and run the command again.'
    }
}

function Assert-ReedLabSafety {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [switch]$AllowWorkgroup
    )

    if ($Config.Domain.Fqdn -ne 'corp.reedlab.test' -or $Config.Domain.Fqdn -notlike '*.test') {
        throw 'Refusing to continue: the configured domain is not the approved fictional .test domain.'
    }

    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        return
    }

    $computer = Get-CimInstance -ClassName Win32_ComputerSystem
    if ($computer.PartOfDomain -and $computer.Domain -ne $Config.Domain.Fqdn) {
        throw "Refusing to run on '$($computer.Domain)'. Use a disposable VM in $($Config.Domain.Fqdn)."
    }
    if (-not $computer.PartOfDomain -and -not $AllowWorkgroup) {
        throw "This machine is not joined to $($Config.Domain.Fqdn)."
    }
}

function Ensure-ReedLabOrganizationalUnit {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Path,
        [string]$Description = 'Managed by ReedLab automation'
    )

    $distinguishedName = "OU=$Name,$Path"
    $existing = Get-ADOrganizationalUnit -Identity $distinguishedName -ErrorAction SilentlyContinue
    if ($existing) {
        return $existing
    }

    if ($PSCmdlet.ShouldProcess($distinguishedName, 'Create organizational unit')) {
        return New-ADOrganizationalUnit -Name $Name -Path $Path -Description $Description -ProtectedFromAccidentalDeletion $true -PassThru
    }
}

function Ensure-ReedLabGroup {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('Global', 'DomainLocal', 'Universal')][string]$Scope,
        [Parameter(Mandatory)][string]$Path,
        [string]$Description = 'Managed by ReedLab automation'
    )

    $existing = Get-ADGroup -Identity $Name -ErrorAction SilentlyContinue
    if ($existing) {
        return $existing
    }

    if ($PSCmdlet.ShouldProcess($Name, "Create $Scope security group")) {
        return New-ADGroup -Name $Name -SamAccountName $Name -GroupCategory Security -GroupScope $Scope -Path $Path -Description $Description -PassThru
    }
}

function Ensure-ReedLabGpo {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Target,
        [string]$Description = 'Managed by ReedLab automation'
    )

    $gpo = Get-GPO -Name $Name -ErrorAction SilentlyContinue
    if (-not $gpo -and $PSCmdlet.ShouldProcess($Name, 'Create Group Policy Object')) {
        $gpo = New-GPO -Name $Name -Comment $Description
    }

    if ($gpo) {
        $link = (Get-GPInheritance -Target $Target).GpoLinks | Where-Object DisplayName -eq $Name
        if (-not $link -and $PSCmdlet.ShouldProcess($Target, "Link GPO '$Name'")) {
            New-GPLink -Name $Name -Target $Target -LinkEnabled Yes | Out-Null
        }
    }

    return $gpo
}

Export-ModuleMember -Function @(
    'Assert-ReedLabAdministrator',
    'Assert-ReedLabSafety',
    'Ensure-ReedLabGpo',
    'Ensure-ReedLabGroup',
    'Ensure-ReedLabOrganizationalUnit',
    'Get-ReedLabConfig',
    'Write-ReedLabStep'
)
