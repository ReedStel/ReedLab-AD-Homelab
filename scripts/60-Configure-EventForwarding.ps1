#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Collector', 'Policy', 'Source')]
    [string]$Mode,

    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\LabConfig.psd1')
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\modules\ReedLab\ReedLab.psd1') -Force

Assert-ReedLabAdministrator
$config = Get-ReedLabConfig -Path $ConfigPath
Assert-ReedLabSafety -Config $config

$subscriptionName = 'ReedLab-Baseline-Events'

if ($Mode -eq 'Collector') {
    if ($env:COMPUTERNAME -ne $config.EventForwarding.CollectorName) {
        throw "Collector mode must run on $($config.EventForwarding.CollectorName)."
    }

    if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Initialize Windows Event Collector')) {
        & wecutil.exe qc /q
        if ($LASTEXITCODE -ne 0) { throw "wecutil qc failed with exit code $LASTEXITCODE." }
    }

    $domainComputersSid = (New-Object Security.Principal.NTAccount("$($config.Domain.NetBIOS)\Domain Computers")).Translate([Security.Principal.SecurityIdentifier]).Value
    $allowedSources = "O:NSG:NSD:(A;;GA;;;$domainComputersSid)"
    $subscriptionPath = Join-Path $env:TEMP 'ReedLab-WEF-Subscription.xml'
    $xml = @"
<Subscription xmlns="http://schemas.microsoft.com/2006/03/windows/events/subscription">
  <SubscriptionId>$subscriptionName</SubscriptionId>
  <SubscriptionType>SourceInitiated</SubscriptionType>
  <Description>Fictional ReedLab security and operations events</Description>
  <Enabled>true</Enabled>
  <Uri>http://schemas.microsoft.com/wbem/wsman/1/windows/EventLog</Uri>
  <ConfigurationMode>Normal</ConfigurationMode>
  <Delivery Mode="Push">
    <Batching><MaxItems>5</MaxItems><MaxLatencyTime>15000</MaxLatencyTime></Batching>
    <PushSettings><Heartbeat Interval="60000" /></PushSettings>
  </Delivery>
  <Query>
    <![CDATA[
      <QueryList>
        <Query Id="0">
          <Select Path="System">*[System[(Level=1 or Level=2 or Level=3)]]</Select>
          <Select Path="Application">*[System[(Level=1 or Level=2)]]</Select>
          <Select Path="Security">*[System[(EventID=4624 or EventID=4625 or EventID=4688 or EventID=4720 or EventID=4728 or EventID=4732)]]</Select>
          <Select Path="Microsoft-Windows-PowerShell/Operational">*[System[(EventID=4103 or EventID=4104)]]</Select>
          <Select Path="Microsoft-Windows-Windows Defender/Operational">*[System[(EventID=1116 or EventID=1117)]]</Select>
        </Query>
      </QueryList>
    ]]>
  </Query>
  <ReadExistingEvents>false</ReadExistingEvents>
  <TransportName>HTTP</TransportName>
  <ContentFormat>RenderedText</ContentFormat>
  <Locale Language="en-US" />
  <LogFile>ForwardedEvents</LogFile>
  <AllowedSourceDomainComputers>$allowedSources</AllowedSourceDomainComputers>
</Subscription>
"@
    if ($PSCmdlet.ShouldProcess($subscriptionName, 'Create or replace the source-initiated event subscription')) {
        Set-Content -LiteralPath $subscriptionPath -Value $xml -Encoding UTF8
        & wecutil.exe ds $subscriptionName 2>$null
        & wecutil.exe cs $subscriptionPath
        if ($LASTEXITCODE -ne 0) { throw "wecutil cs failed with exit code $LASTEXITCODE." }
        Remove-Item -LiteralPath $subscriptionPath -Force
    }
}

if ($Mode -eq 'Policy') {
    if ($env:COMPUTERNAME -ne $config.Computers.DomainController.Name) {
        throw "Policy mode must run on $($config.Computers.DomainController.Name)."
    }
    Import-Module GroupPolicy
    $gpoName = 'ReedLab - Event Forwarding'
    $reedLabOu = "OU=ReedLab,$($config.Domain.DistinguishedName)"
    Ensure-ReedLabGpo -Name $gpoName -Target $reedLabOu -Description 'Source-initiated Windows Event Forwarding' -WhatIf:$WhatIfPreference | Out-Null
    $manager = "Server=http://$($config.EventForwarding.CollectorFqdn):5985/wsman/SubscriptionManager/WEC,Refresh=$($config.EventForwarding.RefreshSeconds)"
    if ($PSCmdlet.ShouldProcess($gpoName, 'Configure the WEF SubscriptionManager policy')) {
        $subscriptionPolicy = @{
            Name      = $gpoName
            Key       = 'HKLM\Software\Policies\Microsoft\Windows\EventLog\EventForwarding\SubscriptionManager'
            ValueName = '1'
            Type      = 'String'
            Value     = $manager
        }
        Set-GPRegistryValue @subscriptionPolicy | Out-Null
    }
}

if ($Mode -eq 'Source') {
    if ($env:COMPUTERNAME -notin @($config.Computers.Client01.Name, $config.Computers.Client02.Name, $config.Computers.FileServer.Name)) {
        throw 'Source mode is restricted to a configured ReedLab workstation or member server.'
    }
    if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Allow Network Service to read event logs and start WinRM')) {
        $member = Get-LocalGroupMember -Group 'Event Log Readers' -ErrorAction SilentlyContinue | Where-Object { $_.SID.Value -eq 'S-1-5-20' }
        if (-not $member) {
            Add-LocalGroupMember -Group 'Event Log Readers' -Member 'NT AUTHORITY\NETWORK SERVICE'
        }
        $auditRules = @(
            @('/set', '/subcategory:Logon', '/success:enable', '/failure:enable')
            @('/set', '/subcategory:Process Creation', '/success:enable', '/failure:disable')
            @('/set', '/subcategory:User Account Management', '/success:enable', '/failure:enable')
            @('/set', '/subcategory:Security Group Management', '/success:enable', '/failure:enable')
        )
        foreach ($auditArguments in $auditRules) {
            & auditpol.exe @auditArguments | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "auditpol failed with exit code $LASTEXITCODE." }
        }
        & wevtutil.exe sl 'Microsoft-Windows-PowerShell/Operational' /e:true
        if ($LASTEXITCODE -ne 0) { throw "Could not enable the PowerShell Operational log (exit code $LASTEXITCODE)." }
        Set-Service WinRM -StartupType Automatic
        Start-Service WinRM
        & gpupdate.exe /target:computer /force | Out-Null
    }
}

Write-Host "Event forwarding '$Mode' configuration completed." -ForegroundColor Green
