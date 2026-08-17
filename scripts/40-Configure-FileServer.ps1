#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\LabConfig.psd1'),
    [string]$SharesPath = (Join-Path $PSScriptRoot '..\data\Shares.csv')
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\modules\ReedLab\ReedLab.psd1') -Force

Assert-ReedLabAdministrator
$config = Get-ReedLabConfig -Path $ConfigPath
Assert-ReedLabSafety -Config $config

if ($env:COMPUTERNAME -ne $config.Computers.FileServer.Name) {
    throw "Run this script only on $($config.Computers.FileServer.Name)."
}

$shares = Import-Csv -LiteralPath $SharesPath
if ($PSCmdlet.ShouldProcess($config.Storage.SharesRoot, 'Create the departmental share root')) {
    New-Item -ItemType Directory -Path $config.Storage.SharesRoot -Force | Out-Null
}

foreach ($share in $shares) {
    $path = Join-Path $config.Storage.SharesRoot $share.Name
    $readPrincipal = "$($config.Domain.NetBIOS)\$($share.ReadGroup)"
    $modifyPrincipal = "$($config.Domain.NetBIOS)\$($share.ModifyGroup)"

    Write-ReedLabStep "Configuring $($share.Name)"
    if ($PSCmdlet.ShouldProcess($path, 'Create folder and apply least-privilege NTFS ACL')) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        $acl = Get-Acl -LiteralPath $path
        $acl.SetAccessRuleProtection($true, $false)

        $inheritance = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        $propagation = [Security.AccessControl.PropagationFlags]::None
        $rules = @(
            [Security.AccessControl.FileSystemAccessRule]::new('NT AUTHORITY\SYSTEM', 'FullControl', $inheritance, $propagation, 'Allow')
            [Security.AccessControl.FileSystemAccessRule]::new('BUILTIN\Administrators', 'FullControl', $inheritance, $propagation, 'Allow')
            [Security.AccessControl.FileSystemAccessRule]::new($modifyPrincipal, 'Modify', $inheritance, $propagation, 'Allow')
            [Security.AccessControl.FileSystemAccessRule]::new($readPrincipal, 'ReadAndExecute', $inheritance, $propagation, 'Allow')
        )
        foreach ($rule in $rules) {
            $acl.SetAccessRule($rule)
        }
        Set-Acl -LiteralPath $path -AclObject $acl
    }

    $existingShare = Get-SmbShare -Name $share.Name -ErrorAction SilentlyContinue
    if (-not $existingShare -and $PSCmdlet.ShouldProcess($share.Name, 'Create encrypted SMB share')) {
        $newShare = @{
            Name                  = $share.Name
            Path                  = $path
            Description           = $share.Description
            FullAccess            = 'BUILTIN\Administrators'
            ChangeAccess          = $modifyPrincipal
            ReadAccess            = $readPrincipal
            FolderEnumerationMode = 'AccessBased'
            EncryptData           = $true
        }
        New-SmbShare @newShare | Out-Null
    } elseif ($existingShare -and $existingShare.Path -ne $path) {
        throw "Share '$($share.Name)' already points to '$($existingShare.Path)', not '$path'."
    }

    if ($existingShare -and $PSCmdlet.ShouldProcess($share.Name, 'Refresh SMB share access and security settings')) {
        Set-SmbShare -Name $share.Name -FolderEnumerationMode AccessBased -EncryptData $true -Force | Out-Null
        Grant-SmbShareAccess -Name $share.Name -AccountName $modifyPrincipal -AccessRight Change -Force | Out-Null
        Grant-SmbShareAccess -Name $share.Name -AccountName $readPrincipal -AccessRight Read -Force | Out-Null
        Revoke-SmbShareAccess -Name $share.Name -AccountName 'Everyone' -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

Write-Host "Configured $($shares.Count) least-privilege SMB shares under $($config.Storage.SharesRoot)." -ForegroundColor Green
