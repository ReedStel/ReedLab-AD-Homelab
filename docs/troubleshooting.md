# Troubleshooting

Troubleshoot one layer at a time: virtual network, IP, DNS, time, domain trust, Group Policy, then the workload. Take notes and avoid random policy changes that hide the original fault.

## Domain join says the domain cannot be contacted

On the member VM:

```powershell
ipconfig /all
Resolve-DnsName corp.reedlab.test -Server 10.50.0.10
Resolve-DnsName _ldap._tcp.dc._msdcs.corp.reedlab.test -Type SRV -Server 10.50.0.10
Test-NetConnection 10.50.0.10 -Port 53
w32tm /query /status
```

The VM must use only `10.50.0.10` for DNS. Do not add a public resolver as a second client DNS address; configure forwarders on the DC instead. Confirm that the hypervisor's own DHCP service is disabled on the lab switch.

## A GPO does not apply

```powershell
gpupdate /force
gpresult /r /scope computer
gpresult /h C:\Windows\Temp\gpresult.html
Get-WinEvent -LogName Microsoft-Windows-GroupPolicy/Operational -MaxEvents 30
```

Check that the computer object is in the Servers or Workstations OU, not the default `Computers` container. In GPMC, confirm the link is enabled and inheritance is not blocked.

## Windows LAPS attributes are missing

On the DC:

```powershell
Get-Command Update-LapsADSchema
Get-ADObject -SearchBase (Get-ADRootDSE).schemaNamingContext `
    -LDAPFilter '(lDAPDisplayName=msLAPS-PasswordExpirationTime)'
Find-LapsADExtendedRights -Identity 'OU=Workstations,OU=ReedLab,DC=corp,DC=reedlab,DC=test'
```

If the schema attribute is absent, take a checkpoint and rerun `50-Configure-SecurityBaseline.ps1 -ExtendLapsSchema` with the required rights. On the client, update policy and run:

```powershell
Invoke-LapsPolicyProcessing -Verbose
Get-LapsDiagnostics
Get-WinEvent -LogName Microsoft-Windows-LAPS/Operational -MaxEvents 30
```

Do not paste diagnostic output publicly until it has been reviewed for sensitive values.

## Share access is wrong

Check both share-level and NTFS permissions:

```powershell
Get-SmbShareAccess -Name Engineering
(Get-Acl C:\Shares\Engineering).Access |
    Select-Object IdentityReference, FileSystemRights, AccessControlType, IsInherited
whoami /groups
```

After changing group membership, sign out and back in to obtain a new Kerberos token. Do not grant a user directly on the folder to “fix” the test; correct the relevant global-to-domain-local nesting.

## No forwarded events arrive

On the collector:

```powershell
wecutil es
wecutil gr ReedLab-Baseline-Events
Get-Service Wecsvc, WinRM
Get-WinEvent -LogName Microsoft-Windows-EventCollector/Operational -MaxEvents 50
```

On the source:

```powershell
gpresult /r /scope computer
Get-ItemProperty 'HKLM:\Software\Policies\Microsoft\Windows\EventLog\EventForwarding\SubscriptionManager'
Get-Service WinRM
winrm id -r:LAB-SRV01.corp.reedlab.test
Get-WinEvent -LogName Microsoft-Windows-Forwarding/Operational -MaxEvents 50
```

Confirm the source is a member of Domain Computers and that `NETWORK SERVICE` belongs to local `Event Log Readers`. Policy and subscriptions can take more than one refresh interval to converge.

## Forest installation failed

Read the AD DS deployment logs in `%systemroot%\debug` and the event logs before retrying. Common causes are an incorrect computer name, dynamic IP configuration, missing restart, or unsupported OS edition.

If promotion failed midway, do not repeatedly rerun it on an uncertain directory state. In this disposable lab, return all affected VMs to the coordinated pre-forest checkpoint or rebuild them. Never use these recovery shortcuts on production AD.

## Static validation fails in GitHub Actions

The workflow parses every PowerShell file, validates required fixtures, checks safety constants, and looks for obvious secrets. Reproduce on Windows PowerShell:

```powershell
.\tests\StaticValidation.ps1
```

Fix the reported file and line. Do not weaken the safety or secret checks to make the build green.
