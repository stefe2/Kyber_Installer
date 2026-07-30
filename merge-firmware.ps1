# Fusionne les 4 fichiers d'un build PlatformIO en une image flash unique,
# publiable dans un manifeste avec "offset": 0.
#
# Usage:
#   .\merge-firmware.ps1 -Source "C:\projet\.pio\build\esp32" -Output "firmware\Kyber_V233.bin"
#   .\merge-firmware.ps1 -Source ... -Output ... -Chip esp32s3
#
# Procedure complete et diagnostic: docs/AJOUTER-UNE-VERSION.md

param(
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [Parameter(Mandatory = $true)]
    [string]$Output,

    [ValidateSet("esp32", "esp32s2", "esp32s3", "esp32c3", "esp32c6", "esp32h2")]
    [string]$Chip = "esp32",

    [string]$FlashMode = "dio",
    [string]$FlashFreq = "80m",
    [string]$FlashSize = "4MB"
)

$ErrorActionPreference = "Stop"

# L'ESP32 et l'ESP32-S2 attendent le bootloader a 0x1000 ; les puces plus recentes a 0x0.
# Se tromper ici produit une image qui ne demarre pas, sans aucun message d'erreur.
$bootloaderOffset = if ($Chip -in @("esp32", "esp32s2")) { "0x1000" } else { "0x0" }

# ------------------------------------------------------------------ esptool
$esptool = $null
foreach ($candidate in @("esptool.py", "esptool")) {
    if (Get-Command $candidate -ErrorAction SilentlyContinue) { $esptool = $candidate; break }
}
if (-not $esptool) {
    Write-Host "esptool n'est pas trouve. Installation via pip..." -ForegroundColor Yellow
    pip install esptool
    foreach ($candidate in @("esptool.py", "esptool")) {
        if (Get-Command $candidate -ErrorAction SilentlyContinue) { $esptool = $candidate; break }
    }
    if (-not $esptool) {
        Write-Host "ERREUR: esptool reste introuvable apres installation." -ForegroundColor Red
        exit 1
    }
}

# esptool 5 a renomme les commandes et les options (merge-bin, --flash-mode).
$versionText = (& $esptool version 2>&1) -join " "
$major = 4
if ($versionText -match "v?(\d+)\.(\d+)") { $major = [int]$Matches[1] }
$useHyphens = $major -ge 5
Write-Host "esptool detecte: $esptool (version majeure $major)" -ForegroundColor DarkGray

# ------------------------------------------------------------- fichiers source
$bootloader = Join-Path $Source "bootloader.bin"
$partitions = Join-Path $Source "partitions.bin"
$bootApp0 = Join-Path $Source "boot_app0.bin"
$firmware = Join-Path $Source "firmware.bin"

# boot_app0.bin ne sort pas du build : il vient du framework Arduino. PlatformIO le copie
# parfois dans le dossier de build, sinon on le cherche dans le paquet du framework.
if (-not (Test-Path $bootApp0)) {
    $fallback = Join-Path $env:USERPROFILE ".platformio\packages\framework-arduinoespressif32\tools\partitions\boot_app0.bin"
    if (Test-Path $fallback) {
        Write-Host "boot_app0.bin absent du build, repris du framework Arduino." -ForegroundColor DarkGray
        $bootApp0 = $fallback
    }
}

foreach ($file in @($bootloader, $partitions, $bootApp0, $firmware)) {
    if (-not (Test-Path $file)) {
        Write-Host "ERREUR: Fichier non trouve: $file" -ForegroundColor Red
        exit 1
    }
}

# ------------------------------------------------------------------- fusion
Write-Host "`nFusion pour $Chip ($FlashMode / $FlashSize / $FlashFreq) :" -ForegroundColor Green
Write-Host "  - bootloader.bin @ $bootloaderOffset"
Write-Host "  - partitions.bin @ 0x8000"
Write-Host "  - boot_app0.bin  @ 0xE000"
Write-Host "  - firmware.bin   @ 0x10000"

$cmd = if ($useHyphens) { "merge-bin" } else { "merge_bin" }
$optMode = if ($useHyphens) { "--flash-mode" } else { "--flash_mode" }
$optFreq = if ($useHyphens) { "--flash-freq" } else { "--flash_freq" }
$optSize = if ($useHyphens) { "--flash-size" } else { "--flash_size" }

& $esptool --chip $Chip $cmd -o $Output `
    $optMode $FlashMode $optFreq $FlashFreq $optSize $FlashSize `
    $bootloaderOffset $bootloader `
    0x8000 $partitions `
    0xE000 $bootApp0 `
    0x10000 $firmware

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nERREUR lors de la fusion!" -ForegroundColor Red
    exit 1
}

$size = (Get-Item $Output).Length
Write-Host "`nFichier fusionne cree: $Output ($([math]::Round($size/1KB, 2)) KB)" -ForegroundColor Green

# ------------------------------------------------------------- verification
$checker = Join-Path $PSScriptRoot "tools\check-firmware.ps1"
if (Test-Path $checker) {
    Write-Host "`nVerification de l'image produite :" -ForegroundColor Cyan
    & $checker $Output
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`nL'image produite n'a pas passe la verification." -ForegroundColor Red
        exit 1
    }
}
