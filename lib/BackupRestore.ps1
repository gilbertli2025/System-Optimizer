<#
.SYNOPSIS
  Backup & Restore user settings, plus a pre-flight readiness check.
  Backs up safe, portable items (browser bookmarks, Wi-Fi profiles, HKCU
  settings, the tool's own profile) to a chosen USB/folder. Passwords are
  intentionally NOT backed up (security risk, not portable) - a password
  manager is recommended instead.

  v1.4 safety: BitLocker is never enabled without a USB drive.
#>

$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------
# Pre-flight check - run before applying changes.
# Returns $true if it is safe to proceed, $false otherwise.
# --------------------------------------------------------------------------
function Test-PreFlight {
    [CmdletBinding()]
    param([string[]]$SecurityIds = @(), [string[]]$MaintIds = @())

    $ok = $true

    if (-not (Test-Admin)) {
        Show-Message 'System Optimizer must run as Administrator to make changes. Please restart it as Administrator.' 'Admin required' Error
        Write-Log "PRE-FLIGHT FAIL: not running as admin."
        return $false
    }
    Write-Log "PRE-FLIGHT: admin OK."

    # Enough free space on C: (need at least ~3 GB to be safe)
    try {
        $c = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop
        $freeGB = [math]::Round($c.FreeSpace/1GB, 1)
        if ($freeGB -lt 3) {
            Show-Message "Low disk space on C: ($freeGB GB free). Optimizer may need space; please free some first." 'Low disk space' Warn
            Write-Log "PRE-FLIGHT WARN: low disk space ($freeGB GB)."
        } else {
            Write-Log "PRE-FLIGHT: free space OK ($freeGB GB)."
        }
    } catch { Write-Log "PRE-FLIGHT WARN: could not check disk space." }

    # System Restore enabled on C: so changes are reversible
    try {
        $rps = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue)
        if ($rps.Count -eq 0) {
            Show-Message 'No System Restore point found on C:. Consider enabling System Restore (Security item 6) so changes can be rolled back.' 'Restore' Warn
            Write-Log "PRE-FLIGHT WARN: no restore point found."
        } else {
            Write-Log "PRE-FLIGHT: restore point present ($($rps.Count) point(s))."
        }
    } catch { Write-Log "PRE-FLIGHT WARN: could not check restore points." }

    # If BitLocker is being applied, a USB drive must be present (recovery key)
    if ($SecurityIds -contains 'bitlocker') {
        $bl = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction SilentlyContinue
        $alreadyOn = ($bl -and $bl.ProtectionStatus -eq 'On')
        if (-not $alreadyOn) {
            $removable = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2" -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 2 } | Select-Object -First 1
            if (-not $removable) {
                Show-Message 'BitLocker needs a USB drive to store the recovery key. Plug in a USB drive first, or skip BitLocker.' 'BitLocker' Warn
                Write-Log "PRE-FLIGHT FAIL: BitLocker selected but no USB drive present."
                $ok = $false
            } else {
                Write-Log "PRE-FLIGHT: USB drive present for BitLocker recovery key."
            }
        } else {
            Write-Log "PRE-FLIGHT: BitLocker already on (no change needed)."
        }
    }

    if (-not $ok) { Write-Log 'PRE-FLIGHT: one or more required checks failed.' }
    else { Write-Log 'PRE-FLIGHT: OK to proceed.' }
    return $ok
}

# --------------------------------------------------------------------------
# Backup user settings to a chosen folder (prefer a USB drive).
# --------------------------------------------------------------------------
function Get-BackupTarget {
    # Prefer a removable (USB) drive; else ask the user to pick a folder.
    $removable = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2" -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 2 } | Select-Object -First 1
    if ($removable) {
        $dir = Join-Path ($removable.DeviceID) 'SystemOptimizer-Backup'
        return $dir
    }
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Choose where to save the settings backup (a USB drive is best)'
    if ($dlg.ShowDialog() -eq 'OK') { return $dlg.SelectedPath }
    return $null
}

function Backup-UserSettings {
    $target = Get-BackupTarget
    if (-not $target) { Show-Message 'No backup location chosen.' 'Backup' Warn; return }
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Write-Log "Backing up user settings to: $target"

    # 1) Browser bookmarks
    $bk = 0
    foreach ($b in @('Microsoft\Edge','Google\Chrome')) {
        $bookmark = Join-Path $env:LOCALAPPDATA ("$b\User Data\Default\Bookmarks")
        if (Test-Path -LiteralPath $bookmark) {
            $dest = Join-Path $target ("bookmarks-" + ($b.Split('\')[-1]) + ".json")
            Copy-Item -LiteralPath $bookmark -Destination $dest -Force
            Write-Log "  Backed up bookmarks: $($b.Split('\')[-1])"
            $bk++
        }
    }
    if ($bk -eq 0) { Write-Log "  No browser bookmarks found (Edge/Chrome)." }

    # 2) Wi-Fi profiles
    try {
        $wifi = Join-Path $target 'wifi'
        New-Item -ItemType Directory -Path $wifi -Force | Out-Null
        & netsh.exe wlan export profile folder=$wifi key=clear 2>&1 | Out-Null
        $wc = @(Get-ChildItem $wifi -Filter '*.xml' -ErrorAction SilentlyContinue).Count
        Write-Log "  Backed up Wi-Fi profiles: $wc"
    } catch { Write-Log "  Wi-Fi export failed: $($_.Exception.Message)" }

    # 3) User settings (HKCU) as a .reg snapshot
    try {
        $regFile = Join-Path $target ("HKCU-settings-" + $env:COMPUTERNAME + ".reg")
        & reg.exe export "HKCU" $regFile /y 2>&1 | Out-Null
        Write-Log "  Backed up user registry settings (HKCU).reg."
    } catch { Write-Log "  HKCU export failed: $($_.Exception.Message)" }

    # 4) The tool's own profile (checked checkboxes)
    try {
        $profile = Join-Path $target 'SystemOptimizer-profile.json'
        @{
            services = @($script:svcChecks  | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
            security = @($script:secChecks   | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
            maint    = @($script:maintChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
            repair   = @($script:repairChecks| Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
        } | ConvertTo-Json | Set-Content -LiteralPath $profile -Encoding UTF8
        Write-Log "  Backed up System Optimizer profile."
    } catch { Write-Log "  Profile export failed: $($_.Exception.Message)" }

    Write-Log "Backup complete. Location: $target"
    Show-Message "Settings backed up to:`n$target" 'Backup' Info
    Write-Log "NOTE: passwords are NOT backed up (security). Use a password manager for those."
}

# --------------------------------------------------------------------------
# Restore user settings from a chosen folder.
# --------------------------------------------------------------------------
function Restore-UserSettings {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Choose the backup folder to restore from'
    if ($dlg.ShowDialog() -ne 'OK') { return }
    $src = $dlg.SelectedPath
    if (-not (Test-Path $src)) { Show-Message 'Folder not found.' 'Restore' Warn; return }
    Write-Log "Restoring user settings from: $src"

    $restored = 0
    foreach ($b in @(@('Edge','Microsoft\Edge'), @('Chrome','Google\Chrome'))) {
        $bookmark = Join-Path $src ("bookmarks-" + $b[0] + ".json")
        if (Test-Path -LiteralPath $bookmark) {
            $dest = Join-Path $env:LOCALAPPDATA ("$($b[1])\User Data\Default\Bookmarks")
            if (Test-Path -LiteralPath (Split-Path $dest)) {
                Copy-Item -LiteralPath $bookmark -Destination $dest -Force
                Write-Log "  Restored bookmarks: $($b[0])"
                $restored++
            }
        }
    }

    # Wi-Fi profiles
    $wifi = Join-Path $src 'wifi'
    if (Test-Path $wifi) {
        Get-ChildItem $wifi -Filter '*.xml' -ErrorAction SilentlyContinue | ForEach-Object {
            & netsh.exe wlan add profile filename="$($_.FullName)" user=current 2>&1 | Out-Null
        }
        Write-Log "  Restored Wi-Fi profiles."
        $restored++
    }

    # HKCU registry
    $regFile = Get-ChildItem $src -Filter 'HKCU-settings-*.reg' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($regFile) {
        & reg.exe import $regFile.FullName 2>&1 | Out-Null
        Write-Log "  Restored user registry settings. (You may need to sign out/in for full effect.)"
        $restored++
    }

    if ($restored -eq 0) { Write-Log "No restorable settings found in $src." }
    else { Write-Log "Restore complete." }
    Show-Message 'Restore complete. Some settings (Wi-Fi, registry) need a sign-out/in or reboot to take effect.' 'Restore' Info
}

$script:LibBackupLoaded = $true
