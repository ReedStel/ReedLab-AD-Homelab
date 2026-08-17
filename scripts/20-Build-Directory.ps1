#requires -Version 5.1
#requires -Modules ActiveDirectory
#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\LabConfig.psd1'),
    [string]$UsersPath = (Join-Path $PSScriptRoot '..\data\Users.csv'),
    [string]$SharesPath = (Join-Path $PSScriptRoot '..\data\Shares.csv'),
    [switch]$CreateSampleUsers,
    [Security.SecureString]$InitialUserPassword
)

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
Import-Module (Join-Path $PSScriptRoot '..\modules\ReedLab\ReedLab.psd1') -Force

Assert-ReedLabAdministrator
$config = Get-ReedLabConfig -Path $ConfigPath
Assert-ReedLabSafety -Config $config

if ((Get-ADDomain).DNSRoot -ne $config.Domain.Fqdn) {
    throw 'Connected domain does not match the fictional ReedLab domain.'
}

Write-ReedLabStep 'Creating the organizational-unit structure'
foreach ($ou in $config.OrganizationalUnits) {
    Ensure-ReedLabOrganizationalUnit -Name $ou.Name -Path $ou.Parent -WhatIf:$WhatIfPreference | Out-Null
}

$groupsOu = "OU=Groups,OU=ReedLab,$($config.Domain.DistinguishedName)"
$roleGroups = @(
    @{ Name = 'GG_Engineering_Users'; Scope = 'Global'; Description = 'Engineering user role' }
    @{ Name = 'GG_Operations_Users';  Scope = 'Global'; Description = 'Operations user role' }
    @{ Name = 'GG_Finance_Users';     Scope = 'Global'; Description = 'Finance user role' }
    @{ Name = 'GG_People_Users';      Scope = 'Global'; Description = 'People user role' }
    @{ Name = 'GG_All_Users';         Scope = 'Global'; Description = 'All standard ReedLab users' }
    @{ Name = 'GG_Server_Admins';     Scope = 'Global'; Description = 'Delegated member-server administrators' }
    @{ Name = 'GG_Tier0_Admins';      Scope = 'Global'; Description = 'Restricted directory administrators' }
    @{ Name = 'GG_LAPS_Readers';      Scope = 'Global'; Description = 'Authorized Windows LAPS password readers' }
)

Write-ReedLabStep 'Creating role and resource groups'
foreach ($group in $roleGroups) {
    Ensure-ReedLabGroup -Name $group.Name -Scope $group.Scope -Path $groupsOu -Description $group.Description -WhatIf:$WhatIfPreference | Out-Null
}

$shares = Import-Csv -LiteralPath $SharesPath
foreach ($share in $shares) {
    Ensure-ReedLabGroup -Name $share.ReadGroup -Scope DomainLocal -Path $groupsOu -Description "$($share.Name) read access" -WhatIf:$WhatIfPreference | Out-Null
    Ensure-ReedLabGroup -Name $share.ModifyGroup -Scope DomainLocal -Path $groupsOu -Description "$($share.Name) modify access" -WhatIf:$WhatIfPreference | Out-Null
}

function Add-GroupMembershipIfMissing {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Group, [string]$Member)

    $targetGroup = Get-ADGroup -Identity $Group -ErrorAction SilentlyContinue
    $memberGroup = Get-ADGroup -Identity $Member -ErrorAction SilentlyContinue
    if (-not $targetGroup -or -not $memberGroup) {
        if ($WhatIfPreference) { return }
        throw "Cannot nest '$Member' in '$Group' because one of the groups does not exist."
    }
    $memberDn = $memberGroup.DistinguishedName
    $present = Get-ADGroupMember -Identity $Group | Where-Object DistinguishedName -eq $memberDn
    if (-not $present -and $PSCmdlet.ShouldProcess("$Member -> $Group", 'Add nested group membership')) {
        Add-ADGroupMember -Identity $Group -Members $Member
    }
}

foreach ($department in 'Engineering', 'Operations', 'Finance', 'People') {
    Add-GroupMembershipIfMissing -Group "DL_${department}_Modify" -Member "GG_${department}_Users" -WhatIf:$WhatIfPreference
}
Add-GroupMembershipIfMissing -Group 'DL_Common_Read' -Member 'GG_All_Users' -WhatIf:$WhatIfPreference

if ($CreateSampleUsers) {
    if (-not $InitialUserPassword -and -not $WhatIfPreference) {
        $InitialUserPassword = Read-Host 'Temporary password for fictional sample users (not displayed)' -AsSecureString
    }

    Write-ReedLabStep 'Creating fictional sample users'
    $users = Import-Csv -LiteralPath $UsersPath
    foreach ($user in $users) {
        $userOu = "OU=$($user.TargetOU),OU=Users,OU=ReedLab,$($config.Domain.DistinguishedName)"
        $existing = Get-ADUser -Identity $user.SamAccountName -ErrorAction SilentlyContinue
        if (-not $existing -and $PSCmdlet.ShouldProcess($user.SamAccountName, 'Create fictional lab user')) {
            $newUser = @{
                Name                  = "$($user.GivenName) $($user.Surname)"
                GivenName             = $user.GivenName
                Surname               = $user.Surname
                DisplayName           = "$($user.GivenName) $($user.Surname)"
                SamAccountName        = $user.SamAccountName
                UserPrincipalName     = "$($user.SamAccountName)@$($config.Domain.Fqdn)"
                Department            = $user.Department
                Title                 = $user.Title
                Path                  = $userOu
                AccountPassword       = $InitialUserPassword
                Enabled               = [bool]::Parse($user.Enabled)
                ChangePasswordAtLogon = $true
            }
            New-ADUser @newUser
        }

        foreach ($roleGroup in ($user.RoleGroups -split ';')) {
            if ($roleGroup) {
                $current = Get-ADPrincipalGroupMembership -Identity $user.SamAccountName -ErrorAction SilentlyContinue | Where-Object Name -eq $roleGroup
                if (-not $current -and $PSCmdlet.ShouldProcess("$($user.SamAccountName) -> $roleGroup", 'Add user group membership')) {
                    Add-ADGroupMember -Identity $roleGroup -Members $user.SamAccountName
                }
            }
        }
        $allUsersMembership = Get-ADPrincipalGroupMembership -Identity $user.SamAccountName -ErrorAction SilentlyContinue | Where-Object Name -eq 'GG_All_Users'
        if (-not $allUsersMembership -and $PSCmdlet.ShouldProcess("$($user.SamAccountName) -> GG_All_Users", 'Add user group membership')) {
            Add-ADGroupMember -Identity GG_All_Users -Members $user.SamAccountName
        }
    }
}

Write-ReedLabStep 'Applying the lab domain password and lockout policy'
if ($PSCmdlet.ShouldProcess($config.Domain.Fqdn, 'Set the default domain password policy')) {
    $passwordPolicy = @{
        Identity                    = $config.Domain.Fqdn
        ComplexityEnabled           = $true
        MinPasswordLength            = $config.Security.MinimumPasswordLength
        PasswordHistoryCount         = $config.Security.PasswordHistoryCount
        MaxPasswordAge               = (New-TimeSpan -Days $config.Security.MaximumPasswordAgeDays)
        LockoutThreshold             = $config.Security.LockoutThreshold
        LockoutDuration              = (New-TimeSpan -Minutes $config.Security.LockoutMinutes)
        LockoutObservationWindow     = (New-TimeSpan -Minutes $config.Security.LockoutMinutes)
        ReversibleEncryptionEnabled = $false
    }
    Set-ADDefaultDomainPasswordPolicy @passwordPolicy
}

Write-Host 'Directory build completed. Re-running this script is safe.' -ForegroundColor Green
