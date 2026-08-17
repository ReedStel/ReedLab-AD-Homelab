@{
    RootModule        = 'ReedLab.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'f08cab31-63d9-4d8f-a5a5-8ac9c3d1f275'
    Author            = 'Reed Stelfox'
    CompanyName       = 'Community'
    Copyright         = '(c) 2026 Reed Stelfox. All rights reserved.'
    Description       = 'Safe, idempotent helpers for the fictional ReedLab Active Directory homelab.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Assert-ReedLabAdministrator'
        'Assert-ReedLabSafety'
        'Ensure-ReedLabGpo'
        'Ensure-ReedLabGroup'
        'Ensure-ReedLabOrganizationalUnit'
        'Get-ReedLabConfig'
        'Write-ReedLabStep'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('ActiveDirectory', 'Homelab', 'WindowsServer', 'PowerShell')
            ProjectUri = 'https://github.com/ReedStel/ReedLab-AD-Homelab'
        }
    }
}
