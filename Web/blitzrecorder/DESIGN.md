# Site design system

The site mirrors the Mac app. Tokens live in `app/globals.css` and copy `BlitzUI`
(`Sources/BlitzRecorderApp/UI/BlitzUIPrimitives.swift`) and `BlitzControlMetrics`
(`Sources/BlitzRecorderApp/UI/BlitzButtonStyle.swift`). Change both together.

## Color

| Token | Value | App source |
| --- | --- | --- |
| `background` | `#09090b` | `canvasBackground` |
| `card` (`.panel`) | `#1b1b1b` | `panelBackground` |
| `primary` | `#17ffa6` | `mint`, selected or active states and the main CTA only |
| `record` | `#ff4545` | `recordRed`, the only red |
| `warning` | `#ffb838` | `warning` |
| `foreground` / `muted-foreground` / `faint` | white 92% / 72% / 56% | `primaryText` / `supportingText` / `secondaryText` |
| `fill-card` / `fill-quiet` / `fill-control` / `fill-hover` / `fill-selected` | white 3.5 / 4.5 / 5.5 / 7.5 / 10% | same names |
| `border` / `separator` | white 10% / 8% | `panelStroke` / `separator` |
| `track-*` | cyan, teal, `#b88aff`, `#5c8fff` | `trackScreen`, `trackCamera`, `trackMicrophone`, `trackSystemAudio` |

## Radius

| Class | Value | Use |
| --- | --- | --- |
| `rounded-inner` | 6px | segments inside a control, timeline clips, canvas frame |
| `rounded-control` | 8px | buttons, inputs, segmented controls, pills (`BlitzControlMetrics.radius`) |
| `rounded-tile` | 10px | layout tiles (`sceneCardRadius`) |
| `rounded-card` | 12px | panels, windows, cards (`cardRadius`) |

`rounded-full` is only for dots, bars, and progress tracks.

## Controls

`Button` follows `BlitzButtonStyle`: `default` = accent (mint, black 88% text),
`outline` = secondary (control fill + 10% stroke), `ghost` = quiet.
Heights: `sm` 28, `default` 34, `lg` 40.

## Surfaces

- `.panel`: flat `card` fill, no stroke. No cards nested in cards.
- `.app-surface`: add to a panel that draws a piece of the app (window, canvas, timeline).
- Selection is a brighter fill (`fill-selected`), not a mint outline.
- No gradients on text, no grain, no glows.
