# Build guide

This guide assumes a clean, disposable set of VMs. Take a checkpoint before forest creation, another after the first successful domain sign-in, and a third before extending the LAPS schema.

## 1. Prepare installation media

Use currently serviced Windows Server 2022/2025 evaluation media and Windows 11 Pro or Enterprise media. Verify the download source and hash when Microsoft publishes one. Do not commit ISO, VHDX, answer, licence-key, or credential files to this repository.

## 2. Create the virtual network and VMs

### Hyper-V option

Open an elevated Windows PowerShell session on the host and preview the changes:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope Process -Force
.\scripts\New-HyperVLab.ps1 `
    -ServerIso C:\ISO\WindowsServer.iso `
    -ClientIso C:\ISO\Windows11.iso `
    -CreateNat `
    -WhatIf
```

If the preview names only `ReedLab-Internal`, `ReedLab-NAT`, `10.50.0.0/24`, and the four documented VMs, apply it without `-WhatIf`.

The script creates dynamic disks and attaches installation media; it does not install or licence Windows. Complete each OS installation interactively.

### Other hypervisors

Create one host-only/internal network with:

- subnet: `10.50.0.0/24`;
- gateway/NAT address: `10.50.0.1` if outbound updates are required;
- no hypervisor DHCP service; and
- no bridged adapter.

Create two Server VMs with 4 GB RAM/80 GB disk and two client VMs with 6 GB RAM/64 GB disk. Two vCPUs per VM are enough for normal lab use.

## 3. Install, patch, rename, and address Windows

Install the Desktop Experience edition on both servers. Install Windows 11 Pro/Enterprise on the clients. Apply current updates before promotion.

Rename the computers and restart:

```powershell
Rename-Computer -NewName LAB-DC01 -Restart
```

Use `LAB-SRV01`, `LAB-CL01`, or `LAB-CL02` on the other VMs.

On the DC, replace `Ethernet` if your interface has a different name:

```powershell
New-NetIPAddress -InterfaceAlias Ethernet -IPAddress 10.50.0.10 -PrefixLength 24 -DefaultGateway 10.50.0.1
Set-DnsClientServerAddress -InterfaceAlias Ethernet -ServerAddresses 10.50.0.10
```

On the member server:

```powershell
New-NetIPAddress -InterfaceAlias Ethernet -IPAddress 10.50.0.20 -PrefixLength 24 -DefaultGateway 10.50.0.1
Set-DnsClientServerAddress -InterfaceAlias Ethernet -ServerAddresses 10.50.0.10
```

Leave the clients on DHCP after the DHCP role is configured. If building without DHCP, use `10.50.0.101` and `.102`, gateway `.1`, and DNS `.10`.

Copy this repository into each VM. Do not use a shared clipboard to transfer credentials.

## 4. Create the forest

On `LAB-DC01`, open PowerShell as Administrator:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope Process -Force
Set-Location C:\Lab\ReedLab-AD-Homelab
.\scripts\00-Test-Prerequisites.ps1 -Role DomainController -Strict
.\scripts\10-Install-Forest.ps1 -WhatIf
.\scripts\10-Install-Forest.ps1 -Restart
```

The final command securely prompts for the Directory Services Restore Mode password. Store it in your password manager; it is not written to disk by the project.

After the restart, sign in as `REEDLAB\Administrator` and confirm that Server Manager reports AD DS and DNS as healthy.

## 5. Build directory objects and DHCP

Preview the directory changes:

```powershell
.\scripts\20-Build-Directory.ps1 -CreateSampleUsers -WhatIf
```

Apply them:

```powershell
.\scripts\20-Build-Directory.ps1 -CreateSampleUsers
.\scripts\15-Configure-Dhcp.ps1
```

The first command securely prompts for one temporary sample-user password and marks each account to change it at first sign-in. The users are fictional. Re-running the script does not duplicate OUs, groups, or users.

In Active Directory Users and Computers, enable **View → Advanced Features** and inspect the `ReedLab` OU. In DHCP Manager, confirm that the `ReedLab Clients` scope is active.

## 6. Join the member server and clients

On each non-DC VM, confirm that DNS points to `10.50.0.10`, then run the correct role:

```powershell
.\scripts\00-Test-Prerequisites.ps1 -Role FileServer
.\scripts\30-Join-Domain.ps1 -Role Server -WhatIf
.\scripts\30-Join-Domain.ps1 -Role Server -Restart
```

Use `-Role Workstation` on both clients. The credential prompt accepts a domain account allowed to join computers; the credential is not serialized. After restart, verify that the computer objects landed in the Servers or Workstations OU.

## 7. Configure file services

On `LAB-SRV01` as a domain administrator:

```powershell
.\scripts\40-Configure-FileServer.ps1 -WhatIf
.\scripts\40-Configure-FileServer.ps1
Get-SmbShare | Where-Object Name -in Engineering,Operations,Finance,People,Common
```

Test with two fictional users from different departments. A member of `GG_Engineering_Users` should modify `\\LAB-SRV01\Engineering` and read `\\LAB-SRV01\Common`, but should not browse Finance.

## 8. Apply security policy and Windows LAPS

On `LAB-DC01`, take a checkpoint and preview:

```powershell
.\scripts\50-Configure-SecurityBaseline.ps1 -ExtendLapsSchema -WhatIf
```

Use an account with the required schema rights for the initial extension, then apply:

```powershell
.\scripts\50-Configure-SecurityBaseline.ps1 -ExtendLapsSchema
```

Remove day-to-day accounts from elevated groups when finished. Add a dedicated lab admin account to `GG_LAPS_Readers` only if it genuinely needs to retrieve local-admin passwords.

On a client, update and inspect policy:

```powershell
gpupdate /force
gpresult /h C:\Windows\Temp\ReedLab-GPResult.html
Get-LapsDiagnostics
```

When demonstrating LAPS, never capture or publish the password field.

## 9. Configure Windows Event Forwarding

On `LAB-DC01`:

```powershell
.\scripts\60-Configure-EventForwarding.ps1 -Mode Policy
```

On `LAB-SRV01`:

```powershell
.\scripts\60-Configure-EventForwarding.ps1 -Mode Collector
.\scripts\60-Configure-EventForwarding.ps1 -Mode Source
```

On each client:

```powershell
.\scripts\60-Configure-EventForwarding.ps1 -Mode Source
```

Allow at least one policy refresh interval. On the collector, inspect:

```powershell
wecutil gr ReedLab-Baseline-Events
Get-WinEvent -LogName ForwardedEvents -MaxEvents 20
```

## 10. Validate and collect evidence

From `LAB-DC01`:

```powershell
.\scripts\90-Validate-Lab.ps1 -ExportPath C:\Lab\ReedLab-validation.csv
```

Investigate failures rather than editing the report. Run again with `-FailOnError` when all expected components are deployed.

Acceptance criteria:

- all documented OUs and groups exist;
- sample users are members of role groups, not directly placed on share ACLs;
- both clients and the member server are in their intended OUs;
- the five shares enforce department separation;
- GPO results show the appropriate baseline, LAPS, audit, and WEF policies;
- LAPS schema and delegated permissions exist;
- `LAB-SRV01` receives forwarded events from all three sources; and
- `90-Validate-Lab.ps1 -FailOnError` completes without an exception.

Capture only sanitized evidence listed in [screenshots/README.md](screenshots/README.md).
