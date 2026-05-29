# Agent Skills — BlitzRecorder

Project-scoped install only. Skill folders live at:
- `.agents/skills/<name>/`

The lock file lives at `.agents/skills-lock.json`.

Nothing was written to agent-specific global folders such as `~/.claude/`,
`~/.codex/`, or `~/.agents/`.

---

## Source repos

| Repo | Type | Skills extracted |
|---|---|---|
| https://github.com/twostraws/SwiftUI-Agent-Skill | Single skill | 1 |
| https://github.com/twostraws/swift-agent-skills | Master index (no skills inside) | 0 |
| https://github.com/Dimillian/Skills | Multi-skill collection | 16 |
| https://github.com/arjitj2/swiftui-design-principles | Single skill (root-level) | 1 |
| https://github.com/code-with-beto/skills | Multi-skill collection | 2 |
| **Total installed** | | **20** |

> `twostraws/swift-agent-skills` is a curated README pointing to other authors' skills — there are no `SKILL.md` files inside the repo itself, so nothing is installed from it. Use it as a discovery hub.

---

## Installed skills

Legend: 🟢 strong fit for BlitzRecorder · 🟡 generic utility · 🔴 not relevant (candidate to remove)

### From `twostraws/SwiftUI-Agent-Skill` (Paul Hudson)

| Skill | Verdict | Use for |
|---|---|---|
| [`swiftui-pro`](https://github.com/twostraws/SwiftUI-Agent-Skill) | 🟢 | Modern SwiftUI best practices: navigation, layout, animations, state management, accessibility, deprecated API. Broad coverage. |

### From `arjitj2/swiftui-design-principles`

| Skill | Verdict | Use for |
|---|---|---|
| [`swiftui-design-principles`](https://github.com/arjitj2/swiftui-design-principles) | 🟢 | Polished design: base-4/8 spacing grid, typography hierarchy, semantic colors, proportional sizing, native grouped content, pre-ship checklist. |

### From `Dimillian/Skills`

| Skill | Verdict | Use for |
|---|---|---|
| [`swiftui-ui-patterns`](https://github.com/Dimillian/Skills/tree/main/swiftui-ui-patterns) | 🟢 | macOS Settings, split views, async state, theming, scroll/focus/searchable patterns. |
| [`swiftui-view-refactor`](https://github.com/Dimillian/Skills/tree/main/swiftui-view-refactor) | 🟢 | Smaller subviews, MV-style data flow, stable view trees, DI, correct Observation usage. |
| [`swift-concurrency-expert`](https://github.com/Dimillian/Skills/tree/main/swift-concurrency-expert) | 🟢 | Actor isolation, `Sendable`, `@MainActor`, data races. High value — AVFoundation/ScreenCaptureKit/Speech are async-heavy. |
| [`macos-spm-app-packaging`](https://github.com/Dimillian/Skills/tree/main/macos-spm-app-packaging) | 🟢 | Scaffolds/builds/signs/notarizes SwiftPM macOS apps without an Xcode project. **Exact match for this repo's setup.** |
| [`swiftui-performance-audit`](https://github.com/Dimillian/Skills/tree/main/swiftui-performance-audit) | 🟢 | Invalidation storms, identity churn, layout thrash. Useful for the live preview canvas. |
| [`review-and-simplify-changes`](https://github.com/Dimillian/Skills/tree/main/review-and-simplify-changes) | 🟡 | Review a diff for reuse, clarity, efficiency; optionally apply safe fixes. |
| [`review-swarm`](https://github.com/Dimillian/Skills/tree/main/review-swarm) | 🟡 | 4-agent diff review (regressions, security, perf, contract gaps). |
| [`bug-hunt-swarm`](https://github.com/Dimillian/Skills/tree/main/bug-hunt-swarm) | 🟡 | 4-agent bug investigation (repro, tracing, regressors, fastest proof). |
| [`github`](https://github.com/Dimillian/Skills/tree/main/github) | 🟡 | `gh` CLI helpers for PRs, issues, workflow runs, CI logs. |
| [`orchestrate-batch-refactor`](https://github.com/Dimillian/Skills/tree/main/orchestrate-batch-refactor) | 🟡 | Plans larger refactors with parallel work packets. |
| [`project-skill-audit`](https://github.com/Dimillian/Skills/tree/main/project-skill-audit) | 🟡 | Analyzes past sessions/memory to recommend new skills. Meta. |
| [`swiftui-liquid-glass`](https://github.com/Dimillian/Skills/tree/main/swiftui-liquid-glass) | 🔴 | iOS 26+ Liquid Glass APIs — project targets macOS 14. |
| [`react-component-performance`](https://github.com/Dimillian/Skills/tree/main/react-component-performance) | 🔴 | No React in this project. |
| [`ios-debugger-agent`](https://github.com/Dimillian/Skills/tree/main/ios-debugger-agent) | 🔴 | XcodeBuildMCP + iOS simulator — this is a macOS app. |
| [`macos-menubar-tuist-app`](https://github.com/Dimillian/Skills/tree/main/macos-menubar-tuist-app) | 🔴 | Tuist + menubar app — this is SwiftPM and not a menubar app. |
| [`app-store-changelog`](https://github.com/Dimillian/Skills/tree/main/app-store-changelog) | 🔴 | App Store release notes — not currently shipping to App Store. |

### From `code-with-beto/skills`

| Skill | Verdict | Use for |
|---|---|---|
| `app-icon` | 🟡 | Generate app icons for React Native projects. Keep only if icon generation work recurs here. |
| `ship` | 🟡 | Scaffold production-ready React Native apps. Keep only if shared mobile workflows need it. |

---

## Recommended core set for BlitzRecorder

For **design / UI / UX / architecture** work, the seven 🟢 skills above are the working set:

1. `swiftui-design-principles` — visual polish
2. `swiftui-pro` — broad SwiftUI best practices
3. `swiftui-ui-patterns` — macOS-flavored patterns
4. `swiftui-view-refactor` — view/state architecture
5. `swift-concurrency-expert` — async/actor correctness
6. `macos-spm-app-packaging` — build/sign/notarize this app
7. `swiftui-performance-audit` — preview canvas perf

---

## Discovery references

- **Master index** — https://github.com/twostraws/swift-agent-skills — categorized list of community skills (SwiftUI, SwiftData, Concurrency, Testing, Architecture, Accessibility, App Intents, Performance, Security, UI).
- **Agent Skills format** — https://agentskills.io / https://skills.sh
- **`npx skills add <repo>`** — official multi-agent installer (alternative to the manual copy used here).
