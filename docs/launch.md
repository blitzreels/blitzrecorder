# Open-source launch notes

Use this when announcing BlitzRecorder publicly.

## Links

- Public repo: https://github.com/blitzreels/blitzrecorder
- Website: https://blitzrecorder.com
- Latest release: https://github.com/blitzreels/blitzrecorder/releases/latest
- Issues: https://github.com/blitzreels/blitzrecorder/issues

## Before posting

- Confirm the public repo is public and default branch is `main`.
- Run `Scripts/check-open-source-readiness.sh` in the public snapshot.
- Run `Scripts/check-github-release-readiness.sh --repo blitzreels/blitzrecorder`.
- Publish a signed DMG release or remove the release link from the post.
- Pin one issue for good first contributions.
- Pin one issue for feedback from real creators.
- Make sure the website points to `blitzreels/blitzrecorder`.

## X post

I open-sourced BlitzRecorder.

It is a native Mac recorder for creators: screen, camera, mic, system audio, scenes, and an iPhone camera companion.

Free tier records 1080p. $39 Early Lifetime License unlocks iPhone camera, 4K, 60 fps, signed builds, updates, and support.

Repo:
https://github.com/blitzreels/blitzrecorder

## Shorter version

BlitzRecorder is now open source.

Native Mac screen recording, scenes, audio, and iPhone camera support.

AGPL for the code. Free 1080p tier. $39 Early Lifetime License for iPhone camera, 4K, 60 fps, official builds, updates, and support.

https://github.com/blitzreels/blitzrecorder

## Follow-up post

Why open source?

I want creators and Mac developers to be able to inspect the recorder, learn from it, and contribute if they care about the same problem.

The model stays simple: source is AGPL, the Mac app has a free 1080p tier, and the paid direct-download license unlocks the creator features that cost the most to support.

## Reply ideas

- The Mac app builds universal DMGs for Apple Silicon and Intel.
- The iPhone companion records the master camera file locally, then sends it back to the Mac take.
- The repo includes the app, release automation, App Store/TestFlight workflows, and Sparkle update setup.
- Good first issues are welcome, but not every PR will be merged. The project needs to stay focused.

## Positioning

Keep the tone direct:

- Built for creator recordings, not enterprise screen capture.
- Open source for trust, learning, and serious contributors.
- Free tier has no account, card, watermark, or subscription.
- Paid launch license unlocks iPhone camera, 4K, and 60 fps.
- Official builds matter because users need signed, notarized, auto-updating software.
