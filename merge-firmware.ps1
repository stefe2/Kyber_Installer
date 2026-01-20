# Script pour fusionner les fichiers firmware PlatformIO en un seul .bin
# Usage: .\merge-firmware.ps1 -Source "C:\path\to\platformio\project\.pio\build\esp32" -Output "firmware\Kyber_V127.bin"

param(
    [Parameter(Mandatory=$true)]
    [string]$Source,
    
    [Parameter(Mandatory=$true)]
    [string]$Output
)

# Vérifier si esptool est installé
$esptool = "esptool.py"
if (!(Get-Command $esptool -ErrorAction SilentlyContinue)) {
    Write-Host "esptool.py n'est pas trouvé. Installation via pip..." -ForegroundColor Yellow
    pip install esptool
}

# Chemins des fichiers source
$bootloader = Join-Path $Source "bootloader.bin"
$partitions = Join-Path $Source "partitions.bin"
$bootApp0 = Join-Path $Source "boot_app0.bin"
$firmware = Join-Path $Source "firmware.bin"

# Vérifier que tous les fichiers existent
$files = @($bootloader, $partitions, $bootApp0, $firmware)
foreach ($file in $files) {
    if (!(Test-Path $file)) {
        Write-Host "ERREUR: Fichier non trouvé: $file" -ForegroundColor Red
        exit 1
    }
}

Write-Host "Fusion des fichiers firmware..." -ForegroundColor Green
Write-Host "  - bootloader.bin @ 0x0000"
Write-Host "  - partitions.bin @ 0x8000 (32768)"
Write-Host "  - boot_app0.bin @ 0xE000 (57344)"
Write-Host "  - firmware.bin @ 0x10000 (65536)"

# Fusionner avec esptool
& $esptool --chip esp32 merge_bin `
    -o $Output `
    --flash_mode dio `
    --flash_freq 40m `
    --flash_size 4MB `
    0x0 $bootloader `
    0x8000 $partitions `
    0xE000 $bootApp0 `
    0x10000 $firmware

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nFichier fusionné créé avec succès: $Output" -ForegroundColor Green
    $size = (Get-Item $Output).Length
    Write-Host "Taille: $([math]::Round($size/1KB, 2)) KB" -ForegroundColor Cyan
} else {
    Write-Host "`nERREUR lors de la fusion!" -ForegroundColor Red
    exit 1
}
