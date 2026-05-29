# 18 agent skills pour que Claude Code et Codex arrêtent de saccager ton SwiftUI

*Le starter pack pour devs Apple qui codent avec un agent IA.*

Par **Virgile Rietsch**. Suis-moi sur [algomax.fr](https://algomax.fr).

---

## Pourquoi tes agents écrivent moche par défaut

Claude Code et Codex te pondent du SwiftUI qui compile mais qui pue. Marges au pif (26, 34, 36 pt pour la même vue), sept tailles de police différentes, `View` monolithique de 400 lignes, `@MainActor` posé n'importe où "pour faire taire le compilateur", `Color.white.opacity(0.42)` au lieu d'une couleur sémantique. Ton app a l'air sortie de 2015 alors que t'utilises iOS 18.

C'est pas l'agent qui est nul. C'est que tu lui as rien donné comme garde-fou. Sa fenêtre de contexte est large, mais son "goût" Apple est moyen, et son backlog de bonnes pratiques s'arrête à la date de cutoff du modèle. Résultat, il code par approximation : ce qui ressemble à du SwiftUI moderne, sans les détails qui font qu'une app *feels right*.

Les **agent skills** réparent ça. Ce sont des fichiers markdown que l'agent charge automatiquement quand le contexte matche. Tu installes une fois, l'agent suit la doc à chaque tâche pertinente. Plus besoin de relire ses outputs au peigne fin pour repérer les marges arbitraires ou les violations Sendable.

Dans cette fiche, je te file ma sélection de **18 skills** que j'installe sur mes projets macOS et iOS, les **7 à mettre en priorité**, les commandes copy-paste, mon workflow et les pièges qui m'ont coûté du temps.

---

## C'est quoi un "agent skill" ?

Format ouvert ([agentskills.io](https://agentskills.io)) supporté par Claude Code, Codex, Cursor, Windsurf, Gemini CLI.

Concrètement, c'est un dossier avec :

```
mon-skill/
  SKILL.md          # frontmatter + corps de la doc
  references/       # docs détaillées chargées à la demande
  agents/           # configs par agent (optionnel)
```

Le `SKILL.md` commence par un YAML frontmatter qui dit quand le skill doit se déclencher :

```yaml
---
name: swiftui-design-principles
description: Design principles for SwiftUI apps. Use when creating or modifying SwiftUI views, widgets, or any native Apple UI.
---
```

L'agent lit la `description`. Si la tâche match (tu touches à une SwiftUI View), il charge le corps du skill et applique ses règles. T'as rien à invoquer manuellement.

Deux portées :

- **Project-scoped** (`.agents/skills/`) : actif uniquement dans ce repo, versionné avec le code.
- **Global** (`~/.agents/skills/`) : actif partout, suit ton user, pas versionné.

Sur les projets Swift, je préfère project-scoped. Comme ça l'équipe ou le futur-moi récupère les skills en clonant le repo.

---

## Installation : 2 méthodes

### Méthode 1 : `npx skills add` (officielle, multi-agent)

```bash
# Single skill
npx skills add https://github.com/twostraws/swiftui-agent-skill --skill swiftui-pro

# Repo multi-skills (te demande lesquels installer)
npx skills add Dimillian/Skills
```

Le CLI te demande :
- pour quels agents (Claude Code, Codex, Cursor, Windsurf, Gemini)
- portée projet ou global

Pas de `npx` ? `brew install node` d'abord.

### Méthode 2 : clone + copie manuelle (project-scoped propre)

Si tu veux contrôler exactement ce qui rentre dans le repo, version par version :

```bash
# Clone tous les repos sources dans un dossier temporaire
mkdir -p /tmp/skill-repos && cd /tmp/skill-repos
git clone --depth 1 https://github.com/twostraws/SwiftUI-Agent-Skill.git twostraws-swiftui
git clone --depth 1 https://github.com/Dimillian/Skills.git dimillian
git clone --depth 1 https://github.com/arjitj2/swiftui-design-principles.git arjitj2-design

# Dans ton repo
cd /chemin/vers/ton/projet
mkdir -p .agents/skills

# Pour chaque skill que tu veux, copie le dossier dans les deux emplacements
cp -R /tmp/skill-repos/twostraws-swiftui/swiftui-pro .agents/skills/
# (etc. pour les autres)
```

C'est ce que j'ai fait sur BlitzRecorder. Avantage : tu choisis exactement quels skills entrent, tu vois le diff, tu peux retirer les irrelevants avant le premier commit.

Après install, **relance ton agent** (nouvelle session Claude Code ou Codex). Les skills se chargent au boot.

---

## Le starter pack : 7 skills à installer en premier

Si tu n'installes que ça, t'as déjà 90% du gain.

### 1. `swiftui-design-principles` (arjitj2)

**À quoi ça sert.** Encode les règles de design qui séparent une app polie d'une app "AI-slop" : grille base-4/base-8 obligatoire, hiérarchie typo basée sur le poids (pas la taille), couleurs sémantiques système au lieu de hardcoded, composants natifs (Gauge, NavigationStack) au lieu de ZStack manuels, checklist pré-ship.

**Quand ça fire.** Création ou modification d'une SwiftUI View ou d'un Widget.

**Gain concret.** Plus de `padding(26)`, plus de `Color.white.opacity(0.42)`, plus de `cornerRadius: 22` aléatoire. L'agent applique la grille.

```
Repo : github.com/arjitj2/swiftui-design-principles
```

### 2. `swiftui-pro` (Paul Hudson / twostraws)

**À quoi ça sert.** Le couteau suisse SwiftUI moderne. Couvre les APIs récentes, navigation (`NavigationStack` vs `NavigationView` deprecated), layout, animations, gestion d'état (`@Observable` vs `@StateObject`), accessibilité (VoiceOver), perfs. Cible les erreurs que les LLMs font vraiment.

**Quand ça fire.** Read, write ou review de code SwiftUI.

**Gain concret.** Plus de code basé sur des APIs deprecated depuis iOS 16. Plus de `@ObservedObject` quand `@Observable` ferait mieux.

```
Repo : github.com/twostraws/SwiftUI-Agent-Skill
```

### 3. `swiftui-ui-patterns` (Dimillian)

**À quoi ça sert.** Patterns concrets pour macOS et iOS. Énorme couverture : Settings macOS, split views, async state, theming, scroll, focus, searchable, matched transitions, form, list, grids. Avec exemples copy-paste.

**Quand ça fire.** Création ou refactor de UI SwiftUI, design de tab architecture, composition de screens.

**Gain concret.** Quand tu dis "fais-moi un panneau Settings macOS", l'agent connaît la convention `Settings { ... }` + `SettingsView` plutôt que de bricoler une fenêtre custom.

```
Repo : github.com/Dimillian/Skills/tree/main/swiftui-ui-patterns
```

### 4. `swiftui-view-refactor` (Dimillian)

**À quoi ça sert.** L'antidote aux Views de 400 lignes. Pousse vers : sous-vues plus petites, data flow MV-style (Model-View, pas MVVM ceremonial), arbres de vues stables (pour éviter les re-renders complets), DI explicite par init, usage correct du nouveau framework `Observation`.

**Quand ça fire.** Quand tu demandes un refactor, ou que tu touches une View qui dépasse 150-200 lignes.

**Gain concret.** Au lieu de "extract subview" plat, l'agent comprend où couper, comment passer les bindings, où garder l'état.

```
Repo : github.com/Dimillian/Skills/tree/main/swiftui-view-refactor
```

### 5. `swift-concurrency-expert` (Dimillian)

**À quoi ça sert.** Swift 6.2+ concurrency. Isolation d'acteurs, conformance `Sendable`, `@MainActor`, diagnostics de data race, migration vers strict concurrency. C'est LE skill qui te sauve quand AVFoundation, ScreenCaptureKit, Speech ou Core Image te crient dessus.

**Quand ça fire.** Toute tâche qui touche du code async, des callbacks AVFoundation, des notifications cross-thread, ou qui produit un warning concurrency.

**Gain concret.** Au lieu de balancer `@MainActor` partout pour faire taire le compilo, l'agent comprend où isoler vraiment.

```
Repo : github.com/Dimillian/Skills/tree/main/swift-concurrency-expert
```

### 6. `macos-spm-app-packaging` (Dimillian)

**À quoi ça sert.** Build / sign / notarize une app macOS basée sur Swift Package Manager, sans projet Xcode. Scaffolding `.app` bundle, Info.plist, code signing, notarisation Apple, scripts de release. Pile poil ce qu'il faut pour les apps macOS modernes sans Xcode IDE.

**Quand ça fire.** Tu demandes un script de build, tu veux distribuer, tu galères avec TCC ou la signature.

**Gain concret.** Plus besoin de googler les flags `codesign` pendant 2h. L'agent connaît le flow complet.

```
Repo : github.com/Dimillian/Skills/tree/main/macos-spm-app-packaging
```

### 7. `swiftui-performance-audit` (Dimillian)

**À quoi ça sert.** Audit perf SwiftUI orienté code. Detecte les invalidation storms, le churn d'identité (`@State` mal placé), le layout thrash, le rendu lourd dans `body`, et te guide vers Instruments quand nécessaire.

**Quand ça fire.** Quand tu décris un lag, un freeze, des frames droppées, ou que tu touches une vue qui se redessine trop.

**Gain concret.** L'agent te montre que ta vue se rebuild 60 fois par seconde parce que tu passes un closure non-stable en paramètre.

```
Repo : github.com/Dimillian/Skills/tree/main/swiftui-performance-audit
```

---

## La liste complète : 18 skills

Légende : 🟢 garde · 🟡 utile mais générique · 🔴 retire si t'es sur macOS/iOS classique

| Skill | Verdict | Source |
|---|---|---|
| `swiftui-design-principles` | 🟢 | arjitj2 |
| `swiftui-pro` | 🟢 | twostraws |
| `swiftui-ui-patterns` | 🟢 | Dimillian |
| `swiftui-view-refactor` | 🟢 | Dimillian |
| `swift-concurrency-expert` | 🟢 | Dimillian |
| `macos-spm-app-packaging` | 🟢 | Dimillian |
| `swiftui-performance-audit` | 🟢 | Dimillian |
| `review-and-simplify-changes` | 🟡 | Dimillian |
| `review-swarm` | 🟡 | Dimillian |
| `bug-hunt-swarm` | 🟡 | Dimillian |
| `github` | 🟡 | Dimillian |
| `orchestrate-batch-refactor` | 🟡 | Dimillian |
| `project-skill-audit` | 🟡 | Dimillian |
| `swiftui-liquid-glass` | 🔴 | Dimillian (iOS 26+ uniquement) |
| `react-component-performance` | 🔴 | Dimillian (pas Apple) |
| `ios-debugger-agent` | 🔴 | Dimillian (iOS Simulator only) |
| `macos-menubar-tuist-app` | 🔴 | Dimillian (Tuist + menubar uniquement) |
| `app-store-changelog` | 🔴 | Dimillian (utile uniquement quand tu shippes App Store) |

---

## Mon workflow quotidien sur un projet Swift

Exemple concret, tiré de mon app **BlitzRecorder** (recorder macOS, SwiftPM, SwiftUI + ScreenCaptureKit + AVFoundation + Speech).

### Étape 1 : nouvelle feature

Je tape ma demande à l'agent. Exemple : "Ajoute un panneau Preview en haut de la fenêtre principale qui montre le contenu sélectionné par SCContentSharingPicker, plus un inset caméra en bas à droite."

L'agent charge automatiquement, vu le contexte :
- `swiftui-ui-patterns` (vue principale macOS, layout)
- `swiftui-design-principles` (marges, typo, couleurs)
- `swiftui-pro` (APIs modernes pour preview SCStream)
- `swift-concurrency-expert` (parce que ça touche AVFoundation async)

Résultat : une `PreviewStage` View avec marges sur la grille, fonds sémantiques, gestion correcte des `@MainActor` sur les callbacks AVCapture.

### Étape 2 : la View grossit

Au bout de 3-4 itérations, `MainView.swift` dépasse 250 lignes.

Je dis : "Refactor cette vue, elle est trop grosse."

`swiftui-view-refactor` se charge. L'agent identifie les sous-blocs, propose une structure (`PreviewStage`, `SourceToggleBar`, `RecordControls`), passe les bindings explicitement.

### Étape 3 : perf

Je remarque que la preview drop des frames quand je toggle un source.

"L'agent : pourquoi la preview lag quand je toggle l'audio système ?"

`swiftui-performance-audit` analyse, trouve que mon `@StateObject` au mauvais niveau cause un rebuild complet de la `PreviewStage` à chaque toggle. Propose le fix.

### Étape 4 : packaging

Quand je veux tester sur `/Applications/BlitzRecorder.app` (parce que TCC sur macOS est lié à l'identité de l'app, son chemin compte) :

"Génère un script `build_and_run.sh` qui build via SPM, package en `.app`, signe avec mon dev cert, et lance."

`macos-spm-app-packaging` génère un script qui sait quels flags `codesign` utiliser, comment construire le bundle correctement, où placer l'Info.plist.

### Étape 5 : review avant commit

`review-and-simplify-changes` pour passer sur le diff avant de commit. Repère les patterns dupliqués, les optimisations triviales oubliées.

---

## Les pièges qui m'ont coûté du temps

### 1. Installer global "pour avoir partout" puis polluer tous tes projets

J'ai commencé par installer tout en global. Résultat : sur un projet React, mes agents chargeaient quand même les skills SwiftUI dans le contexte. Pas grave en théorie, mais ça remplit le context window pour rien. Mieux : project-scoped sur chaque repo, et tu commit `.agents/skills/` avec le code.

### 2. Skills qui se contredisent

`swiftui-liquid-glass` cible iOS 26+. Si ton projet target macOS 14 ou iOS 17, ce skill va pousser l'agent vers des APIs que tu ne peux pas utiliser. **Vérifie le target deployment** avant d'installer chaque skill.

### 3. Oublier de relancer l'agent après install

Les skills sont chargés au boot de la session. Si tu installes en plein milieu, l'agent en cours ne les voit pas. Quit, relance, ça repart.

### 4. Trop de skills tuent le focus

J'ai testé avec 30+ skills installés. L'agent commence à hésiter, à charger 5 skills par message, à mélanger les conseils. Au-dessus de ~15-20 skills *réellement pertinents pour ce projet*, ça dégrade. Reste lean. Retire les 🔴 sans hésiter.

### 5. Lire le skill avant de l'installer

Un skill est juste du markdown. Ouvre `SKILL.md`, lis le frontmatter et le corps. Tu valides que les règles correspondent à ton style. Si un skill dit "always use MVVM with separate ViewModel classes" et que toi tu préfères MV-style à la Dimillian, vire-le. Les skills sont des opinions packagées, pas du code neutre.

### 6. `.gitignore` qui mange tes skills

Vérifie que `.agents/` n'est pas ignoré. Sur certains templates, les dossiers de configuration d'agents peuvent être dans `.gitignore` par défaut "pour la sécu". Pour les skills, tu veux qu'ils soient versionnés.

### 7. Confondre "skills" et "MCP servers"

Skill = markdown statique chargé en contexte. MCP server = serveur live qui expose des outils (lecture de docs, queries API, etc.). Les deux coexistent, ils ne servent pas la même chose. Pour du conseil de style et de pattern, c'est skill. Pour fetch des docs à jour, c'est MCP (cf. Context7).

---

## Bonus : écris ton propre skill en 10 minutes

Tu remarques que ton agent fait la même erreur 5 fois sur ton projet ? Skill-ify la règle.

### Template minimal

`mon-projet/.agents/skills/mon-skill/SKILL.md` :

```markdown
---
name: blitzrecorder-tcc-rules
description: Rules for macOS TCC permissions in BlitzRecorder. Use when adding capture sources, handling permission prompts, or wiring AVAuthorizationStatus / SCShareableContent. Ensures correct handling of the screen capture permission gate which does not behave like camera/mic auth.
---

# BlitzRecorder TCC rules

## Permission gates

- Camera et microphone : `AVAuthorizationStatus`, promptable via `AVCaptureDevice.requestAccess(for:)`.
- Screen recording (`kTCCServiceScreenCapture`) : NOT promptable. macOS retourne "denied" sans afficher de dialogue. La seule façon de prompter, c'est de tenter un capture (qui échoue) ; macOS affiche alors le path vers System Settings.
- Système audio : suit le même TCC que screen recording. Pas de chemin séparé.

## Path d'identité

- TCC est lié à : bundle id + signature + chemin de l'app.
- Pour tester localement, build via `script/build_and_run.sh` et lance `/Applications/BlitzRecorder.app`. Pas le binaire dans `.build/`, sinon TCC voit une autre app.

## SCContentSharingPicker

- Préféré sur la voie "broad capture" pour les flows interactifs.
- C'est session-scoped : l'utilisateur consent à un screen / window / app spécifique pour cette session uniquement.
- Bypasse le `kTCCServiceScreenCapture` gate pour ce contenu sélectionné.
- Mais : système audio nécessite quand même le gate broad.
```

### Bonnes pratiques

- **`name`** en kebab-case, préfixé par ton projet pour éviter les collisions.
- **`description`** courte mais riche en mots-clés. C'est ce que l'agent matche pour décider de charger.
- **Verbatim > paraphrase.** Si tu colles une convention de code, mets l'exemple exact, pas un résumé.
- **Couvre les pièges, pas les évidences.** "Use SwiftUI" ne sert à rien. "Don't call AVCaptureSession.startRunning() on @MainActor, dispatch to sessionQueue" sert.
- **Versionne-le.** Le skill évolue avec ton projet. Commit chaque changement.

Tu peux aussi factoriser en `references/` quand un skill grossit. Le `SKILL.md` charge à 100% à chaque match, les `references/` à la demande de l'agent.

---

## Mes sources

Les 4 repos qui composent ce starter pack :

1. **[twostraws/SwiftUI-Agent-Skill](https://github.com/twostraws/SwiftUI-Agent-Skill)** — Paul Hudson (Hacking with Swift). 1 skill : `swiftui-pro`.
2. **[twostraws/swift-agent-skills](https://github.com/twostraws/swift-agent-skills)** — Paul Hudson. Pas un repo de skills mais un index curé, catégorisé par framework (SwiftUI, SwiftData, Concurrency, Testing, Architecture, Accessibility, App Intents, Performance, Security, UI). Le hub à bookmarker.
3. **[Dimillian/Skills](https://github.com/Dimillian/Skills)** — Thomas Ricouard (auteur d'Ice Cubes, Medium, MovieDB). 16 skills couvrant SwiftUI, concurrency, packaging macOS, code review, refactor.
4. **[arjitj2/swiftui-design-principles](https://github.com/arjitj2/swiftui-design-principles)** — Dérivé d'une comparaison côte à côte entre deux apps iOS construites avec un agent IA, une polie et une "off". Les patterns sont littéralement ce qui sépare les deux.

Format ouvert : **[agentskills.io](https://agentskills.io)** / **[skills.sh](https://skills.sh)**.

---

## Récap

Tu installes les **7 skills du starter pack**. Tu retires les 5 🔴. Tu relances ton agent. Tu codes.

Si t'as une question pendant l'install ou que ton agent fait un truc bizarre malgré les skills, écris-moi sur [algomax.fr](https://algomax.fr/cadeau). Je réponds.

— Virgile
