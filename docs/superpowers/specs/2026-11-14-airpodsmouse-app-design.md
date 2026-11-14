# AirPodsMouse — une vraie appli pour tout le monde

*Design · 14 novembre 2026*

## Pourquoi

AirPodsMouse permet de piloter le curseur du Mac en bougeant la tête avec des AirPods. Le moteur
fonctionne bien (testé sur de vrais enregistrements : visée fluide, 5 clics sur 5 par hochement, zéro faux
clic). Mais l'appli reste un outil de bricoleur : petite fenêtre de boutons gris, icône cachée par l'encoche,
autorisations à faire à la main.

Le but : une appli **à donner à d'autres**, que n'importe qui peut installer et utiliser seul, y compris
des personnes peu à l'aise avec l'informatique ou qui ne peuvent pas se servir d'une souris.

## Objectifs

1. **Installation autonome** : télécharger un `.dmg`, glisser dans Applications, ouvrir. Personne n'a besoin d'aide.
2. **Accueil guidé au premier lancement** qui mène jusqu'au premier clic réussi.
3. **Plusieurs façons de cliquer**, dont une qui ne demande aucun geste rapide.
4. **Belle et native** : ressemble à une appli Apple, mode clair/sombre, français et anglais.
5. **Garder le ressenti actuel** du pointage, qui « marche hyper bien ».

## Non-objectifs (v1)

- Mac App Store (impossible : Apple interdit aux applis du Store de déplacer la souris d'autres applis).
- Signature/notarisation Apple (compte développeur payant) — prévu pour plus tard, l'appli doit être prête à l'accueillir sans refonte.
- Mises à jour automatiques (un lien « Vérifier les mises à jour » vers la page GitHub suffit).
- Glisser-déposer, défilement à la tête, multi-utilisateurs.
- Version Intel optimisée : l'appli sera « universelle », mais testée seulement sur ce Mac (Apple Silicon).

## Anti-objectifs (échec même si « ça marche »)

- Des clics qui partent tout seuls.
- Une étape qu'une personne non technique ne peut pas franchir seule.
- Un pointage moins bon qu'aujourd'hui.

## Contraintes

- macOS 14+ ; AirPods avec capteurs (Pro 1/2/3, 3, 4, Max).
- Ce Mac n'a que les outils en ligne de commande (pas Xcode) → projet Swift Package + script qui assemble l'appli.
- Sans compte Apple, macOS bloque la première ouverture d'un `.dmg` téléchargé (« Ouvrir quand même »
  dans Réglages › Confidentialité et sécurité). Le `.dmg` et la page GitHub l'expliquent avec captures.
- Toutes les versions sont signées avec le certificat local « AirPodsMouse Dev » : l'autorisation
  Accessibilité reste valable d'une mise à jour à l'autre chez chaque utilisateur.
- **Bloquant avant publication** : le code d'origine appartient à Harlo9 et n'a pas de licence. Rien n'est
  publié sur GitHub tant que ce n'est pas réglé (c'est toi, ou il donne son accord / ajoute une licence).

## Approches envisagées

| | Approche | Pour | Contre |
|---|---|---|---|
| **A ✅ choisie** | **Refaire toute l'interface en SwiftUI**, garder le moteur `Pointer.swift` tel quel | Rendu natif moderne (matériaux, animations, mode sombre) avec peu de code ; le moteur testé ne bouge pas | Réécriture de l'interface (la logique capteurs/permissions est reprise) |
| B | Embellir l'interface AppKit actuelle | Moins de changements | Beaucoup de code pour un résultat moins beau ; l'accueil animé serait laborieux |
| C | Projet Xcode | Outils graphiques d'Apple | Installer Xcode (~15 Go) sans bénéfice pour ce projet |

Installation : choisie par toi — **`.dmg`** (la commande Terminal reste possible plus tard).

## Ce que voit l'utilisateur

### 1. Le `.dmg`
Fenêtre avec fond illustré : icône AirPodsMouse → flèche → dossier Applications, et un fichier
« Si macOS bloque l'ouverture » (2 captures).

### 2. Accueil (premier lancement) — une fenêtre, 6 étapes avec points de progression
```
┌──────────────────────────────────────────┐
│              [icône animée]               │
│   Pilote ton Mac avec ta tête             │
│   Tes AirPods deviennent une souris.      │
│                                           │
│              [ Commencer ]                │
│                ●○○○○○                     │
└──────────────────────────────────────────┘
```
1. **Bienvenue** — ce que fait l'appli.
2. **Tes AirPods** — mets-les dans tes oreilles ; détection en direct (« ✅ AirPods Pro détectés, ils bougent ! » avec un petit indicateur qui suit la tête). Explique si modèle incompatible.
3. **Mouvements** — bouton « Autoriser » (déclenche la demande macOS) ; passe tout seul à la suite.
4. **Accessibilité** — explication en une phrase + bouton « Ouvrir le réglage » + mini-animation montrant l'interrupteur à activer ; détecte l'accord en direct et passe à la suite.
5. **Comment cliquer ?** — deux grandes cartes au choix (modifiable plus tard) :
   - *Hochement de tête* (petit « oui » rapide) — par défaut ;
   - *Clic automatique* (rester immobile ~1 s sur une cible) — pour qui ne peut pas faire de geste rapide.
6. **Essai** — 3 grosses cibles à viser et cliquer ; chaque réussite s'illumine ; « C'est parti ! » à la fin.

### 3. Barre des menus
Icône compacte (symbole AirPods ; triangle si problème ; pause). Menu : état en une ligne, Pause,
Clic automatique on/off, Réglages…, Quitter. Si l'icône est cachée par l'encoche : rouvrir l'appli
(double-clic) ouvre les Réglages.

### 4. Réglages — fenêtre style Réglages Système, barre latérale
- **Général** : état (AirPods, autorisations, avec boutons de correction), Ouvrir au démarrage du Mac, Pause, raccourcis.
- **Pointeur** : vitesse (curseur), vitesse verticale, inverser axes, recalibrer / réinitialiser.
- **Clic** : hochement on/off + sensibilité (prudent ↔ facile) ; clic automatique on/off + délai (0,6–2 s) ; clic droit par inclinaison on/off.
- **Essai** : la page de cibles de l'accueil, pour s'entraîner.
- **À propos** : version, lien GitHub, vue 3D (diagnostic), journal.

### 5. Retour visuel autour du curseur
Petit anneau translucide qui suit le curseur :
- clic automatique : l'anneau se **remplit** pendant le délai, puis clic ;
- hochement : bref « pulse » au clic ;
- pause : rien.

## Comment c'est construit

- **Swift Package** (macOS 14), une cible exécutable. Fichiers :
  - `PointerEngine` (= `Pointer.swift` actuel, inchangé) + `tools/replay` conservé ;
  - `MotionService` (capteurs, santé, relance rare), `CursorController` (sortie 120 Hz, synchro trackpad, clics, double-clic),
    `DwellClicker` (clic automatique), `Permissions` (Mouvements / Accessibilité, vérification en direct),
    `Settings` (préférences), `CursorOverlay` (anneau), vues SwiftUI (Accueil, Réglages, Essai, MenuBar), `Viewer3D` (conservé).
- Textes en catalogue de traduction FR + EN, langue du Mac.
- Icône dessinée par code puis convertie en `.icns` (pas besoin d'outil graphique).
- `scripts/build-app.sh` : compile en universel (Apple Silicon + Intel), assemble l'appli, icône, signature « AirPodsMouse Dev ».
- `scripts/make-dmg.sh` : `.dmg` avec fond et raccourci Applications.
- Ouvrir au démarrage : service système d'Apple pour les applis (`SMAppService`).

### Clic automatique — règles
Clic quand le curseur reste dans un rayon de ~6 px pendant le délai choisi, **et** a bougé d'au moins
~40 px depuis le dernier clic automatique (pas de rafale si on laisse la tête immobile). Désactivé
pendant la pause et quand le vrai trackpad bouge.

## Décisions prises par Claude (à vérifier)
- **Nom et identifiant inchangés** (`AirPodsMouse`, `local.airpodsmouse`) : tes réglages, ton calibrage et
  l'autorisation Accessibilité déjà accordée sont conservés.
- **Raccourcis clavier conservés** (⌃⌥P pause, ⌃⌥C calibrer, ⌃⌥Q quitter) ; ⌃⌥V devient « Réglages ».
- **« Sensibilité du hochement »** = un curseur à 3 crans (prudent / normal / facile) qui ajuste seuil de
  vitesse et durée maximale du geste ; « normal » = réglage actuel validé sur enregistrements.
- **« Revoir l'accueil »** dans À propos.
- **Interface « Réglages Système »** plutôt qu'une fenêtre sur mesure : plus familière pour les non-initiés.

## Laissé au constructeur
Proportions, couleurs et animations exactes (style natif Apple) ; textes définitifs ; dessin de l'icône ;
détails du fond du `.dmg`.
