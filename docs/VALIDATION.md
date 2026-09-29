# Validation — September 28, 2026

Environment: Apple Silicon MacBook, macOS 26.6.2, Xcode 27.0, built-in Retina
display plus an external 1080p monitor; Cap Desktop 0.6.0.

## Verified

- Signed Debug build succeeds using the existing Apple Development identity.
- App launches as a native `.app`; its editor, script field, playback controls,
  panel settings, and microphone picker were inspected through accessibility
  and a screenshot.
- The microphone picker lists the MacBook microphone, OWC Thunderbolt audio,
  and Brio 100. Selecting voice-follow and starting reaches macOS microphone
  authorization.
- Focused core tests cover elapsed-time scrolling, pause/resume, countdowns,
  end-of-script, empty scripts, paragraph navigation, normalized words, repeated
  phrases, revised partial results, small omissions, unrelated ad-libs,
  bounded matching, manual re-anchoring, atomic draft recovery, corrupt data,
  and camera-adjacent geometry with different display origins.
- An opt-in integration test passed using Apple's actual on-device recognizer
  with generated speech. The resulting transcript advanced the real matcher
  through every word of the fixture.
- The final combined run passed all 15 tests, including the on-device integration.
- Cap 0.6.0 source inspection confirms its desktop excluded-window picker stores
  bundle identifiers and resolves visible windows before recording. This is
  configuration support, not proof of an excluded recording from this Mac.

## Pending live checks

The Mac locked during verification, and the computer-control tool cannot
interact with macOS's microphone authorization dialog. No claim is made that
these checks have passed:

- Approve Teleprompter's microphone access and speak a real script. Check pauses,
  ad-libs, and retakes; verify the input meter goes to zero and microphone
  capture stops when paused or hidden.
- Show the panel, add Teleprompter to Cap Desktop's excluded windows, and record
  a Studio sample with screen, built-in camera, and microphone while voice-follow
  runs. Inspect the saved video and audio for exclusion, continuity, and smooth
  scrolling. Cap settings were not changed during the locked-session checks.
- Inspect the panel beneath the physical notch and across fullscreen apps;
  confirm clicking its controls does not steal keyboard focus from the recorder.
- Exercise global shortcuts with another app focused, including an intentional
  conflict and reassignment. Change display configuration and check reanchoring.
- Read from 2 and 4 feet, sitting and standing. Judge readability and eye movement
  from the resulting camera recording; tune the adjustable layout as needed.

Generated fixture audio and test logs are local-only under `artifacts/` and are
not included in Git. Build logs are under `build/`.
