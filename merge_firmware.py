Import("env")
import os
import subprocess

def merge_firmware(source, target, env):
    """Fusionne les fichiers firmware après le build"""
    
    build_dir = env.subst("$BUILD_DIR")
    project_dir = env.subst("$PROJECT_DIR")
    
    bootloader = os.path.join(build_dir, "bootloader.bin")
    partitions = os.path.join(build_dir, "partitions.bin")
    boot_app0 = os.path.join(project_dir, ".pio", "build", env["PIOENV"], "boot_app0.bin")
    firmware = os.path.join(build_dir, "firmware.bin")
    
    output = os.path.join(project_dir, "firmware_merged.bin")
    
    # Vérifier que tous les fichiers existent
    if not all(os.path.exists(f) for f in [bootloader, partitions, boot_app0, firmware]):
        print("Erreur: Fichiers source manquants")
        return
    
    # Fusionner avec esptool
    cmd = [
        "esptool.py",
        "--chip", "esp32",
        "merge_bin",
        "-o", output,
        "--flash_mode", "dio",
        "--flash_freq", "40m",
        "--flash_size", "4MB",
        "0x0", bootloader,
        "0x8000", partitions,
        "0xE000", boot_app0,
        "0x10000", firmware
    ]
    
    try:
        subprocess.run(cmd, check=True)
        print(f"\nFirmware fusionné créé: {output}")
    except subprocess.CalledProcessError:
        print("Erreur lors de la fusion du firmware")

# Ajouter l'action post-build
env.AddPostAction("$BUILD_DIR/${PROGNAME}.bin", merge_firmware)
