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

## Type

Geist for everything, Geist Mono only for timecodes. Headings are Geist semibold set tight:
`.type-hero` (page titles, -0.045em), `.type-title` (section titles, -0.04em), `.type-statement`
(sentence-sized statements, weight 500). Body copy is 15 to 20px in `muted-foreground`. Section titles are
sentences, never labels: no small or uppercase text above a heading.

## Radius

| Class | Value | Use |
| --- | --- | --- |
| `rounded-inner` | 8px | timeline clips, segments inside a control |
| `rounded-control` | pill | buttons, inputs, segmented controls |
| `rounded-tile` | 16px | small media, phone screens |
| `rounded-card` | 24px | dialogs, large panels |
| `rounded-[20px]` | 20px | product shots (`.product-surface`) |

## Controls

`Button` keeps `BlitzButtonStyle` colors: `default` = accent (mint, black 88% text),
`outline` = secondary, `ghost` = quiet. Shape is a pill. Heights: `sm` 32, `default` 36, `lg` 48.
Selected options in a segmented control are white with black text; mint is for the main action.

## Surfaces

- Sections sit on the black page. No grey bands, no cards inside cards.
- `.product-surface`: a piece of the product on the page (hairline edge, lit top edge, deep soft shadow). `Card` uses it.
- Product shots use the device frames in `components/site/devices.tsx` (MacBook, iPhone) and only real material:
  app renders from `Scripts/ui-proof.sh` (`BLITZRECORDER_PROOF_SCALE=2`) and real exports from published videos.
  Never a mock UI or a scripted demo video.
- Viewfinder corner marks (`FrameMarks`) only on the 404 and error screens (`Problem`).
- No gradients on text, no grain, no glows.

## Motion

Device videos play silently while on screen (`useLoopingVideos`) and pause off screen. Everything else moves only
when the visitor acts (a toggle, a button). No fade-in on scroll. Reduced motion keeps the posters.

## Copy

Outcomes, not features. Say a reassurance once, at the point of action (under the download button). No release
counts or build details on marketing pages.
