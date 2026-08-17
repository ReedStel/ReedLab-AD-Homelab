#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { $failures.Add($Message) }
}

$requiredFiles = @(
    'README.md', 'LICENSE', 'SECURITY.md', 'NOTICE',
    'config\LabConfig.psd1', 'data\Users.csv', 'data\Shares.csv',
    'modules\ReedLab\ReedLab.psm1', 'scripts\10-Install-Forest.ps1',
    'scripts\20-Build-Directory.ps1', 'scripts\50-Configure-SecurityBaseline.ps1',
    'scripts\90-Validate-Lab.ps1'
)
foreach ($relativePath in $requiredFiles) {
    Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot $relativePath)) "Missing required file: $relativePath"
}

$powerShellFiles = @(Get-ChildItem -Path $projectRoot -Recurse -File | Where-Object { $_.Extension -in '.ps1', '.psm1', '.psd1' })
foreach ($file in $powerShellFiles) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    foreach ($parseError in $parseErrors) {
        $failures.Add("Parse error in $($file.FullName):$($parseError.Extent.StartLineNumber): $($parseError.Message)")
    }
}

$config = Import-PowerShellDataFile -LiteralPath (Join-Path $projectRoot 'config\LabConfig.psd1')
Assert-True ($config.Domain.Fqdn -eq 'corp.reedlab.test') 'The domain must remain the fictional corp.reedlab.test namespace.'
Assert-True ($config.Domain.NetBIOS -eq 'REEDLAB') 'Unexpected NetBIOS name.'
Assert-True ($config.Network.Prefix -eq '10.50.0.0/24') 'Unexpected lab network.'
Assert-True ($config.Security.MinimumPasswordLength -ge 14) 'Minimum password length must be at least 14.'
Assert-True ($config.Security.LapsPasswordLength -ge 20) 'LAPS password length must be at least 20.'

$users = @(Import-Csv -LiteralPath (Join-Path $projectRoot 'data\Users.csv'))
$shares = @(Import-Csv -LiteralPath (Join-Path $projectRoot 'data\Shares.csv'))
Assert-True ($users.Count -ge 8) 'Expected at least eight fictional sample users.'
Assert-True ($shares.Count -ge 5) 'Expected at least five share definitions.'
Assert-True (@($users.SamAccountName | Sort-Object -Unique).Count -eq $users.Count) 'Duplicate sample SamAccountName value.'
Assert-True (@($shares.Name | Sort-Object -Unique).Count -eq $shares.Count) 'Duplicate share name.'

$sourceFiles = @(Get-ChildItem -Path $projectRoot -Recurse -File | Where-Object { $_.Extension -in '.ps1', '.psm1', '.psd1', '.csv', '.md' })
$sourceText = ($sourceFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
$secretPatterns = @(
    '(?im)(api[_-]?key|client[_-]?secret|access[_-]?token)\s*=\s*["''][^"'']+["'']',
    '(?im)password\s*=\s*["''][^"'']+["'']',
    '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
)
foreach ($pattern in $secretPatterns) {
    Assert-True (-not [regex]::IsMatch($sourceText, $pattern)) "Potential committed secret matched: $pattern"
}

$mutatingScripts = Get-ChildItem (Join-Path $projectRoot 'scripts') -Filter '*.ps1' | Where-Object { $_.Name -notin '00-Test-Prerequisites.ps1', '90-Validate-Lab.ps1' }
foreach ($script in $mutatingScripts) {
    $text = Get-Content -LiteralPath $script.FullName -Raw
    Assert-True ($text -match 'SupportsShouldProcess') "$($script.Name) must support -WhatIf."
    $hasSafetyGuard = $text -match 'Assert-ReedLabSafety'
    if ($script.Name -eq 'New-HyperVLab.ps1') {
        $hasSafetyGuard = $text -match "switchName = 'ReedLab-Internal'" -and $text -match 'Get-ReedLabConfig'
    }
    Assert-True $hasSafetyGuard "$($script.Name) must include a lab-safety guard."
}

if ($failures.Count) {
    $failures | ForEach-Object { Write-Error $_ }
    throw "Static validation failed with $($failures.Count) issue(s)."
}

Write-Host "Static validation passed: $($powerShellFiles.Count) PowerShell files parsed, fixtures checked, and no obvious secrets found." -ForegroundColor Green
