# Validation — September 29, 2026

## First public preview: 1.1.2 (build 4)

The first public preview uses the verified 1.1.2 app build. Public launch changes
the documentation, issue templates, and installer instructions; it does not
change the app executable or bundled models.

- The bug-report form's YAML and six required fields validated. Reports ask for
  app version/build, Mac and macOS details, mode/engine, reproduction steps,
  expected behavior, and actual behavior.
- The refreshed DMG was mounted and its public-preview instructions and report
  URL inspected. All 79 license documents matched the inventory. The app inside
  passed strict signature verification, notarization-ticket validation, and
  Gatekeeper assessment (`accepted`, `Notarized Developer ID`).
- Public installer SHA-256:
  `dc4414e9fdde5befd8ecf65f97d6729c4953d4c34b6d693866097b1909167f1b`.
- The repository was made public and GitHub confirmed the active main ruleset
  (ID 24219843), including owner review, stale-approval dismissal, review-thread
  resolution, force-push protection, and deletion protection. Only the owner
  has an explicit bypass. Old private test releases were retained as drafts.

Earlier automated and local UI evidence is recorded below. The 8 GB/16 GB
recording-load and saved Cap-recording checks remain open; this public preview
does not claim those results.

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
- Live microphone recognition subsequently advanced the script through words
  6–9 of the welcome script, confirmed by the running app's alignment events.
  The earlier synthetic speaker test was inaudible because system output was
  muted; no sound settings were changed. A full visual read-through and the
  practical distance/eye-movement checks remain pending.

## Voice-follow responsiveness

The recognizer previously requested `volatileResults` without `fastResults`.
That returned revised words in batches several seconds apart, so successful
alignment alone did not establish a comfortable live reading experience.

`script/benchmark_speech.swift` streams the same generated 7.73-second fixture
at real-time speed through the on-device recognizer and actual script matcher.
On this Mac, the comparison measured:

| Configuration | First script advance | Matched words |
| --- | --- | --- |
| Partial results only (previous) | 4.05 seconds | 24 / 24 |
| Partial + fast results (current) | 1.12 seconds | 24 / 24 |

The app now enables both options. Apple's `fastResults` uses a smaller context
window and trades some recognition accuracy for responsiveness, so confident
multiword matching and bounded passage search remain in place. See
[Apple's fast-results documentation](https://developer.apple.com/documentation/speech/speechtranscriber/reportingoption/fastresults).

All 19 tests passed with the faster configuration, including on-device
transcription and real matcher integration. The signed app was rebuilt and
relaunched at the saved reading position. These fixture timings describe this
comparison, not a guaranteed microphone latency or human comfort result.

## Continuous voice scrolling repair

The faster recognition setting alone did not solve the reported reading feel.
The display still quantized voice positions to whole lines and eased each jump
over roughly 90 milliseconds. Voice mode now uses fractional word positions
within lines and a continuous, velocity-preserving scroll controller. It starts
moving on the next frame, limits large catch-up movements, and never scrolls
beyond confirmed script progress. The final recognized words scroll out before
the completion message replaces them.

Matching now accepts two exact words within two words of the segment anchor to
start sooner. Fuzzy matching retains its three-word threshold. An exact nearby
three-word suffix can recover after an ad-lib in the same transcript; cached
accepted results prevent duplicate partials from consuming repeated passages.

The regression tests reproduced the old 9-point first-frame jump and the
200-point jump after a delayed frame. The new controller passes movement,
frame-rate consistency, bounded catch-up, silence, retake, line-boundary,
short-phrase, ad-lib recovery, and delayed completion checks. All 28 tests passed,
including on-device transcription. The signed build was relaunched and voice
capture started successfully. Subjective scrolling comfort still needs a live
read-through; numerical tests are not proof of that experience.

## Optional local transcription engines — September 29

- Apple Speech remains the default, including migration of drafts created before
  the engine setting existed. Downloading a model never selects it, opens the
  microphone, or loads its recognition engine.
- Added Moonshine Small Streaming (MoonshineVoice 0.1.5), Parakeet Realtime EOU
  120M with 320 ms Core ML steps (FluidAudio 0.17.4), and the compressed 626 MB
  Whisper Large v3 Turbo variant (WhisperKit 1.1.0). Package versions are pinned
  in both build systems with checked-in lockfiles; weights remain outside the repository.
- All three engines downloaded and transcribed the generated 7.73-second fixture
  using the actual production backend implementations, without microphone or
  speaker playback. Moonshine and Whisper recovered the complete sentence;
  Parakeet recovered the sentence after omitting the opening word "Today."
  This is a small functional fixture, not a general accuracy benchmark.
- A 38.66-second repeated-speech Whisper run completed across four rolling audio
  windows. While inference runs, intermediate revisions are replaced by the
  latest audio; final windows stay ordered. Audio windows and pending inference
  are bounded. Sustained overload reports an error instead of silently dropping
  audio. A long cumulative-transcript regression also covers Parakeet-style
  transcripts, duplicate partials, and manual re-anchoring.
- Core ML loading for Whisper took approximately 51 seconds on this M5 Pro.
  A process sample located that delay in Core ML model loading. The selected
  Whisper model now remains resident while paused for quick retakes; capture and
  inference stop, and switching models or modes releases it. Initial preparation
  status remains visible and can be cancelled.
- The native UI was inspected visually and through accessibility. The model
  disclosure sits immediately above Keyboard shortcuts. Download progress,
  cancellation, retry, Download → Use model → Selected, and unchanged Apple
  selection after downloads were exercised. All three downloaded models remained
  available after relaunch; selected Parakeet and Whisper settings also persisted.
- Moonshine, Parakeet, and Whisper reached live microphone listening in the signed app.
  Selecting another model paused playback, stopped capture, and kept the reading
  position. Whisper pause/resume returned to listening and countdown without
  repeating the long Core ML load. Apple Speech was restored as selected with
  microphone capture off. All 34 tests passed, including the opt-in Apple transcription/matcher
  integration, engine-setting recovery, and Whisper window/silence tests.
- The installed model directories occupied approximately 139 MiB (Moonshine),
  219 MiB (Parakeet), and 608 MiB (Whisper), excluding system Core ML caches.
  These are disk sizes, not RAM requirements. No 8 GB/16 GB hardware or MacBook
  Neo performance claim is established by this M5 Pro validation.

## Manual panel scrolling — September 29

- The floating panel handles AppKit wheel events directly without becoming the
  key window. Precise trackpad deltas move by points; ordinary wheel deltas move
  by lines, using the user's system scrolling direction.
- Scrolling pauses active playback/capture, maps the visible offset back to a
  fractional script position, resets speech alignment, and debounces draft saves.
  It clamps to the first and last readable lines and can leave the finished state
  for a retake. Existing Play controls resume from the new position.
- Both focused regression tests passed: offset/position round trips across lines
  with different word counts, movement in both directions, empty-script and end
  bounds, and resuming after scrolling back from completion. The signed app was
  rebuilt and launched successfully.
- Physical trackpad and mouse-wheel feel remains a user check. The editor was
  actively in use during validation, so automated UI interaction was stopped.

## Resume after manual scrolling and optional countdown — September 29

- A scroll gesture remembers whether it interrupted an active take. After 350 ms
  without another wheel or momentum event, auto-scroll restarts at the new
  fractional position without a countdown. Voice-follow starts a fresh session
  and alignment anchor there. A paused/stopped take remains paused.
- The Pause control remains available while a running take is being repositioned.
  Explicit pause, hide, script edit, navigation, mode/model changes, and shutdown
  cancel any pending automatic resume. Old speech callbacks are invalidated.
- Moonshine and Parakeet now retain only the selected model across suspension,
  like Whisper already did. Transcript/audio state resets for the next take;
  switching engines or leaving voice mode releases the old model.
- Added a saved Countdown menu with No countdown, 1 second, 2 seconds, and
  3 seconds. Existing drafts default to 3 seconds. Explicit starts honor the
  choice; automatic continuation after scrolling always skips the countdown.
- The signed app built and launched. The native menu exposed all four choices,
  and selecting No countdown persisted as zero in the saved draft and survived
  relaunch. The default 3 seconds was restored after testing.
- Both Moonshine and Parakeet transcribed the fixture on two successive takes
  using the new `VoiceEngineCheck --retake` path. The second take prepared in
  roughly 3 ms and 1 ms respectively, without reloading their models, and returned
  a fresh transcript rather than appending to the first take.
- The regression suite passed 40 tests, with the existing opt-in Apple speech
  fixture test skipped. New tests cover all countdown delays, settings recovery,
  gesture/momentum settling, pause cancellation, auto-scroll elapsed time after
  repositioning, and voice alignment at a newly selected passage.
- Automated wheel input into the nonactivating panel is blocked by the UI tool's
  `noWindowsAvailable` error. Panel rendering remains inspectable; physical
  gesture feel and timing are still a user check.

## Tighter camera placement — September 29

- Removed the 8-point gap below the notch/menu bar and the 12-point top padding
  inside the panel. The first reading line is 20 points closer to the camera;
  the panel height now matches its content without the removed padding.
- All three placement tests passed: an offset built-in display, a display
  without a notch, and a notched display with the menu bar hidden. The signed
  app built and launched successfully. Physical notch clearance and the new
  reading position remain a visual user check.

## Constant-speed auto-scroll — September 29

- Reproduced the reported slowdown in the actual playback/layout code using the
  saved 53-word script at 155 WPM, 32-point text, and 440-point panel width. The
  first line moved at 37.20 points/second and the second at 22.32, a 40% drop.
  Other lines ranged from 15.94 to 37.20 points/second.
- Auto-scroll now advances through rendered lines at a constant rate calibrated
  to the complete script's word count and WPM. It maps back to the shared
  fractional word position for seeking, saved drafts, reflow, and voice mode.
  The same diagnostic now reports 25.27 points/second for every line. These are
  playback/layout measurements, not a screen-recording frame-rate benchmark.
- The unequal-line regression failed before the fix and passed afterward. The
  suite passed 47 tests, with one opt-in Apple speech test skipped. Coverage
  includes 30/60/120 Hz and irregular timing, countdown, pause/resume, manual
  retakes, WPM changes, layout changes, and whole-script completion/restart.
- The signed app built and launched, and its native editor shows the saved
  155 WPM setting and updated average-WPM explanation. Diagnostic outputs are
  local-only in `artifacts/scroll-audit/`.

## Signed installer and repository documentation — September 29

- Archived the current app in Release for arm64. Xcode exported it with the
  existing cloud-managed Developer ID Application certificate for Salty Panda
  LLC. A local keychain identity listing alone did not expose that certificate.
- Submitted the archive through Xcode's Developer ID upload path. Stapling and
  ticket validation succeeded; Gatekeeper reported `accepted` with
  `source=Notarized Developer ID`. The hardened runtime and microphone entitlement
  are present, and the exported bundle passes deep/strict signature validation.
- Created `dist/Teleprompter-1.0-arm64.dmg` (about 24 MB) with the app, an
  Applications shortcut, and install instructions. Disk-image verification and
  the SHA-256 checksum passed. Repeated signature, ticket, and Gatekeeper checks
  on the app mounted from the DMG; copied it out and confirmed the copied Release
  app launches. The image was then unmounted.
- Added a reproducible packaging script, Developer ID export options, a revised
  README, a generated repository banner, and separate development/packaging
  guides. Local documentation links resolve. No application source changed in
  this packaging update; the earlier 47-test passing result still applies.
- This verifies packaging and launch on this Mac. It does not close the Cap,
  recording-load, or lower-memory hardware checks below.

## Remaining live checks

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

## 2026-09-29: Local script library (1.1)

- My Scripts sidebar added with search, New, rename, duplicate, recoverable Trash,
  import as a new script, and named plain-text export. The welcome script is the
  initial saved selection. Existing settings carry over; the old draft file is
  retained and distinct text is recovered separately.
- Nine focused library tests passed, including atomic-write failure, unreadable
  and future-version protection, empty-library restore, independent positions,
  migration, and search. Full Swift test run: 57 discovered, 56 passed, one
  optional real Apple Speech fixture skipped.
- The integration executable used the real AppModel and NSTextView with temporary
  storage and silent speech doubles. All 20 assertions passed: save before switch,
  playback and gesture-resume cancellation, speech-start cancellation, import
  preservation, editor Undo isolation, failed-save retention, and relaunch.
- Xcode Debug build succeeded and the exact app bundle launched. The on-disk user
  library was confirmed to contain the default script; the original draft remains.
- Actual running app window captured and visually inspected: sidebar, search,
  New, selected welcome script, Trash, editor, and native sidebar-toggle toolbar
  rendered correctly. AppKit bitmap previews omit some native glass layers, so
  those previews were not treated as proof of rendering.
- One independent code review found no actionable issues. Actual recognition and
  Cap recording were not repeated for this library change; their earlier limits
  and remaining practical checks still apply.
- Release 1.1 (build 2) archived, exported with Salty Panda LLC Developer ID,
  notarized through the signed-in Xcode account, and stapled. The app mounted
  from `Teleprompter-1.1-arm64.dmg` passed strict signature verification,
  stapler validation, and Gatekeeper (`accepted`, `Notarized Developer ID`).
  The DMG checksum verified; SHA-256:
  `15a0cca2f06b44376e225d495342ebb940c5b2ed972f864a7d6c499a1a9202df`.
