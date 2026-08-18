<#
.SYNOPSIS
  Builds the System Optimizer apps: compiles the PowerShell sources to .exe
  with PS2EXE, signs them with your code-signing certificate, and builds the
  .msi installers with WiX v3.

.DESCRIPTION
  Tool locations can be overridden with environment variables (or a paths.json
  next to this script). Sign thumbprint can be set via $SignThumbprint below
  or $env:WSO_SIGN_THUMBPRINT. Set to $null to skip signing.

  Example:
    $env:WSO_PS2EXE = 'C:\Tools\PS2EXE\Module\ps2exe.psm1'
    $env:WSO_WIX    = 'C:\Tools\wix\bin'
    $env:WSO_SIGN_THUMBPRINT = 'C2DD93EC094DEAD52F7C275007B646452A9D79A6'
    .\build.ps1

.EXAMPLE
  .\build.ps1
#>

[CmdletBinding()]
param(
    [string]$Version = '1.3.0',
    [string]$SourceDir,            # defaults to script directory
    [string]$OutDir,               # defaults to %USERPROFILE%\Desktop\System-Optimizer
    [string]$Ps2ExeModule,         # defaults to env WSO_PS2EXE
    [string]$WixBin,               # defaults to env WSO_WIX
    [string]$SignThumbprint,       # defaults to env WSO_SIGN_THUMBPRINT
    [string]$TimeStampServer = 'http://timestamp.digicert.com'
)

$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------
# Resolve configuration (env vars > explicit param > default)
# --------------------------------------------------------------------------
$ScriptRoot = Split-Path -Parent $PSCommandPath

function Get-ConfigPath {
    param([string]$Key, [string]$Default)
    $envKey = "WSO_$($Key.ToUpper())"
    if (Test-Path "env:$envKey" -ErrorAction SilentlyContinue) {
        $val = Get-Content "env:$envKey" -ErrorAction SilentlyContinue
        if ($val) { return "$val" }
    }
    $json = Join-Path $ScriptRoot 'paths.json'
    if (Test-Path -LiteralPath $json) {
        try {
            $o = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
            if ($o.$Key) { return "$($o.$Key)" }
        } catch { }
    }
    return $Default
}

if (-not $SourceDir)      { $SourceDir      = $ScriptRoot }
if (-not $OutDir)         { $OutDir         = Get-ConfigPath -Key 'OutDir'   -Default (Join-Path $env:USERPROFILE 'Desktop\System-Optimizer') }
if (-not $Ps2ExeModule)   { $Ps2ExeModule   = Get-ConfigPath -Key 'Ps2Exe'   -Default '' }
if (-not $WixBin)         { $WixBin         = Get-ConfigPath -Key 'Wix'      -Default '' }
if (-not $SignThumbprint) { $SignThumbprint = Get-ConfigPath -Key 'Thumbprint' -Default '' }
if (-not $SignThumbprint) { $SignThumbprint = $null }

Write-Host "=== Building System Optimizer $Version ===" -ForegroundColor Cyan
Write-Host "  SourceDir:    $SourceDir"
Write-Host "  OutDir:       $OutDir"
Write-Host "  PS2EXE:       $Ps2ExeModule"
Write-Host "  WiX:          $WixBin"
Write-Host "  Sign thumb:   $SignThumbprint"

if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
function Invoke-Sign {
    param([string]$Path)
    if (-not $SignThumbprint) { Write-Host '  (signing skipped)' -ForegroundColor DarkGray; return }
    $cert = Get-ChildItem "Cert:\CurrentUser\My\$SignThumbprint" -ErrorAction Stop
    Set-AuthenticodeSignature -FilePath $Path -Certificate $cert -TimeStampServer $TimeStampServer -ErrorAction Stop | Out-Null
    $st = (Get-AuthenticodeSignature $Path).Status
    Write-Host "  signed $Path -> $st" -ForegroundColor Green
}

function Invoke-PS2Exe {
    param(
        [string]$Input,
        [string]$Output,
        [string]$Title
    )
    if (-not (Test-Path -LiteralPath $Ps2ExeModule)) {
        Write-Warning "PS2EXE module not found at $Ps2ExeModule - skipping $Output."
        return
    }
    Import-Module $Ps2ExeModule -Force -ErrorAction Stop
    ps2exe -inputFile $Input -outputFile $Output -title $Title -noConsole -version $Version -ErrorAction Stop | Out-Null
    Write-Host "  compiled $Output" -ForegroundColor Green
    Invoke-Sign $Output
}

function Invoke-WixBuild {
    param([string]$WxsFile, [string]$MsiName)
    if (-not (Test-Path -LiteralPath (Join-Path $WixBin 'candle.exe'))) {
        Write-Warning "WiX (candle.exe) not found at $WixBin - skipping $MsiName."
        return
    }
    $wixobj = Join-Path $env:TEMP "$WxsFile.wixobj"
    & (Join-Path $WixBin 'candle.exe') (Join-Path $SourceDir $WxsFile) "-dSourceDir=$SourceDir" "-dVersion=$Version" -out $wixobj | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "candle failed: $WxsFile" }

    $msi = Join-Path $OutDir $MsiName
    $libDir = Join-Path $SourceDir 'lib'
    if (Test-Path -LiteralPath $libDir) { Copy-Item -LiteralPath $libDir -Destination (Join-Path $OutDir 'lib') -Recurse -Force }

    & (Join-Path $WixBin 'light.exe') $wixobj -out $msi -ext WiXUtilExtension | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "light failed: $MsiName" }
    Write-Host "  MSI built: $msi" -ForegroundColor Green
    Invoke-Sign $msi
}

# --------------------------------------------------------------------------
# 1. Compile exes
# --------------------------------------------------------------------------
Invoke-PS2Exe -Input (Join-Path $SourceDir 'SystemOptimizer-GUI.ps1')         -Output (Join-Path $OutDir 'SystemOptimizer.exe')         -Title 'System Optimizer'
Invoke-PS2Exe -Input (Join-Path $SourceDir 'WinServiceOptimizer-GUI.ps1')      -Output (Join-Path $OutDir 'WinServiceOptimizer-GUI.exe')  -Title 'Windows Services Optimizer'
Invoke-PS2Exe -Input (Join-Path $SourceDir 'WinServiceOptimizer.ps1')         -Output (Join-Path $OutDir 'Windows-Services-Optimizer.exe') -Title 'Windows Services Optimizer (console)'
Invoke-PS2Exe -Input (Join-Path $SourceDir 'WinSecurityOptimizer-GUI.ps1')     -Output (Join-Path $OutDir 'WinSecurityOptimizer-GUI.exe')  -Title 'Windows Security Optimizer'
Invoke-PS2Exe -Input (Join-Path $SourceDir 'WinSecurityOptimizer.ps1')        -Output (Join-Path $OutDir 'Windows-Security-Optimizer.exe') -Title 'Windows Security Optimizer (console)'

# Copy launcher + sources + lib/ so the installed folder is self-contained.
Copy-Item -LiteralPath (Join-Path $SourceDir '1-Click-System-Optimizer.cmd') -Destination $OutDir -Force
Copy-Item -LiteralPath (Join-Path $SourceDir 'HELP.md')                       -Destination $OutDir -Force
Copy-Item -LiteralPath (Join-Path $SourceDir 'README.md')                      -Destination $OutDir -Force
if (Test-Path -LiteralPath (Join-Path $SourceDir 'lib')) {
    Copy-Item -LiteralPath (Join-Path $SourceDir 'lib') -Destination (Join-Path $OutDir 'lib') -Recurse -Force
}

# --------------------------------------------------------------------------
# 2. Build MSIs
# --------------------------------------------------------------------------
Invoke-WixBuild -WxsFile 'SystemOptimizer.wxs'          -MsiName 'System-Optimizer.msi'
Invoke-WixBuild -WxsFile 'WindowsServicesOptimizer.wxs' -MsiName 'Windows-Services-Optimizer.msi'
Invoke-WixBuild -WxsFile 'WindowsSecurityOptimizer.wxs' -MsiName 'Windows-Security-Optimizer.msi'

Write-Host '=== Done ===' -ForegroundColor Cyan
