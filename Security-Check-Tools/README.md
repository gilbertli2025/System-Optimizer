# Free Security Check Tools for Windows

A curated list of free utilities to check if a Windows PC is compromised or
running dangerous software. Download only from the **official** sites listed.

> **Golden rule:** run one good scanner, then get a **second opinion** from a
> different vendor. No single tool catches everything.

---

## 1. Full antivirus / malware scanners (second opinions)

| Tool | What it does | Official link |
|------|--------------|---------------|
| **Microsoft Defender Offline scan** | Deep scan at boot (built into Windows) | Windows Security â†’ Virus & threat protection â†’ Scan options |
| **Microsoft Safety Scanner (MSERT)** | On-demand single-use scanner | `www.microsoft.com/en-us/wdsi/threats/scanner` |
| **Malwarebytes Free** | Excellent second-opinion scanner + PUP removal | `malwarebytes.com` |
| **Kaspersky Virus Removal Tool (KVRT)** | Free portable virus removal | `usa.kaspersky.com/downloads/free-virus-removal-tool` |
| **ESET Online Scanner** | One-time online scan (no install) | `eset.com/online-scanner` |
| **Bitdefender / Sophos free scan** | Free cloud scanners | `bitdefender.com`, `sophos.com` |
| **HitmanPro** | Fast cloud second-opinion scanner | `hitmanpro.com` |

---

## 2. Rootkit / stealth threat scanners

| Tool | What it does | Official link |
|------|--------------|---------------|
| **Malwarebytes Anti-Rootkit / AdwCleaner** | Finds hidden rootkits & PUPs | `malwarebytes.com` |
| **GMER** | Rootkit/process inspector | `gmer.net` (advanced users) |
| **Sophos Virus Removal Tool** | Removes active/blocked threats | `sophos.com` |

---

## 3. System inspection (find what's running & auto-starting)

| Tool | What it does | Official link |
|------|--------------|---------------|
| **Process Explorer** | See every running process & what it uses | Microsoft **Sysinternals** |
| **Autoruns** | Every program that starts at boot/login | Microsoft **Sysinternals** |
| **TCPView** | See all network connections & ports | Microsoft **Sysinternals** |
| **Process Monitor (ProcMon)** | Watch files/registry/network activity live | Microsoft **Sysinternals** |

> Sysinternals is official Microsoft freeware: `learn.microsoft.com/en-us/sysinternals`

---

## 4. Network / firewall monitoring

| Tool | What it does | Official link |
|------|--------------|---------------|
| **GlassWire Free** | Visual network traffic monitor | `glasswire.com` |
| **Wireshark** | Deep packet inspection (advanced) | `wireshark.org` |

---

## 5. Ransomware help

| Tool | What it does | Official link |
|------|--------------|---------------|
| **No More Ransom decryptors** | Free decryptors for many ransomware strains | `nomoreransom.org` |

---

## 6. Account / browser security checks (no install)

- **Microsoft account** â†’ *Security* â†’ *Sign-in activity* â€” see recent logins & locations.
- **Outlook / OneDrive activity** â€” check for unknown sign-ins or shares.
- **Browser** â†’ check Extensions + Saved passwords; remove anything you don't remember installing.
- **Password check** â€” `haveibeenpwned.com` to see if your email was in a data breach.

---

## 7. When to run these

- **Monthly (or when suspicious):** Malwarebytes Free + Defender full scan.
- **PC acting weird:** Defender Offline scan + Malwarebytes + a Sysinternals check (Autoruns + Process Explorer).
- **After clicking something risky:** run MSERT + Kaspersky KVRT immediately, then change passwords.

---

## Red flags (run a scan if you see these)

- Sudden slowness / high CPU or disk with nothing open
- New browser toolbars/extensions, changed homepage, random pop-ups
- Browser redirects, unknown processes, unexpected accounts or logins
- Files renamed with `.locked` / `.crypt` (ransomware)

## If you think you're infected

1. Disconnect from the internet.
2. Run a Defender Offline scan + a second-opinion scanner.
3. Change important passwords **from another device**.
4. Check Microsoft account sign-in activity; sign out other sessions.
5. Consider System Restore (from your optimizer) or restore from a backup.

