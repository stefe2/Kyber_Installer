# Kyber_Installer — guide du dépôt

Site statique d'installation de firmwares ESP32 par le navigateur (Web Serial), publié sur
GitHub Pages : <https://stefe2.github.io/Kyber_Installer/>

Aucun build, aucune dépendance à installer : le dépôt **est** le site. Tout ce qui est poussé
sur `main` est en ligne quelques minutes plus tard, y compris les `.bin`.

## Comment ça marche

Chaque page d'installation charge le composant `esp-web-tools` depuis unpkg :

```html
<script type="module" src="https://unpkg.com/esp-web-tools@latest/dist/web/install-button.js?module"></script>
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
| [Kyber_Echo/](Kyber_Echo/) | Installateur Kyber Echo (ESP32-S3) — dossier `BBBip/` jusqu'au 03/08/2026 |
| [tools/check-firmware.ps1](tools/check-firmware.ps1) | Analyse un `.bin` : fusionnée ou brute, paramètres flash, table de partitions, checksum + SHA-256, empreinte bootloader |
| [merge-firmware.ps1](merge-firmware.ps1) | Fusion manuelle d'un build PlatformIO (paramètre `-Chip`, vérifie le résultat) |
| [merge_firmware.py](merge_firmware.py) | Même fusion en post-build PlatformIO (voir [platformio-config-example.ini](platformio-config-example.ini)) |

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

**Le contrôle est outillé, ne le refais pas à la main :**

```powershell
.\tools\check-firmware.ps1 firmware\Kyber_V232.bin
```

Codes de sortie : `0` publiable telle quelle, `1` image corrompue, `2` intacte mais à fusionner.
L'outil affiche aussi les paramètres flash, la table de partitions, le taux d'occupation d'`app0`
et l'empreinte du bootloader. La signature qu'il interprète, si tu dois vérifier à la main :

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

Les images Kyber de production sont toutes en **dio / 4MB / 80m**. Ces paramètres ne sont que trois
octets de l'en-tête du bootloader, réécrits par les options `--flash_mode/--flash_freq/--flash_size`
de la fusion : s'en écarter change le comportement de la puce au démarrage.

> **Historique, si tu tombes sur un ancien script ailleurs.** Jusqu'au 29/07/2026, les trois aides à
> la fusion du dépôt plaçaient le bootloader à `0x0` (correct pour un S3/C3, **faux pour l'ESP32
> classique**) et annonçaient `--flash_freq 40m` au lieu de `80m`. Elles ont été corrigées, et
> `FUSION-FIRMWARE-COMMANDE.txt` supprimé au profit de
> [docs/AJOUTER-UNE-VERSION.md](docs/AJOUTER-UNE-VERSION.md), pour ne garder qu'une source de
> vérité. Les images V1.2.7 et V2.0.0 en production n'avaient donc pas été fabriquées avec ces
> scripts.

## Inventaire

Kyber Controller — versions proposées dans le sélecteur de [index.html](index.html) :

| Version affichée | Manifeste | Binaire | État |
| --- | --- | --- | --- |
| V2.3.2 | `Manifest/Kyber_V232-manifest.json` | `firmware/Kyber_V232.bin` | fusionnée, en ligne, **flash validé** (défaut) |
| V1.2.7 | `Manifest/Kyber_V127-manifest.json` | `firmware/Kyber_V127.bin` | fusionnée, en ligne, flash validé |

La V2.0.0 a été dépubliée le 29/07/2026, la V2.3.2 la remplaçant : `<option>` retiré du sélecteur
et `Manifest/Kyber_V200-manifest.json` supprimé. **`firmware/Kyber_V200.bin` est en revanche
conservé** — c'est la source de l'en-tête de la V2.3.2 (voir plus bas) et le chemin de retour
arrière. Pour la remettre en ligne, il faut donc recréer son manifeste (12 lignes, calquer sur celui
de la V2.3.2 en pointant `../firmware/Kyber_V200.bin`) puis rajouter son `<option>`.

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

`firmware/` contient les deux binaires publiés (`Kyber_V232.bin`, `Kyber_V127.bin`) plus
`Kyber_V200.bin`, gardé sans manifeste comme retour arrière : **c'est le seul `.bin` du dossier qui
n'est volontairement pas publié, ne pas le supprimer lors d'un nettoyage.** Les anciens `.bin` non
référencés ont été supprimés le 29/07/2026 — ils restent récupérables dans l'historique git.

Autres installateurs :

| Dossier | Nom du manifeste | Puce | Binaire | Particularité |
| --- | --- | --- | --- | --- |
| Astropixels | Astropixels Controller 0.0.1 | ESP32 | `Firmware/Astropixels.bin` | seule page avec un lien vers une doc des commandes |
| 1PIPBOY | PipBoy_Edition | ESP32 | `PIPV2CYD.bin` | |
| B2EMO | Kyber_B2EMO_Edition | ESP32 | `Kyber_V03.bin` | |
| Huyang | Huyang Eyes | ESP32 | `Huyang.bin` | |
| Kyber_Echo | Echo | **ESP32-S3** | 4 parties dans `firmware/` | seul installateur à ne pas utiliser d'image fusionnée |

Toutes ces images sont correctement fusionnées (vérifié avec
[tools/check-firmware.ps1](tools/check-firmware.ps1)), sauf Kyber_Echo qui flashe volontairement les
4 parties séparément. Chacun de ces dossiers ne garde plus qu'un seul exemplaire de son binaire, à
sa racine, là où le manifeste le cherche.

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

1. 1PIPBOY, B2EMO et Huyang sont trois copies de 252 lignes d'une ancienne version de l'index
   racine : toute retouche de style doit être répétée manuellement. Le refactor vers un CSS partagé
   coûte probablement plus cher que la duplication, sauf si ces pages redeviennent actives.
2. Aucune page d'accueil ne liste les installateurs secondaires : Astropixels, Kyber_Echo, Huyang, B2EMO
   et 1PIPBOY ne sont accessibles que par URL directe.
3. [README.md](README.md) racine fait trois lignes, et les READMEs de 1PIPBOY, B2EMO et Huyang n'en
   sont que des copies mot pour mot.
4. `Manifest/bootloader.bin`, `partitions.bin` et `firmware.bin` : orphelins depuis la suppression
   de l'entrée VTEST, mais gardés sciemment (voir l'inventaire). Le `firmware.bin` ne pèse que
   262 KiB — ce n'est pas un build Kyber ; sa table de partitions est en revanche identique à
   celle de la V2.0.0.

5. `esp-web-tools@latest` sur les 6 pages : elles suivent automatiquement les ruptures amont, y
   compris une future v11. C'est un choix assumé de Stéphane (03/08/2026), pas un oubli — ne pas
   « corriger » en réépinglant. La contrepartie est qu'une page cassée ne se verra qu'à l'usage :
   si un utilisateur signale un flash qui échoue sans qu'on ait touché au dépôt, vérifier d'abord
   la version publiée (`curl -s https://registry.npmjs.org/esp-web-tools | ...`, dist-tags) et les
   notes de version.

Corrigé le 29/07/2026 : binaires dupliqués et non référencés supprimés (~12 Mo), `index copy.html`
supprimé, scripts de fusion corrigés et outillés.

Le 03/08/2026, les 6 pages sont passées de `esp-web-tools@9` (9.4.3) à `@latest` (10.4.0 à cette
date), annulant l'épinglage du 29/07/2026. La v10 ne change ni le format des manifestes ni la
balise `<esp-web-install-button>` — la seule rupture est visuelle (bouton et dialogue en Material
3) ; les 10.1→10.4 apportent la couche de transport esptool réécrite, le reset natif et le support
ESP32-C5.
