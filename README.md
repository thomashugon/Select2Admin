# Select2Admin pour macOS

Portage macOS de **Select2Search** (version Windows, AutoIt) : surlignez l'identifiant d'une armoire Zeendoc n'importe où (mail, ticket, tableur, page web…), **appuyez deux fois sur ⌘ Commande droite**, et la page d'administration de l'armoire s'ouvre dans le navigateur.

## Fonctionnement

| | Windows | macOS |
|---|---|---|
| Déclenchement | double appui sur **Ctrl droite** seule | double appui sur **⌘ droite** seule (modifiable : ⌥ / ⌃ / ⇧ droite) |
| Lecture de la sélection | Ctrl+C simulé, presse-papiers restauré | ⌘C simulé, presse-papiers restauré (repli : API d'accessibilité) |
| Nettoyage | espaces de début/fin et multiples supprimés | idem, retours à la ligne compris, puis encodage URL |
| Plusieurs classeurs | fenêtre de liste | menu sous le pointeur (touches 1 à 9) |
| Présence | icône dans la zone de notification | icône dans la barre des menus |

La touche est considérée « seule » : un raccourci du type ⌘C ou ⌘⇧… n'est jamais pris pour un déclenchement. Les deux appuis doivent se suivre en moins de 0,45 s.

Le menu de la barre des menus permet aussi d'**ouvrir une armoire en tapant son identifiant**, de changer la touche, de modifier `config.ini` et d'ouvrir l'app à l'ouverture de session.

## config.ini

Même format que sous Windows ; le fichier Windows peut être réutilisé tel quel.

```ini
[Classeurs]
Admin armoire ="https://admin.zeendoc.com/Admin_Armoires/Armoire.php?Popup=ok&N_Client={Selected_Text}"

[delay]
delay="100"
```

Emplacement lu, dans l'ordre :
1. `config.ini` placé **à côté** de `Select2Admin.app` (comme sous Windows) ;
2. `~/Library/Application Support/Select2Admin/config.ini` (créé au premier lancement).

Le fichier est relu à chaque déclenchement : pas besoin de redémarrer l'app.

## Installation

1. Décompresser `Select2Admin-macOS.zip` et glisser `Select2Admin.app` dans **Applications**.
2. Premier lancement : l'app n'est pas notariée par Apple. Faire clic droit → **Ouvrir**, ou, si macOS refuse, **Réglages Système → Confidentialité et sécurité → Ouvrir quand même**.
   En ligne de commande : `xattr -dr com.apple.quarantine /Applications/Select2Admin.app`
3. Accorder l'accès **Accessibilité** quand macOS le demande (Réglages Système → Confidentialité et sécurité → Accessibilité → activer Select2Admin). Il est nécessaire pour détecter la touche et simuler ⌘C. L'icône ⚠︎ dans la barre des menus disparaît une fois l'accès accordé.
4. Optionnel : menu ▸ **Ouvrir à l'ouverture de session**.

> Après chaque recompilation, la signature change : il faut retirer puis réactiver Select2Admin dans la liste Accessibilité.

## Compiler

Prérequis : macOS 13+ et les outils en ligne de commande Xcode (`xcode-select --install`).

```sh
./build.sh
```

Produit `build/Select2Admin.app` (universel Apple Silicon + Intel) et `build/Select2Admin-macOS.zip`.

Le workflow GitHub Actions (`.github/workflows/build.yml`) compile à chaque push sur `main` et publie le zip dans la release correspondant à la version de `Resources/Info.plist` (`CFBundleShortVersionString`).
