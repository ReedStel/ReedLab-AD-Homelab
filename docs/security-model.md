# Security model

## Scope and assumptions

ReedLab models defensive administration inside an isolated virtual network. The hypervisor and physical host are trusted. The sample users are unprivileged. The lab may have outbound NAT for updates, but no service should be exposed inbound from the internet or bridged home network.

## Assets

- directory database and administrative identities;
- local administrator passwords protected by Windows LAPS;
- departmental data and ACLs;
- Group Policy configuration;
- event records on the central collector; and
- the integrity of the project source and validation results.

## Main risks and controls

| Risk | Control in this lab | Remaining limitation |
|---|---|---|
| Accidental execution against a real domain | Fixed `.test` domain, fixed subnet, computer-name checks, domain-membership guard | A user can deliberately remove safety code; review source before execution |
| Excessive file access | AGDLP, domain-local ACL groups, access-based enumeration, SMB encryption | One file server is a single point of failure |
| Shared local-admin password | Windows LAPS rotation with AD backup and encrypted-password policy | Recovery still depends on correct AD permissions and backups |
| Over-privileged daily account | Dedicated admin OUs/groups and delegated LAPS reader group | The lab does not implement a full privileged-access workstation design |
| Weak or reused credentials | 14-character minimum, history, lockout, secure prompts, change at first logon | A lab baseline is not a universal password-policy recommendation |
| Invisible administrative activity | Script-block/module logging, process command-line capture, WEF | The collector is not tamper-proof and has no long-term retention tier |
| Legacy protocol exposure | SMBv1 server control and current Windows builds | This is not a full Microsoft Security Baseline import |
| Source-code secret leakage | No serialized credentials; static secret-pattern checks; ignored secret/VM file types | Pattern scans cannot identify every sensitive value |

## Identity tiers

- Standard users belong to department global groups and `GG_All_Users`.
- `GG_Server_Admins` is reserved for member-server administration.
- `GG_Tier0_Admins` is reserved for directory-control-plane work.
- `GG_LAPS_Readers` can retrieve sensitive local-admin credentials and must remain small.
- Admin and service accounts have separate OUs so policies and delegation can be tightened independently.

The project does not automatically add people to privileged groups. That decision must stay visible and manual.

## Windows LAPS choices

- Password backup target: Active Directory (`BackupDirectory = 2`)
- Password length: 20 characters
- Rotation: 30 days
- Complexity: upper, lower, number, and special characters
- AD password encryption: enabled
- Password decryption principal: `GG_LAPS_Readers`
- Expiration protection: enabled
- Computer self-write permission: delegated only on Servers and Workstations OUs
- Read permission and successful-read auditing: delegated to `GG_LAPS_Readers`

Retrieving a password is a privileged act. Demos should select metadata fields only or redact the value before capture.

## Audit selection

The event subscription favours useful identity and operations signals without forwarding every event:

- failed and successful sign-ins (`4625`, `4624`);
- process creation (`4688`);
- user and privileged-group changes (`4720`, `4728`, `4732`);
- PowerShell module/script-block records (`4103`, `4104`);
- Defender detections (`1116`, `1117`); and
- severe System/Application events.

`60-Configure-EventForwarding.ps1 -Mode Source` enables the corresponding Logon, Process Creation, User Account Management, and Security Group Management audit subcategories on the member server and clients.

Production environments need capacity planning, protected retention, access reviews, alert rules, clock synchronization, and privacy/legal review. Those are intentionally outside this lab.

## Credential handling rules

1. Use the interactive secure prompts in the scripts.
2. Store DSRM and admin credentials in a password manager, not a text file or shell history.
3. Never export a LAPS password into documentation or validation output.
4. Never commit certificates with private keys, VM images, event exports, or registry hives.
5. Rotate any value immediately if it appears in a screenshot or Git history.

## Recovery

Use VM checkpoints for learning recovery, but do not confuse them with AD-aware production backups. Before a schema change, checkpoint every lab VM while powered down. If forest creation or the LAPS extension fails irrecoverably, revert the isolated lab set together or rebuild from the scripts; do not mix reverted DC state with newer domain members.
