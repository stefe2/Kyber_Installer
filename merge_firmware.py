"""Script post-build PlatformIO : fusionne les 4 fichiers du build en une image flash unique.

A activer dans platformio.ini (voir platformio-config-example.ini) :

    extra_scripts = post:merge_firmware.py

Le fichier produit, firmware_merged.bin a la racine du projet, est directement publiable dans
un manifeste avec "offset": 0. Procedure complete : docs/AJOUTER-UNE-VERSION.md
"""

Import("env")  # noqa: F821 - fourni par PlatformIO
import os
import subprocess

# L'ESP32 et l'ESP32-S2 attendent le bootloader a 0x1000 ; les puces plus recentes a 0x0.
# Se tromper produit une image qui ne demarre pas, sans aucun message d'erreur.
BOOTLOADER_OFFSET_1000 = ("esp32", "esp32s2")

# Les images Kyber de production sont en dio / 4MB / 80m.
DEFAULT_FLASH_MODE = "dio"
DEFAULT_FLASH_FREQ = "80m"
DEFAULT_FLASH_SIZE = "4MB"


def find_boot_app0(env, build_dir):
    """boot_app0.bin ne sort pas du build : il vient du framework Arduino."""
    candidate = os.path.join(build_dir, "boot_app0.bin")
    if os.path.exists(candidate):
        return candidate
    try:
        framework = env.PioPlatform().get_package_dir("framework-arduinoespressif32")
    except Exception:
        return candidate
    if framework:
        candidate = os.path.join(framework, "tools", "partitions", "boot_app0.bin")
    return candidate


def merge_firmware(source, target, env):
    build_dir = env.subst("$BUILD_DIR")
    project_dir = env.subst("$PROJECT_DIR")
    board = env.BoardConfig()

    mcu = board.get("build.mcu", "esp32")
    bootloader_offset = "0x1000" if mcu in BOOTLOADER_OFFSET_1000 else "0x0"
    flash_mode = board.get("build.flash_mode", DEFAULT_FLASH_MODE)
    flash_freq = board.get("build.f_flash", DEFAULT_FLASH_FREQ).replace("000000L", "m")
    flash_size = board.get("upload.flash_size", DEFAULT_FLASH_SIZE)

    parts = {
        bootloader_offset: os.path.join(build_dir, "bootloader.bin"),
        "0x8000": os.path.join(build_dir, "partitions.bin"),
        "0xE000": find_boot_app0(env, build_dir),
        "0x10000": os.path.join(build_dir, "firmware.bin"),
    }

    missing = [p for p in parts.values() if not os.path.exists(p)]
    if missing:
        print("Erreur: fichiers source manquants :")
        for p in missing:
            print("  -", p)
        return

    output = os.path.join(project_dir, "firmware_merged.bin")

    # esptool est fourni par PlatformIO ; on l'appelle avec le meme interpreteur.
    python_exe = env.subst("$PYTHONEXE") or "python"
    try:
        esptool_py = os.path.join(env.PioPlatform().get_package_dir("tool-esptoolpy"), "esptool.py")
    except Exception:
        esptool_py = None
    base = [python_exe, esptool_py] if esptool_py and os.path.exists(esptool_py) else ["esptool.py"]

    print(f"\nFusion pour {mcu} ({flash_mode} / {flash_size} / {flash_freq}) :")
    for offset, path in parts.items():
        print(f"  - {os.path.basename(path):16s} @ {offset}")

    # esptool 5 a renomme la commande et les options ; on tente la syntaxe historique puis
    # la nouvelle, ce qui evite d'avoir a detecter la version.
    variants = [
        ("merge_bin", "--flash_mode", "--flash_freq", "--flash_size"),
        ("merge-bin", "--flash-mode", "--flash-freq", "--flash-size"),
    ]
    for cmd_name, opt_mode, opt_freq, opt_size in variants:
        cmd = base + [
            "--chip", mcu, cmd_name,
            "-o", output,
            opt_mode, flash_mode,
            opt_freq, flash_freq,
            opt_size, flash_size,
        ]
        for offset, path in parts.items():
            cmd += [offset, path]
        try:
            subprocess.run(cmd, check=True)
            size = os.path.getsize(output)
            print(f"\nFirmware fusionne cree : {output} ({size / 1024:.1f} KiB)")
            print("Verifiez-le avec tools/check-firmware.ps1 avant publication.")
            return
        except subprocess.CalledProcessError:
            continue
        except FileNotFoundError:
            print("Erreur: esptool introuvable.")
            return

    print("Erreur lors de la fusion du firmware (les deux syntaxes esptool ont echoue).")


env.AddPostAction("$BUILD_DIR/${PROGNAME}.bin", merge_firmware)  # noqa: F821
