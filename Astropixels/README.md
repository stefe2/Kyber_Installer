# Astropixels Controller Installer

## Installation des fichiers firmware

Pour que l'installateur fonctionne, vous devez ajouter les 4 fichiers firmware PlatformIO dans le dossier `Firmware/`:

### Fichiers requis:

1. **bootloader.bin** - Bootloader ESP32
2. **partitions.bin** - Table de partitions
3. **boot_app0.bin** - Application de boot
4. **firmware.bin** - Firmware principal Astropixels

### Où trouver ces fichiers?

Dans votre projet PlatformIO, après compilation:
```
.pio/build/esp32/bootloader.bin
.pio/build/esp32/partitions.bin
.pio/build/esp32/boot_app0.bin
.pio/build/esp32/firmware.bin
```

### Installation:

Copiez ces 4 fichiers dans:
```
Kyber_Installer/Astropixels/Firmware/
```

### Utilisation:

Ouvrez `index.html` dans un navigateur (depuis https:// ou localhost) et suivez les instructions.

## Version

- Version actuelle: **0.0.1**
- Puce: **ESP32**
- Nom: **Astropixels Controller**
