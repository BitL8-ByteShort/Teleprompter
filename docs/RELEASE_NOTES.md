# Teleprompter 1.1.2 — First Public Preview

This is the first release for public testing. Version 1.1.2 (build 4) follows
private development builds; it is not a claim that earlier versions were public.

Read scripts just below your MacBook camera while Cap, OBS, or another app
handles recording.

## Included

- Steady auto-scroll at an adjustable 60–240 WPM.
- Voice-follow with Apple Speech by default and optional Moonshine Small,
  Parakeet Realtime, and Whisper Turbo downloads.
- Trackpad and mouse-wheel scrolling, paragraph navigation, retakes, and
  configurable countdowns and shortcuts.
- Adjustable text size, panel width, visible lines, opacity, and alignment.
- A local script library with search, autosave, import/export, and recoverable
  Trash.
- A native app icon and bundled license documents.

## Install

Requires macOS 26 or later, Apple Silicon, and an open built-in MacBook display.
Download `Teleprompter-1.1.2-arm64.dmg`, open it, drag the app into Applications,
and eject the disk image. Optional speech models download separately.

The app is signed by Salty Panda LLC, notarized by Apple, and has an attached
notarization ticket. The disk-image container has no separate signature or ticket.

## Preview limits

Performance has been checked on the development Mac; recording-load testing on
8 GB and 16 GB Macs is still pending. Whisper can take time to prepare on first
use. English (US) is the default speech language.

Before a full take, make and inspect a short recording to confirm the panel is
excluded and the audio is intact. Cap setup instructions are in the
[README](../README.md#recording-with-cap-or-obs). Recorder exclusion has not been
verified here by inspecting an actual saved Cap recording.

## Report bugs

[Check existing issues](https://github.com/BitL8-ByteShort/Teleprompter/issues),
then [submit a bug report](https://github.com/BitL8-ByteShort/Teleprompter/issues/new?template=bug_report.yml).
Include app version/build, Mac model and memory, macOS version, playback mode or
speech engine, reproduction steps, expected behavior, and actual result. Remove
private script text from screenshots and clips. Bug reports don't require the
contributor agreement; questions and feature ideas can use a general issue.

## License and validation

Teleprompter remains under Salty Panda LLC's proprietary license. Personal and
internal business use, including monetized videos, is permitted by the
[license](../LICENSE). Contributions are welcome through the
[contribution guide](../CONTRIBUTING.md) and separately accepted
[contributor agreement](../CLA.md).

The app build completed a 59-test run with one optional Apple speech fixture
skipped, passed the script-library integration checks, and passed signature,
notarization-ticket, and Gatekeeper verification. All 79 third-party license
documents were checked in the app and installer. These checks do not establish
performance on every supported Mac. See [validation notes](VALIDATION.md) and
[distribution verification](DISTRIBUTION_SECURITY.md).
