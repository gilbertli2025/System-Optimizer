# Pester tests for the System Optimizer shared library (Common.ps1).
# Run: Invoke-Pester ./tests   (from the project root)
BeforeAll {
    Add-Type -AssemblyName System.Windows.Forms
    . 'C:\Users\admin\Documents\System-Optimizer -V1.4\lib\Common.ps1'
    $script:testLog = Join-Path $env:TEMP ("so-test-" + [guid]::NewGuid().ToString('N') + ".log")
    $script:LogFile = $script:testLog
    $script:UiSink = @{ MessageBox = { param($t, $tt, $b, $i) } }
}
Describe 'Common.ps1' {
    It 'Get-Paths returns the canonical keys' { ($(Get-Paths).Keys -contains 'UnifiedLog') | Should -BeTrue }
    It 'Write-Log appends a line to the log file' { Write-Log 'unit test line'; (Test-Path $script:testLog) | Should -BeTrue }
    It 'JSON round-trip stays a flat array' { $tmp = Join-Path $env:TEMP ("so-json-" + [guid]::NewGuid().ToString('N') + ".json"); Write-JsonArray -Path $tmp -Items @('a','b','c'); (@(Read-JsonArray -Path $tmp)).Count | Should -Be 3; Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
}
