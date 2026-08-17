# Honest resume and LinkedIn wording

Use only claims you can demonstrate. Pick two or three bullets that match the role; do not paste every line.

## If you have built the code but not deployed the VMs yet

- Designed a four-node Active Directory homelab for a fictional `.test` domain, with PowerShell automation for OU design, AGDLP groups, domain joining, Group Policy, Windows LAPS, file services, and validation.
- Wrote guarded, repeatable PowerShell deployment scripts using secure credential prompts, `-WhatIf`, configuration data, and CI parser/secret-hygiene checks.
- Documented a least-privilege Windows identity architecture, build runbook, troubleshooting flow, security assumptions, and measurable acceptance criteria.

## After you deploy and validate it

- Built and validated a four-VM Windows Server/Windows 11 Active Directory lab with AD DS, DNS, DHCP, Group Policy, SMB file services, Windows LAPS, and centralized event forwarding.
- Implemented AGDLP-based departmental access across five SMB shares, separating user roles from resource permissions and verifying allowed/denied access with test identities.
- Automated repeatable OU, group, user, policy, and share deployment in PowerShell with environment safety guards, secure prompts, `-WhatIf`, and a pass/fail validation report.
- Deployed Windows LAPS with encrypted AD password backup, scoped self-write/read delegation, 20-character rotation policy, and successful-access auditing.
- Centralized selected authentication, process, PowerShell, Defender, and system events through source-initiated Windows Event Forwarding for defensive investigation practice.

## Short project description

> ReedLab is a four-VM Active Directory environment I built to practise identity, access, endpoint policy, and Windows monitoring. The environment is reproducible from PowerShell, uses AGDLP for departmental access, protects local-admin credentials with Windows LAPS, and forwards selected events to a central collector. All data and infrastructure are fictional and isolated.

## Interview framing

Lead with one design decision and one fault you genuinely resolved. Good examples after deployment are DNS order during domain join, OU placement affecting GPO scope, group-token refresh after membership changes, or WEF subscription timing. Never invent an outage, user impact, scale, or production deployment.
