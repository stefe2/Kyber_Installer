# Publier une nouvelle version du Kyber Controller

Procédure complète, de la sortie de PlatformIO jusqu'à la mise en ligne. Exemple fil rouge :
publier la **2.3.2**, donc `Kyber_V232.bin`.

Voir [CLAUDE.md](../CLAUDE.md) pour le fonctionnement général du dépôt.

---

## 1. Récupérer les 4 fichiers du build

Dans le projet PlatformIO, après compilation :

```text
.pio/build/<env>/bootloader.bin
.pio/build/<env>/partitions.bin
.pio/build/<env>/boot_app0.bin      (parfois dans ~/.platformio/packages/framework-arduinoespressif32/tools/partitions/)
.pio/build/<env>/firmware.bin
```

`firmware.bin` seul ne suffit pas. C'est l'erreur la plus fréquente : il démarre par `E9` comme
une image complète, mais il ne contient ni bootloader ni table de partitions.

## 2. Fusionner en une image flash unique

Sur **ESP32 classique**, le bootloader va à **0x1000** (et non 0x0 comme l'écrivent les scripts
livrés dans le dépôt — voir l'avertissement dans [CLAUDE.md](../CLAUDE.md)) :

```powershell
esptool.py --chip esp32 merge_bin -o Kyber_V232.bin `
  --flash_mode dio --flash_freq 40m --flash_size 4MB `
  0x1000 bootloader.bin `
  0x8000 partitions.bin `
  0xE000 boot_app0.bin `
  0x10000 firmware.bin
```

À partir d'esptool 5, la commande et les options sont en tirets : `esptool merge-bin`,
`--flash-mode`, `--flash-freq`, `--flash-size`. Vérifier avec `esptool.py version` en cas de
message d'option inconnue.

Sur **ESP32-S3 / C3**, remplacer `--chip esp32` par la bonne puce et mettre le bootloader à `0x0`.

Puis copier le résultat :

```powershell
Copy-Item Kyber_V232.bin "C:\Users\stefe\Documents\GitHub\Kyber_Installer\firmware\Kyber_V232.bin"
```

## 3. Vérifier l'image avant d'aller plus loin

Trente secondes ici évitent un firmware mort en production :

```powershell
$b = [System.IO.File]::ReadAllBytes("firmware\Kyber_V232.bin")
'0x0000 : {0:X2} {1:X2}' -f $b[0], $b[1]
'0x1000 : {0:X2} {1:X2}' -f $b[4096], $b[4097]
'0x8000 : {0:X2} {1:X2}' -f $b[32768], $b[32769]
```

Attendu pour une image ESP32 fusionnée :

```text
0x0000 : FF FF      <- zone vide avant le bootloader
0x1000 : E9 xx      <- en-tête du bootloader
0x8000 : AA 50      <- magie de la table de partitions
```

Si `0x0000` vaut `E9 ..` et que `0x8000` ne vaut pas `AA 50`, c'est un `firmware.bin` brut :
retourner à l'étape 2. La taille doit aussi être cohérente avec les versions précédentes
(1,3 à 1,6 Mo pour le Kyber Controller).

## 4. Créer le manifeste

`Manifest/Kyber_V232-manifest.json`, calqué sur
[Kyber_V200-manifest.json](../Manifest/Kyber_V200-manifest.json) :

```json
{
    "name": "Kyber Controller V2.3.2",
    "version": "2.3.2",
    "new_install_prompt_erase": true,
    "new_install_improv_wait_time": 0,
    "builds": [
      {
        "chipFamily": "ESP32",
        "parts": [
          { "path": "../firmware/Kyber_V232.bin", "offset": 0 }
        ]
      }
    ]
}
```

Le `path` est relatif **au manifeste**, d'où le `../firmware/`. `chipFamily` doit correspondre
exactement à la puce (`ESP32`, `ESP32-S2`, `ESP32-S3`, `ESP32-C3`) : si elle ne correspond pas,
esp-web-tools refuse l'installation sans expliquer pourquoi.

## 5. Déclarer la version dans le sélecteur

Dans [index.html](../index.html), ajouter une `<option>` au `<select id="versionSelector">` :

```html
<option value="Manifest/Kyber_V232-manifest.json">V2.3.2</option>
```

Le `value` est le chemin du manifeste, relatif à la page. Le script en bas de page recopie ce
`value` dans l'attribut `manifest` du bouton à chaque changement — rien d'autre à modifier.

**Version proposée par défaut** : c'est celle du premier `<option>`, qui doit correspondre à
l'attribut `manifest="..."` en dur sur `<esp-web-install-button>`. Pour faire de la 2.3.2 le
défaut, placer son `<option>` en premier **et** mettre à jour l'attribut du bouton. Oublier l'un
des deux fait afficher une version alors qu'une autre est flashée.

## 6. Tester en local

Web Serial exige HTTPS ou `localhost` :

```powershell
python -m http.server 8000
```

Puis <http://localhost:8000> dans Chrome ou Edge : sélectionner la nouvelle version, brancher une
carte, flasher, et vérifier que la carte démarre vraiment (console série) — un flash « réussi » ne
garantit pas un firmware bootable.

## 7. Publier

```powershell
git add firmware/Kyber_V232.bin Manifest/Kyber_V232-manifest.json index.html
git commit -m "feat: Kyber Controller V2.3.2"
git push
```

GitHub Pages redéploie automatiquement depuis `main` en quelques minutes. Revérifier ensuite sur
<https://stefe2.github.io/Kyber_Installer/>, en rechargeant sans cache (Ctrl+F5) : les `.bin` et
les manifestes sont mis en cache agressivement par le navigateur.

---

## Diagnostic : la carte reboote en boucle après le flash

Symptôme, sur la console série à 115200 :

```text
rst:0x3 (SW_RESET),boot:0x13 (SPI_FAST_FLASH_BOOT)
...
load:0x3fff0030,len:1344
load:0x40078000,len:13964
load:0x40080400,len:3600
entry 0x400805f0
          <- rien, puis ça recommence
```

La ROM charge bien le second bootloader, puis celui-ci refuse l'application et se relance. Comme
le bootloader Arduino est compilé sans verbosité, **l'échec est totalement silencieux** : aucun
message n'explique la cause.

**Premier réflexe : reflasher.** Un flash incomplet donne exactement ce symptôme, et c'est de loin
la cause la plus fréquente. C'est ce qui est arrivé lors de la publication de la 2.3.2 : le même
binaire, reflashé, a démarré sans rien changer d'autre.

Si le problème persiste après plusieurs essais, la panne est dans l'image, et le diagnostic se fait
sur le fichier, sans matériel :

1. **Valider l'image applicative** — parcourir les segments depuis l'offset 0x10000, vérifier
   l'octet de checksum (XOR de toutes les données de segments, initialisé à 0xEF) et le SHA-256 de
   32 octets ajouté en fin d'image. Une image qui passe ces deux contrôles n'est pas corrompue.
2. **Identifier le bootloader réellement présent** — les trois longueurs `load:...,len:` du log
   série sont celles des segments du second bootloader. Les comparer à celles du bootloader de
   l'image dit sans ambiguïté quelle version tourne sur la puce. Repères connus :
   la V2.0.0 et la V2.3.2 donnent `1344 / 13964 / 3600` et `entry 0x400805f0` ; la V1.2.7 (IDF 5.4.1)
   donne `4888 / 16516 / 4 / 3476` et `entry 0x400805b4`.
3. **Comparer les en-têtes étendus** avec une version qui fonctionne — surtout `chip_id` (0 pour
   ESP32) et `min_chip_rev` : une application compilée pour la révision 3 boucle silencieusement sur
   une puce plus ancienne.
4. **Vérifier que le fichier publié est bien celui attendu** — comparer le SHA-256 du `.bin` servi
   par GitHub Pages à celui du dépôt, pour écarter un problème de cache ou de transfert.

---

## Récapitulatif

| # | Action | Fichier |
| --- | --- | --- |
| 1-2 | Fusionner les 4 parties | → `firmware/Kyber_V232.bin` |
| 3 | Vérifier les octets 0x0000 / 0x1000 / 0x8000 | — |
| 4 | Créer le manifeste | `Manifest/Kyber_V232-manifest.json` |
| 5 | Ajouter l'`<option>` (+ l'attribut `manifest` si défaut) | `index.html` |
| 6 | Tester sur `localhost` avec une vraie carte | — |
| 7 | Commit + push | — |

## Cas particulier : nouvel installateur pour un autre projet

Créer un dossier à la racine avec son propre `index.html` (partir de
[Astropixels/index.html](../Astropixels/index.html), la version la plus propre), son
`manifest.json` et son binaire. Le manifeste reste local au dossier et n'a pas besoin de `../`.
Penser à ajouter le lien depuis la page d'accueil — aujourd'hui aucun des installateurs
secondaires n'est référencé.
