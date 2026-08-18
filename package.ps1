$ErrorActionPreference = 'Stop'

$srcRoot = 'C:\Users\admin\Desktop\System-Optimizer'
$outRoot = $env:USERPROFILE

# Self-sign the exes (Windows 11 Smart App Control requires an Authenticode
# signature; we use a throwaway self-signed cert generated in the CurrentUser
# store).
$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue
if (-not $cert) {
    Write-Host "Creating one-off self-signed code-signing cert..." -ForegroundColor Yellow
    $cert = New-SelfSignedCertificate -Type 'CodeSigningCert' -Subject 'CN=System Optimizer (self-signed)' -CertStoreLocation 'Cert:\CurrentUser\My' -NotAfter (Get-Date).AddYears(2)
}

Write-Host "Signing exes with: $($cert.Subject)" -ForegroundColor Cyan
$timeStamp = 'http://timestamp.digicert.com'
Get-ChildItem -LiteralPath $srcRoot -Filter '*.exe' | ForEach-Object {
    Write-Host "  sign $($_.Name)"
    try {
        Set-AuthenticodeSignature -FilePath $_.FullName -Certificate $cert -TimestampServer $timeStamp -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "    (timestamp server unreachable - signing without timestamp)" -ForegroundColor DarkYellow
        Set-AuthenticodeSignature -FilePath $_.FullName -Certificate $cert | Out-Null
    }
}

Write-Host 'Exporting signing cert so end-users can trust it on their PC...' -ForegroundColor Cyan
$cerOut = Join-Path $srcRoot 'WSO-Trust.cer'
Export-Certificate -Cert $cert -FilePath $cerOut | Out-Null
Write-Host "  -> $cerOut"

# Build the distributable ZIP
$ts      = Get-Date -Format 'yyyyMMdd'
$ver     = '1.3.0'
$zipName = "System-Optimizer-v$ver-$ts.zip"
$zipPath = Join-Path $outRoot $zipName
$guid = [Guid]::NewGuid().ToString('N').Substring(0,8)
$staging = Join-Path $env:TEMP ('wso-pkg-' + $guid)

if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
New-Item -ItemType Directory -Path $staging -Force | Out-Null

Write-Host ''
Write-Host "Building package: $zipPath" -ForegroundColor Cyan
$items = Get-ChildItem -LiteralPath $srcRoot
foreach ($item in $items) {
    Write-Host "  adding $($item.Name)"
    if ($item.PSIsContainer) {
        Copy-Item -LiteralPath $item.FullName -Destination $staging -Recurse -Force
    } else {
        Copy-Item -LiteralPath $item.FullName -Destination $staging -Force
    }
}

# Stage into the zip via Compress-Archive (use -Update loop)
Push-Location -LiteralPath $staging
try {
    $zipPathUnix = $zipPath.Replace('\','/')
    foreach ($item in (Get-ChildItem)) {
        if (Test-Path -LiteralPath $zipPath) {
            Compress-Archive -Path $item.FullName -DestinationPath $zipPath -CompressionLevel Optimal -Update
        } else {
            Compress-Archive -Path $item.FullName -DestinationPath $zipPath -CompressionLevel Optimal
        }
    }
} finally { Pop-Location }

# SHA256 + size
$hsh = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
$sumPath = Join-Path $outRoot ($zipName + '.sha256')
@"
# SHA256 of System Optimizer distribution package
# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# This package contains compiled exes + support files. See INSTALL.txt.
$hsh  $zipName
"@ | Set-Content -LiteralPath $sumPath -Encoding utf8

Write-Host ''
Write-Host 'DONE.' -ForegroundColor Green
Write-Host "  ZIP    : $zipPath  ($((Get-Item $zipPath).Length.ToString('N0')) bytes)"
Write-Host "  SHA256 : $sumPath"
Write-Host "  $hsh"
