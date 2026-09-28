# BlitzRecorder Web

Next.js app for the BlitzRecorder marketing site, product pages, checkout flows, license handling, and public app metadata.

## App Structure

```text
app/
  page.tsx                  Home route. Renders the landing page.
  layout.tsx                Root layout, metadata, fonts, and global shell.
  globals.css               Global Tailwind styles and shared visual effects.
  opengraph-image.tsx       Dynamic Open Graph image.
  robots.ts                 Robots metadata route.
  sitemap.ts                Sitemap metadata route.
  ios/                      iOS product page route.
  macos/                    macOS product page route.
  license/                  License pages and claim UI.
  privacy/                  Privacy page.
  support/                  Support page.
  terms/                    Terms page.
  upgrade/                  Upgrade route.
  api/                      Server routes for license issue, notify, Stripe (legacy keys), and licenses.

components/
  site/                     Site-specific UI and feature components.
    landing/                Home landing page sections and landing-only helpers.
      index.tsx             Landing page orchestrator.
      hero.tsx              Hero, presentation film, and chapter links.
      chapter.tsx           Timeline chapter ruler and section header.
      record-chapter.tsx    Record: interactive layout composer.
      camera-chapter.tsx    iPhone camera: phone preview and pairing inspector.
      edit-chapter.tsx      Edit: silence-removal timeline and transcript.
      export-chapter.tsx    Export: resolution, frame rate, speed, and BlitzReels.
      share-chapter.tsx     Share: hosted link with transcript and chapters.
      toolbox.tsx           "Also in the app" list.
      faq.tsx               FAQ accordion section.
      pricing.tsx           Free plan and final download CTA.
      checkout-return-tracker.tsx  Legacy checkout return analytics.
      tracking.ts           Landing CTA tracking helper.
      reveal.ts             Reveal animation delay helper.
    app-window.tsx          macOS window frame for app screenshots.
    product-page.tsx        Product page template for macOS and iOS.
    product-shell.tsx       Product page shell.
    legal-page.tsx          Terms, privacy, and support template.
    site-nav.tsx            Global site navigation.
    site-footer.tsx         Global site footer.
    marketing-only.tsx      Hides marketing scripts on shared video pages.
    download-button.tsx     Download CTA and version metadata.
    buy-button.tsx          Legacy license email form.
    notify-form.tsx         Waitlist form.
    journey-markers.tsx     Page and section analytics markers.
    icons.tsx               Site icon components.
  ui/                       Reusable primitive UI components. See DESIGN.md.
    button.tsx
    card.tsx
    layout.tsx
    typography.tsx

lib/
  assets.ts                 Static image asset imports.
  content.ts                Site copy, product pages, FAQs, and legal pages.
  journey-events.ts         Analytics event helper.
  release.ts                Release/download metadata helpers.
  payments.ts               Stripe/payment helpers.
  licenses.ts               License business logic.
  license-issue.ts          Free license HTTP issue helper.
  license-store.ts          License persistence helpers.
  notify-store.ts           Waitlist/notification persistence helpers.
  utils.ts                  Shared utility helpers.

public/
  generated-icons/          App icon artwork.
  media/                    Editor screenshot and frames from a real take.
  logos/                    Brand logos.
  videos/                   Public video assets.

types/
  datafast.d.ts             DataFast type declarations.
```

## Landing Page Organization

The home page is intentionally split by section under `components/site/landing/`.

`components/site/landing/index.tsx` owns the page order and global landing concerns:

- reveal initialization
- checkout return tracker
- page view tracking marker
- site background, navigation, footer
- section composition

Each visible section lives in its own file, such as `hero.tsx`, `features.tsx`, `editor.tsx`, `pricing.tsx`, and `faq.tsx`. Shared landing-only helpers also stay in this folder so they do not leak into broader site components unless needed elsewhere.

## Common Commands

```bash
npm run dev
npm run lint
npx tsc --noEmit
npm run build
```

## Notes

- Route-level pages and server routes live in `app/`.
- Reusable site components live in `components/site/`.
- Generic primitives live in `components/ui/`.
- Editable marketing and product copy should usually go in `lib/content.ts`.
- Static assets should be imported through `lib/assets.ts` when they are used by React components.
