<#
.SYNOPSIS
  Pester 5/6 tests for lib/*.ps1. These tests mock the OS-touching cmdlets so
  they can run anywhere (no admin rights, no real changes).

  Run:
    Install-Module -Name Pester -Force -SkipPublisherCheck
    Invoke-Pester ./tests

  No actual Windows settings are touched.
#>

BeforeAll {
    # Redirect every %ProgramData%* path to a temp folder so the tests are
    # completely isolated from the real Windows machine.
    $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) "wso-tests-$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null

    # lib/Common.ps1 hardcodes $env:ProgramData. Point ProgramData at the
    # temp dir for this process and then dot-source everything.
    $env:ProgramData = $script:TestRoot

    $lib = Join-Path (Split-Path -Parent $PSCommandPath) '..\lib'
    $lib = (Resolve-Path $lib).Path
    . (Join-Path $lib 'Common.ps1')
    . (Join-Path $lib 'ServiceCatalog.ps1')
    . (Join-Path $lib 'SecurityItems.ps1')
    . (Join-Path $lib 'MaintenanceItems.ps1')
    . (Join-Path $lib 'Repair.ps1')
    . (Join-Path $lib 'Review.ps1')

    # Wire a sink that just collects lines, instead of touching a TextBox.
    $script:CapturedLines = [System.Collections.ArrayList]::new()
    $script:LogFile = $null
    $script:LogSink = { param($l) [void]$script:CapturedLines.Add($l) }
}

AfterAll {
    if (Test-Path -LiteralPath $script:TestRoot) {
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Common.ps1 helpers' {
    It 'Write-Log writes a UTF-8 (no BOM) timestamped line' {
        $logPath = Join-Path $script:TestRoot 'log.txt'
        $script:LogFile = $logPath
        Write-Log 'hello'
        $bytes = [System.IO.File]::ReadAllBytes($logPath)
        # No BOM: first byte must not be 0xEF
        $bytes[0] | Should -Not -Be 0xEF
        # The message is present (Write-Log prepends a timestamp)
        [System.Text.Encoding]::ASCII.GetString($bytes) | Should -Match 'hello'
    }

    It 'Read-JsonArray returns empty on missing file' {
        $r = Read-JsonArray -Path (Join-Path $script:TestRoot 'no.json')
        @($r).Count | Should -Be 0
    }

    It 'Read-JsonArray parses JSON and returns an array' {
        $path = Join-Path $script:TestRoot 'arr.json'
        # Write WITHOUT BOM (the same way the lib writes backups)
        [System.IO.File]::WriteAllText($path, '{"Name":"x","Value":"y"}', [System.Text.UTF8Encoding]::new($false))
        $r = @(Read-JsonArray -Path $path)
        $r.Count | Should -Be 1
        $r[0].Name | Should -Be 'x'
    }

    It 'Set-KeyedRow round-trips through Read-JsonArray (order-independent)' {
        $path = Join-Path $script:TestRoot 'k.json'
        Set-KeyedRow -Path $path -Key 'a' -Value '{"x":1}'
        Set-KeyedRow -Path $path -Key 'b' -Value '{"y":2}'
        Set-KeyedRow -Path $path -Key 'a' -Value '{"x":99}'   # overwrite
        $r = @(Read-JsonArray -Path $path)
        $map = @{}
        foreach ($row in $r) { $map[$row.Name] = $row.Value }
        $map.Count | Should -Be 2
        $map['a'] | Should -Be '{"x":99}'
        $map['b'] | Should -Be '{"y":2}'
    }

    It 'Set-KeyedRow writes UTF-8 without BOM' {
        $path = Join-Path $script:TestRoot 'utf8.json'
        Set-KeyedRow -Path $path -Key 'a' -Value 'v'
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $bytes[0] | Should -Not -Be 0xEF
    }
}

Describe 'Security backup round-trip (no BOM, the historic bug)' {
    BeforeAll {
        Mock -CommandName Set-MpPreference -MockWith { } -ModuleName $null
        Mock -CommandName Set-NetFirewallProfile -MockWith { } -ModuleName $null
    }

    It 'Save backup row, then read it back through Read-JsonArray' {
        $path = $script:Paths.SecurityBackupFile
        Set-KeyedRow -Path $path -Key 'firewall' -Value (@{ Domain=@{DefaultInboundAction='Allow';Enabled=$true}; Private=@{DefaultInboundAction='Allow';Enabled=$true}; Public=@{DefaultInboundAction='Allow';Enabled=$true} } | ConvertTo-Json -Compress)
        $rows = @(Read-JsonArray -Path $path)
        $rows.Count          | Should -Be 1
        $rows[0].Name        | Should -Be 'firewall'
        $v = $rows[0].Value | ConvertFrom-Json
        $v.Domain.DefaultInboundAction | Should -Be 'Allow'
    }
}

Describe 'Maintenance backup round-trip' {
    It 'Save and read back a power plan GUID' {
        $path = $script:Paths.MaintBackupFile
        Set-KeyedRow -Path $path -Key 'powerplan' -Value '381b4222-f694-41f0-9685-ff5bb260df2e'
        Set-KeyedRow -Path $path -Key 'tips'      -Value (@{ 'SubscribedContent-310093Enabled' = 1 } | ConvertTo-Json -Compress)
        $rows = @(Read-JsonArray -Path $path)
        $names = @($rows | ForEach-Object { $_.Name })
        $names | Should -Contain 'powerplan'
        $names | Should -Contain 'tips'
    }
}

Describe 'Service backup round-trip' {
    It 'Save and read back a service row' {
        $path = $script:Paths.ServicesBackupFile
        $row = [PSCustomObject]@{ Name='DiagTrack'; OldStartType='Automatic'; WasRunning=$true; Category='Safe'; Date=(Get-Date).ToString('o') }
        Write-CsvRows -Path $path -Rows @($row)
        $r = @(Read-CsvRows -Path $path)
        $r.Count         | Should -Be 1
        $r[0].Name       | Should -Be 'DiagTrack'
        $r[0].OldStartType | Should -Be 'Automatic'
    }
}

Describe 'Restore-Security keeps the backup when one item fails' {
    It 'Survives a partial failure without losing the backup' {
        $path = $script:Paths.SecurityBackupFile
        Set-KeyedRow -Path $path -Key 'autorun'  -Value '145'
        Set-KeyedRow -Path $path -Key 'lockout'  -Value (@{ threshold=$null; duration=15; window=15 } | ConvertTo-Json -Compress)
        # Force a failure by removing Set-ItemProperty mock for lockout
        Mock -CommandName Set-ItemProperty -MockWith { throw 'simulated' } -ModuleName $null -ParameterFilter { $Name -eq 'lockoutthreshold' }

        $script:LogFile = $path + '.log'
        Restore-SecurityItems -Ids @('autorun','lockout')

        Test-Path -LiteralPath $path | Should -BeTrue 'backup file must be kept on partial failure'
        $remaining = @(Read-JsonArray -Path $path)
        ($remaining | ForEach-Object { $_.Name }) -contains 'lockout' | Should -BeTrue
    }
}
