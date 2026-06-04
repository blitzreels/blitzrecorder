# Open-source launch notes

Use this when announcing BlitzRecorder publicly.

## Links

- Public repo: https://github.com/blitzreels/blitzrecorder-public
- Website: https://blitzrecorder.com
- Latest release: https://github.com/blitzreels/blitzrecorder-public/releases/latest
- Issues: https://github.com/blitzreels/blitzrecorder-public/issues

## Before posting

- Confirm the public repo is public and default branch is `main`.
- Run `Scripts/check-open-source-readiness.sh` in the public snapshot.
- Run `Scripts/check-github-release-readiness.sh --repo blitzreels/blitzrecorder-public`.
- Publish a signed DMG release or remove the release link from the post.
- Pin one issue for good first contributions.
- Pin one issue for feedback from real creators.
- Make sure the website points to the public repo, not the private development repo.

## X post

I open-sourced BlitzRecorder.

It is a native Mac recorder for creators: screen, camera, mic, system audio, scenes, and an iPhone camera companion.

Code is AGPL. Paid licenses fund signed builds, updates, and support.

Repo:
https://github.com/blitzreels/blitzrecorder-public

## Shorter version

BlitzRecorder is now open source.

Native Mac screen recording, scenes, audio, and iPhone camera support.

AGPL for the code. Paid licenses for official builds, updates, support, and commercial use.

https://github.com/blitzreels/blitzrecorder-public

## Follow-up post

Why open source?

I want creators and Mac developers to be able to inspect the recorder, learn from it, and contribute if they care about the same problem.

The model stays simple: the app is free and open source; official signed builds, updates, and support are trust and distribution work, not feature gates.

## Reply ideas

- The Mac app builds universal DMGs for Apple Silicon and Intel.
- The iPhone companion records the master camera file locally, then sends it back to the Mac take.
- The repo includes the app, release automation, App Store/TestFlight workflows, and Sparkle update setup.
- Good first issues are welcome, but not every PR will be merged. The project needs to stay focused.

## Positioning

Keep the tone direct:

- Built for creator recordings, not enterprise screen capture.
- Open source for trust, learning, and serious contributors.
- No Pro tier or export limit at launch.
- Official builds matter because users need signed, notarized, auto-updating software.
