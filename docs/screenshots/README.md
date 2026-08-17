# Screenshot evidence checklist

Capture your own lab after it is deployed. Do not use mock screenshots as proof.

Recommended evidence:

1. Hypervisor console showing only the four `LAB-*` VM names.
2. AD Users and Computers with the `ReedLab` OU tree expanded.
3. A fictional user's department group membership.
4. The global-role → domain-local-resource group nesting.
5. Group Policy Management showing GPO names and OU links.
6. Engineering share ACL and share permissions, with no real usernames.
7. Successful Engineering access and denied Finance access from a client.
8. Windows LAPS metadata with the password field completely absent or covered.
9. `ForwardedEvents` showing source machine, event ID, and timestamp only.
10. The final `90-Validate-Lab.ps1` pass/fail table.

Before publishing, crop or redact:

- passwords, hashes, recovery keys, and QR codes;
- host usernames and personal folder paths;
- Windows product keys and activation identifiers;
- public IP addresses, Wi-Fi names, and physical-network details;
- personal email, browser tabs, notifications, and bookmarks;
- VM generation IDs, certificates, or values that are not needed to prove the claim; and
- any name or detail copied from a real workplace.

Store raw screenshots outside the repository. Commit only reviewed, sanitized PNG files and add useful alt text in the README.
