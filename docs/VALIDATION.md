# Validation — September 29, 2026

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

## September 29 playback repair

- Reproduced voice-follow pausing immediately after Play: a routine
  `AVAudioEngineConfigurationChange` notification was treated as a fatal error.
  The input now checks its actual running state and format, keeps a healthy
  stream running, and can rebuild a stopped or reformatted stream with bounded
  retries. Recovery preserves the analyzer session and script position.
- Live microphone input also exposed a Swift 6 actor-isolation crash in the
  audio tap. The tap is explicitly `@Sendable` so it runs on AVAudioEngine's
  callback queue rather than inheriting the UI actor.
- The corrected signed Debug app was rebuilt and relaunched. Voice-follow
  completed its countdown, remained active, and Apple's analyzer continuously
  received microphone audio buffers. A startup configuration notification
  reported a healthy 48 kHz mono input and no longer paused playback.
  Pause and resume were also exercised through the UI, returning to microphone
  off and then listening without a crash or configuration error.
- Auto-scroll was exercised through the UI: countdown, progress, and completion
  of the 53-word welcome script were observed.
- Four regression tests cover startup recovery, harmless notifications, changed
  formats, and bounded retries. All 19 tests passed in the final run, including
  Apple's on-device recognition of the generated fixture and actual script
  alignment.
- Live spoken-word advancement still needs confirmation. The speaker test was
  inaudible because the system output was muted; no sound settings were changed.

## Pending live checks

Microphone access is now granted and the live input starts. No claim is made
that these remaining checks have passed:

- Speak a real script. Check pauses,
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
