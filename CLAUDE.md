# Kyber_Installer — guide du dépôt

Site statique d'installation de firmwares ESP32 par le navigateur (Web Serial), publié sur
GitHub Pages : <https://stefe2.github.io/Kyber_Installer/>

Aucun build, aucune dépendance à installer : le dépôt **est** le site. Tout ce qui est poussé
sur `main` est en ligne quelques minutes plus tard, y compris les `.bin`.

## Comment ça marche

Chaque page d'installation charge le composant `esp-web-tools` depuis unpkg :

```html
<script type="module" src="https://unpkg.com/esp-web-tools@9/dist/web/install-button.js?module"></script>
...
<esp-web-install-button manifest="manifest.json">
```

Le composant lit le manifeste JSON, choisit le `build` dont le `chipFamily` correspond à la puce
détectée, puis flashe chaque `part` à son `offset`. Les chemins des `parts` sont **relatifs au
manifeste**, pas à la page HTML.

Contraintes à ne pas oublier :

- **HTTPS ou `localhost` obligatoire** (Web Serial). Ouvrir un `index.html` en `file://` ne
  fonctionne pas. Pour tester en local : `python -m http.server 8000` puis
  <http://localhost:8000>.
- Navigateurs Chromium uniquement (Chrome, Edge). Pas de Firefox, pas de Safari, pas de mobile.
- Chemins **relatifs** partout : le site est servi sous le sous-chemin `/Kyber_Installer/`, une
  URL absolue commençant par `/` casserait tout.

## Carte du dépôt

| Chemin | Rôle |
| --- | --- |
| [index.html](index.html) | Installateur principal Kyber Controller, avec sélecteur de version |
| [Manifest/](Manifest/) | Manifestes du Kyber Controller (`Kyber_Vxxx-manifest.json`) |
| [firmware/](firmware/) | Binaires du Kyber Controller (`Kyber_Vxxx.bin`) |
| [images/](images/) | Logo, favicon (`Krystal.png` sert de favicon) |
| [Astropixels/](Astropixels/) | Installateur Astropixels + [documentation des commandes](Astropixels/command_en.html) |
| [1PIPBOY/](1PIPBOY/) | Installateur Pip-Boy Edition |
| [B2EMO/](B2EMO/) | Installateur B2EMO Edition |
| [Huyang/](Huyang/) | Installateur Huyang Eyes |
| [BBBip/](BBBip/) | Installateur BB-8 SoundBoard (ESP32-S3) |
| [merge-firmware.ps1](merge-firmware.ps1), [merge_firmware.py](merge_firmware.py), [FUSION-FIRMWARE-COMMANDE.txt](FUSION-FIRMWARE-COMMANDE.txt) | Aides à la fusion des binaires PlatformIO — **voir l'avertissement plus bas** |

Chaque sous-dossier est un installateur autonome (son `index.html`, son `manifest.json`, ses
`.bin`). Ils ne sont **pas** liés depuis la page d'accueil : on y accède par URL directe, par
exemple <https://stefe2.github.io/Kyber_Installer/Astropixels/>.

Le logo et le badge Creative Commons sont embarqués en base64 dans les pages, d'où des lignes
HTML très longues. Ce sont des données, pas du code : ne pas chercher à les relire ni à les
reformater.

## Règle centrale : image fusionnée vs `firmware.bin` brut

Un manifeste avec `"offset": 0` exige une **image flash complète et fusionnée**, pas le
`firmware.bin` sorti de PlatformIO. Les deux fichiers se ressemblent (même extension, taille du
même ordre) et l'erreur ne se voit qu'au flash : la carte reboote en boucle.

Vérification en 3 octets, sous PowerShell :

```powershell
$b = [System.IO.File]::ReadAllBytes("firmware\Kyber_V232.bin")
'0x0000 : {0:X2} {1:X2}' -f $b[0], $b[1]
'0x0020 : {0:X2} {1:X2} {2:X2} {3:X2}' -f $b[32], $b[33], $b[34], $b[35]
'0x1000 : {0:X2} {1:X2}' -f $b[4096], $b[4097]
'0x8000 : {0:X2} {1:X2}' -f $b[32768], $b[32769]
```

| Signature | Diagnostic |
| --- | --- |
| `0x0000 = FF FF`, `0x1000 = E9 ..`, `0x8000 = AA 50` | Image fusionnée ESP32 — utilisable avec `offset: 0` |
| `0x0000 = E9 ..` **et** `0x0020 = 32 54 CD AB` | `firmware.bin` brut (magie `esp_app_desc`) — **inutilisable** avec `offset: 0`, il faut le fusionner |

`AA 50` à 0x8000 est la magie de la table de partitions ; `E9` est l'en-tête d'une image ESP.
Sur ESP32-S3/C3 le bootloader est à 0x0, donc `0x0000 = E9 ..` y est normal : la distinction se
fait alors sur la présence de `AA 50` à 0x8000.

### Offsets de fusion selon la puce

| Partie | ESP32 | ESP32-S3 / C3 |
| --- | --- | --- |
| `bootloader.bin` | **0x1000** | 0x0 |
| `partitions.bin` | 0x8000 | 0x8000 |
| `boot_app0.bin` | 0xE000 | 0xE000 |
| `firmware.bin` | 0x10000 | 0x10000 |

> **Avertissement sur les scripts de fusion du dépôt.** [merge-firmware.ps1](merge-firmware.ps1),
> [merge_firmware.py](merge_firmware.py) et [FUSION-FIRMWARE-COMMANDE.txt](FUSION-FIRMWARE-COMMANDE.txt)
> placent tous les trois le bootloader à `0x0` avec `--chip esp32`. C'est correct pour un S3/C3
> mais **faux pour l'ESP32 classique**, et produit une image qui ne démarre pas. Les images
> V1.2.7 et V2.0.0 en production ont leur bootloader à 0x1000 : elles n'ont donc pas été faites
> avec ces scripts. Ne pas s'y fier tel quel — corriger l'offset ou utiliser la commande de
> [docs/AJOUTER-UNE-VERSION.md](docs/AJOUTER-UNE-VERSION.md).

## Inventaire

Kyber Controller — versions proposées dans le sélecteur de [index.html](index.html) :

| Version affichée | Manifeste | Binaire | État |
| --- | --- | --- | --- |
| V2.3.2 | `Manifest/Kyber_V232-manifest.json` | `firmware/Kyber_V232.bin` | fusionnée, en ligne, **flash validé** (défaut) |
| V1.2.7 | `Manifest/Kyber_V127-manifest.json` | `firmware/Kyber_V127.bin` | fusionnée, en ligne, flash validé |

La V2.0.0 a été retirée du sélecteur le 29/07/2026, la V2.3.2 la remplaçant. **Son manifeste et son
binaire sont conservés** : `firmware/Kyber_V200.bin` est la source de l'en-tête de la V2.3.2 (voir
plus bas) et le chemin de retour arrière si un souci apparaît. Pour la remettre en ligne, il suffit
de rajouter son `<option>` — le manifeste est toujours là.

L'entrée VTEST et son manifeste ont été supprimés le 29/07/2026. Les binaires
`Manifest/bootloader.bin`, `partitions.bin` et `firmware.bin` qu'elle utilisait sont désormais
orphelins (~290 Ko) mais **conservés volontairement** (décision du 29/07/2026) : ne pas les
supprimer au passage lors d'un nettoyage.

La V2.3.2 a été fabriquée en reprenant les 65 536 premiers octets de `Kyber_V200.bin` (padding,
bootloader à 0x1000, table de partitions à 0x8000, otadata à 0xE000) suivis de l'application
`firmware.bin` de la 2.3.2 à 0x10000 — les deux builds partagent le même socle Arduino/IDF 4.4.7.
Elle hérite donc du schéma de partitions de la V2.0.0 (`app0`/`app1` de 1920 KiB, `spiffs` de
128 KiB à 0x3D0000). L'application brute d'origine est sauvegardée hors dépôt dans le scratchpad
de la session.

Fichiers présents mais non publiés :

- `firmware/Kyber_V125.bin` — `firmware.bin` brut, référencé par aucun manifeste.

Autres installateurs :

| Dossier | Nom du manifeste | Puce | Binaire | Particularité |
| --- | --- | --- | --- | --- |
| Astropixels | Astropixels Controller 0.0.1 | ESP32 | `Firmware/Astropixels.bin` | seule page avec un lien vers une doc des commandes |
| 1PIPBOY | PipBoy_Edition | ESP32 | `PIPV2CYD.bin` | `PIPV2.bin` et `PIPV21.bin` présents mais non utilisés |
| B2EMO | Kyber_B2EMO_Edition | ESP32 | `Kyber_V03.bin` | |
| Huyang | Huyang Eyes | ESP32 | `Huyang.bin` | |
| BBBip | BB-8 SoundBoard | **ESP32-S3** | 4 parties dans `firmware/` | seul installateur à ne pas utiliser d'image fusionnée |

Toutes ces images sont correctement fusionnées (vérifié : `AA 50` à 0x8000), sauf BBBip qui flashe
volontairement les 4 parties séparément.

## Conventions

- Binaires Kyber : `firmware/Kyber_V<majeur><mineur><patch>.bin` — `Kyber_V232.bin` pour 2.3.2.
- Manifestes Kyber : `Manifest/Kyber_V<xxx>-manifest.json`, avec `name` lisible
  (« Kyber Controller V2.0.0 ») et `version` en semver.
- `new_install_prompt_erase: true` et `new_install_improv_wait_time: 0` partout : on garde.
- Une nouvelle version se déclare dans **trois** endroits : le `.bin`, le manifeste, et l'`<option>`
  du sélecteur. Le détail est dans [docs/AJOUTER-UNE-VERSION.md](docs/AJOUTER-UNE-VERSION.md).
- Documentation et commentaires en français ; l'interface des pages est en anglais.

## Dettes connues

Recensées, non corrigées à ce jour — à traiter avec l'accord de Stéphane, pas au passage :

1. Binaires dupliqués : `B2EMO/Kyber_V03.bin` **et** `B2EMO/firmware/Kyber_V03.bin`,
   `Huyang/Huyang.bin` **et** `Huyang/firmware/Huyang.bin`, idem `1PIPBOY/PIPV2.bin`. Les
   manifestes pointent vers la copie à la racine du dossier ; celles dans `firmware/` sont mortes.
2. `1PIPBOY/index copy.html` — résidu à supprimer.
3. 1PIPBOY, B2EMO et Huyang sont trois copies de 252 lignes d'une ancienne version de l'index
   racine : toute retouche de style doit être répétée manuellement.
4. `Manifest/bootloader.bin`, `partitions.bin` et `firmware.bin` : orphelins depuis la suppression
   de l'entrée VTEST, mais gardés sciemment (voir l'inventaire). Le `firmware.bin` ne pèse que
   262 KiB — ce n'est pas un build Kyber ; sa table de partitions est en revanche identique à
   celle de la V2.0.0.
5. `esp-web-tools@9` est épinglé partout sauf dans [BBBip/index.html](BBBip/index.html) qui utilise
   `@latest` — divergence involontaire.
6. Aucune page d'accueil ne liste les installateurs secondaires.
