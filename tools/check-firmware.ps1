# Analyse un binaire ESP32 et dit s'il est publiable tel quel dans un manifeste.
#
# Usage: .\tools\check-firmware.ps1 firmware\Kyber_V232.bin
#
# Repond a trois questions:
#   1. Est-ce une image flash complete (utilisable avec "offset": 0) ou un firmware.bin brut ?
#   2. L'image applicative est-elle intacte (checksum + SHA-256) ?
#   3. Quelles longueurs de segments le bootloader affichera-t-il sur la console serie ?
#      (utile pour identifier a distance quelle version tourne sur une carte)

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "ERREUR: fichier introuvable: $Path" -ForegroundColor Red
    exit 1
}

$b = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path))
$name = Split-Path -Leaf $Path
Write-Host "`n$name — $($b.Length) octets ($([math]::Round($b.Length/1KB,1)) KiB)`n" -ForegroundColor Cyan

$flashMode = @{ 0 = "qio"; 1 = "qout"; 2 = "dio"; 3 = "dout" }
$flashFreq = @{ 0 = "40m"; 1 = "26m"; 2 = "20m"; 15 = "80m" }
$flashSize = @{ 0 = "1MB"; 1 = "2MB"; 2 = "4MB"; 3 = "8MB"; 4 = "16MB" }

function Test-ImageHeader([byte[]]$data, [int]$off) {
    if ($off + 24 -gt $data.Length) { return $false }
    return $data[$off] -eq 0xE9
}

function Test-PartitionTable([byte[]]$data, [int]$off) {
    if ($off + 2 -gt $data.Length) { return $false }
    return ($data[$off] -eq 0xAA) -and ($data[$off + 1] -eq 0x50)
}

# ---------------------------------------------------------------- classification
$hasTable = Test-PartitionTable $b 0x8000
$blOff = -1
if ($hasTable) {
    if (Test-ImageHeader $b 0x1000) { $blOff = 0x1000 }   # ESP32 / ESP32-S2
    elseif (Test-ImageHeader $b 0) { $blOff = 0 }          # ESP32-S3 / C3 / C6...
}

$appOff = -1
$isRaw = $false
if ($hasTable -and $blOff -ge 0) {
    Write-Host "TYPE : image flash complete (fusionnee) — publiable avec `"offset`": 0" -ForegroundColor Green
    Write-Host "       bootloader a 0x$('{0:X}' -f $blOff), table de partitions a 0x8000"
    $appOff = 0x10000
}
elseif ((Test-ImageHeader $b 0) -and $b.Length -gt 0x24 -and
        $b[0x20] -eq 0x32 -and $b[0x21] -eq 0x54 -and $b[0x22] -eq 0xCD -and $b[0x23] -eq 0xAB) {
    Write-Host "TYPE : firmware.bin BRUT (image applicative seule)" -ForegroundColor Yellow
    Write-Host "       INUTILISABLE avec `"offset`": 0 — il faut le fusionner." -ForegroundColor Yellow
    Write-Host "       Voir docs/AJOUTER-UNE-VERSION.md"
    $appOff = 0
    $isRaw = $true
}
else {
    Write-Host "TYPE : format non reconnu" -ForegroundColor Red
    Write-Host "       premiers octets: $(($b[0..7] | ForEach-Object { '{0:X2}' -f $_ }) -join ' ')"
    exit 1
}

# ------------------------------------------------------- parametres flash + bootloader
if ($blOff -ge 0) {
    $h = $b[$blOff..($blOff + 3)]
    $mode = $flashMode[[int]$h[2]]
    $freq = $flashFreq[[int]($h[3] -band 0x0F)]
    $size = $flashSize[[int]($h[3] -shr 4)]
    Write-Host "`nPARAMETRES FLASH : mode=$mode taille=$size frequence=$freq"
    if ($freq -ne "80m" -or $mode -ne "dio" -or $size -ne "4MB") {
        Write-Host "  Attention: les images Kyber de production sont en dio / 4MB / 80m." -ForegroundColor Yellow
    }

    Write-Host "`nEMPREINTE BOOTLOADER (ce que la console serie affichera) :"
    $segs = [int]$b[$blOff + 1]
    $p = $blOff + 24
    for ($i = 0; $i -lt $segs; $i++) {
        $addr = [BitConverter]::ToUInt32($b, $p)
        $len = [BitConverter]::ToUInt32($b, $p + 4)
        Write-Host ("   load:0x{0:x8},len:{1}" -f $addr, $len)
        $p += 8 + $len
    }
    Write-Host ("   entry 0x{0:x8}" -f [BitConverter]::ToUInt32($b, $blOff + 4))
}

# ------------------------------------------------------------- table de partitions
if ($hasTable) {
    Write-Host "`nTABLE DE PARTITIONS :"
    $off = 0x8000
    $appPart = $null
    while (Test-PartitionTable $b $off) {
        $type = $b[$off + 2]; $sub = $b[$off + 3]
        $addr = [BitConverter]::ToUInt32($b, $off + 4)
        $size = [BitConverter]::ToUInt32($b, $off + 8)
        $label = (-join ($b[($off + 12)..($off + 27)] | Where-Object { $_ -ne 0 -and $_ -ne 0xFF } |
                    ForEach-Object { [char]$_ }))
        Write-Host ("   {0,-10} type={1} subtype=0x{2:x2} addr=0x{3:x6} taille={4,5} KiB" -f `
                $label, $type, $sub, $addr, [int]($size / 1024))
        if ($type -eq 0 -and $addr -eq 0x10000) { $appPart = $size }
        $off += 32
    }
}

# ------------------------------------------------------- validation de l'image applicative
Write-Host "`nIMAGE APPLICATIVE (offset 0x$('{0:X}' -f $appOff)) :"
if (-not (Test-ImageHeader $b $appOff)) {
    Write-Host "   pas d'image valide a cet offset" -ForegroundColor Red
    exit 1
}
$segs = [int]$b[$appOff + 1]
$hashAppended = $b[$appOff + 23]
Write-Host ("   segments={0} entry=0x{1:x8} chip_id={2} min_chip_rev={3} sha_ajoute={4}" -f `
        $segs, [BitConverter]::ToUInt32($b, $appOff + 4), [BitConverter]::ToUInt16($b, $appOff + 12), `
        $b[$appOff + 14], $hashAppended)

$ck = 0xEF
$p = $appOff + 24
$ok = $true
for ($i = 0; $i -lt $segs; $i++) {
    if ($p + 8 -gt $b.Length) { Write-Host "   seg$i : TRONQUE" -ForegroundColor Red; exit 1 }
    $len = [BitConverter]::ToUInt32($b, $p + 4)
    $p += 8
    if ($p + $len -gt $b.Length) { Write-Host "   seg$i : depasse la fin du fichier" -ForegroundColor Red; exit 1 }
    for ($j = $p; $j -lt $p + $len; $j++) { $ck = $ck -bxor $b[$j] }
    $p += $len
}
$pad = (16 - (($p - $appOff + 1) % 16)) % 16
$ckOff = $p + $pad
if ($ckOff -ge $b.Length) { Write-Host "   octet de checksum hors fichier" -ForegroundColor Red; exit 1 }
$ckOk = (($ck -band 0xFF) -eq $b[$ckOff])
Write-Host ("   checksum : calcule=0x{0:X2} lu=0x{1:X2} -> {2}" -f ($ck -band 0xFF), $b[$ckOff],
    $(if ($ckOk) { "OK" } else { "INVALIDE" })) -ForegroundColor $(if ($ckOk) { "Green" } else { "Red" })
if (-not $ckOk) { $ok = $false }

$imgEnd = $ckOff + 1
if ($hashAppended -eq 1) {
    if ($imgEnd + 32 -gt $b.Length) { Write-Host "   SHA-256 tronque" -ForegroundColor Red; exit 1 }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $got = $sha.ComputeHash($b, $appOff, $imgEnd - $appOff)
    $want = $b[$imgEnd..($imgEnd + 31)]
    $shaOk = -not (Compare-Object $got $want)
    Write-Host "   SHA-256 : $(if ($shaOk) { 'OK' } else { 'INVALIDE' })" `
        -ForegroundColor $(if ($shaOk) { "Green" } else { "Red" })
    if (-not $shaOk) { $ok = $false }
    $imgEnd += 32
}

$appLen = $imgEnd - $appOff
Write-Host "   taille de l'image : $appLen octets"
if ($appPart) {
    $pct = [math]::Round(100 * $appLen / $appPart, 1)
    Write-Host "   occupation de app0 : $pct % de $([int]($appPart/1024)) KiB"
    if ($appLen -gt $appPart) { Write-Host "   NE TIENT PAS DANS app0" -ForegroundColor Red; $ok = $false }
}
$trailing = $b.Length - $imgEnd
if ($trailing -gt 0) { Write-Host "   $trailing octets apres l'image" }

# Codes de sortie : 0 = publiable tel quel, 1 = corrompue, 2 = intacte mais a fusionner
Write-Host ""
if (-not $ok) {
    Write-Host "RESULTAT : image CORROMPUE, ne pas publier." -ForegroundColor Red
    exit 1
}
elseif ($isRaw) {
    Write-Host "RESULTAT : image applicative intacte, mais A FUSIONNER avant publication." -ForegroundColor Yellow
    exit 2
}
else {
    Write-Host "RESULTAT : image intacte et publiable telle quelle." -ForegroundColor Green
    exit 0
}
