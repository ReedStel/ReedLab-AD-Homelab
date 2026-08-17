# Six-minute portfolio demo

The goal is to show decisions and evidence, not click through every wizard. Practise once, keep the LAPS password hidden, and use only fictional sample identities.

## Before recording

- Run `90-Validate-Lab.ps1` and resolve expected failures.
- Close password managers, personal browser tabs, notifications, and unrelated consoles.
- Confirm no terminal history or screenshot reveals a password, public IP, licence key, or host username.
- Open AD Users and Computers, Group Policy Management, `\\LAB-SRV01`, and Event Viewer in advance.
- Use a VM checkpoint so the demo is repeatable.

## 0:00–0:45 — Frame the project

“ReedLab is a four-VM Windows domain I built to practise repeatable identity and endpoint administration. The whole environment is generated from PowerShell and fictional CSV data, and the scripts refuse to run against an unrelated domain.”

Show the diagram in the README and point out the separate DC, member server, clients, and event flow.

## 0:45–1:40 — Directory structure

Show the `ReedLab` OU tree. Explain why servers, workstations, admins, service accounts, and quarantine are separate policy boundaries.

Then show one fictional user and its department role group. Keep the explanation concrete:

“Alex is a member of the global Engineering role. That role is nested into a domain-local Engineering resource group. The ACL grants the resource group—not the person—Modify access.”

## 1:40–2:35 — Prove least privilege

Sign in to `LAB-CL01` as a fictional Engineering user. Demonstrate:

- write access to `\\LAB-SRV01\Engineering`;
- read access to `\\LAB-SRV01\Common`; and
- denied access to `\\LAB-SRV01\Finance`.

Show access-based enumeration and the folder ACL briefly. Do not change permissions during the demo.

## 2:35–3:35 — Show policy and LAPS

In Group Policy Management, show the separate baseline, audit, LAPS, and event-forwarding GPOs and their OU links.

Show LAPS metadata without the password:

```powershell
Get-LapsADPassword -Identity LAB-CL01 |
    Select-Object ComputerName, Account, PasswordUpdateTime, ExpirationTimestamp, DecryptionStatus
```

Explain that computers can write their own LAPS attributes, while only `GG_LAPS_Readers` can retrieve the secret and successful retrieval is audited.

## 3:35–4:45 — Follow one event

Generate one failed sign-in on a client using a fictional account, then wait for the forwarding interval. On `LAB-SRV01`:

```powershell
Get-WinEvent -FilterHashtable @{ LogName = 'ForwardedEvents'; Id = 4625 } -MaxEvents 3 |
    Select-Object TimeCreated, MachineName, Id, ProviderName
```

Explain that the same collector also receives selected PowerShell, Defender, System, and group-change events. Do not claim it is a SIEM.

## 4:45–5:30 — Show repeatability

Open `config/LabConfig.psd1`, a fictional CSV file, and one numbered script. Highlight secure prompts, `-WhatIf`, idempotent existence checks, and domain safety guards.

Run the validation report:

```powershell
.\scripts\90-Validate-Lab.ps1
```

## 5:30–6:00 — Close with what you learned

“The useful part was not just promoting a DC. I had to design role-to-resource access, make reruns safe, delegate LAPS narrowly, troubleshoot policy timing, and prove that identity events reached the collector. My next step would be protected log retention and automated policy regression tests.”

## Questions to expect

**Why AGDLP for one domain?** It separates business roles from resource permissions and keeps ACLs readable as the environment grows.

**Why `.test` instead of `.local`?** It is an explicitly fictional namespace and avoids coupling the lab to a real organisation or mDNS-style naming.

**Why WinRM HTTP for WEF?** The source and collector authenticate in the domain on an isolated network. A production design may require HTTPS based on trust boundaries and policy.

**What would you change for production?** Redundant DCs, backups and restore tests, tiered administration, Microsoft security baselines, certificate services planning, monitoring/retention capacity, change control, and staged rollout.
