<#
.SYNOPSIS
  V1.6 Utilities: duplicate-file finder, disk analyzer, large-file finder.
  All are READ-ONLY scans that return data; deletions go to the Recycle Bin
  only (never permanent) via Remove-ToRecycleBin. The GUI shows previews and
  requires explicit confirmation before deleting.
#>

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue

# Disk analyzer: return immediate subfolders of $Path with recursive sizes.
function Get-DiskUsage {
    [CmdletBinding()]
    param([string]$Path, [int]$Top = 20)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $results = @()
    foreach ($dir in (Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue)) {
        $size = (Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum).Sum
        $results += [pscustomobject]@{ Name = $dir.Name; Path = $dir.FullName; SizeMB = [math]::Round($size/1MB, 1) }
    }
    $results | Sort-Object SizeMB -Descending | Select-Object -First $Top
}

# Large-file finder: top files over a minimum size.
function Find-LargeFiles {
    [CmdletBinding()]
    param([string]$Path, [double]$MinimumMB = 100, [int]$Top = 30)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $min = [long]($MinimumMB * 1MB)
    Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -ge $min } |
        Sort-Object Length -Descending |
        Select-Object -First $Top |
        ForEach-Object { [pscustomobject]@{ Name = $_.Name; Path = $_.FullName; SizeMB = [math]::Round($_.Length/1MB,1) } }
}

# Duplicate-file finder: group by size, then hash candidates. Returns groups.
function Find-DuplicateFiles {
    [CmdletBinding()]
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }

    # 1) group files by size (candidates only)
    $bySize = @{}
    foreach ($f in (Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue)) {
        if ($f.Length -gt 0) {
            $k = $f.Length
            if (-not $bySize.ContainsKey($k)) { $bySize[$k] = [System.Collections.ArrayList]::new() }
            [void]$bySize[$k].Add($f)
        }
    }

    # 2) hash each size-group that has 2+ members
    $groups = [System.Collections.ArrayList]::new()
    foreach ($k in $bySize.Keys) {
        $pile = $bySize[$k]
        if ($pile.Count -ge 2) {
            $byHash = @{}
            foreach ($f in $pile) {
                $h = $null
                try { $h = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA1 -ErrorAction Stop).Hash } catch { $h = $null }
                if ($h) {
                    if (-not $byHash.ContainsKey($h)) { $byHash[$h] = [System.Collections.ArrayList]::new() }
                    [void]$byHash[$h].Add($f)
                }
            }
            foreach ($h in $byHash.Keys) {
                $dup = $byHash[$h]
                if ($dup.Count -gt 1) {
                    $members = @()
                    foreach ($f in $dup) { $members += [pscustomobject]@{ Path = $f.FullName; SizeMB = [math]::Round($f.Length/1MB,1) } }
                    [void]$groups.Add([pscustomobject]@{ Hash = $h; Files = $members })
                }
            }
        }
    }
    ,$groups
}

# Delete to Recycle Bin (safe). Returns count deleted.
function Remove-ToRecycleBin {
    [CmdletBinding()]
    param([string[]]$Paths)
    $n = 0
    foreach ($p in $Paths) {
        if (Test-Path -LiteralPath $p) {
            try {
                $item = Get-Item -LiteralPath $p
                if ($item.PSIsContainer) {
                    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($p, 'OnlyErrorDialogs', 'SendToRecycleBin')
                } else {
                    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p, 'OnlyErrorDialogs', 'SendToRecycleBin')
                }
                $n++
            } catch { Write-Log "  could not delete $p : $($_.Exception.Message)" }
        }
    }
    return $n
}

$script:LibUtilitiesLoaded = $true
