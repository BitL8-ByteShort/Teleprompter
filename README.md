# Teleprompter

A native Mac teleprompter for YouTube recording. The reading panel sits below the
MacBook camera, with adjustable auto-scroll and on-device voice-follow. Cap (or
your preferred recorder) records the video separately.

## Run

Requires an Apple Silicon Mac, macOS 26+, and Xcode 26+.

1. Open **Teleprompter.xcodeproj**.
2. Select the **Teleprompter** scheme and **My Mac**.
3. Press **⌘R**.

The project is configured for the existing Salty Panda Apple Development signing
team on Chris's Mac. On another Mac, select your own team or **Sign to Run Locally**
in Signing & Capabilities. No third-party libraries or package installation is needed.

The Codex **Run** action and this command build and launch the same app:

```sh
./script/build_and_run.sh --verify
```

Optional script modes: `--debug`, `--logs`, and `--telemetry`.
The local app bundle is `build/Build/Products/Debug/Teleprompter.app`.

## Read a script

- Paste or import a UTF-8 `.txt` script in the editor. The draft, reading position,
  microphone, shortcuts, and panel settings save automatically on this Mac.
- Choose **Auto-scroll** (60–240 WPM) or **Voice-follow**, then **Start reading**.
  Both modes include a three-second countdown.
- Start with the default 36-point text, 460-point width, and three visible lines.
  Adjust while sitting or standing at your actual 2–4-foot recording distance.
- Choose **Left**, **Center**, or **Right** under **Reading Panel → Text alignment**.
  Changes apply immediately and are remembered between launches.
- Click a line in the panel to resume there after a countdown. In the editor, place the
  cursor and choose **Read from cursor**. Previous/next paragraph and Restart
  support retakes. Paragraph navigation pauses; press Play to continue.
- Hover over the panel for controls. Hide pauses playback; the same panel window
  is reused when shown again. Closing the editor pauses playback; its menu-bar
  icon can reopen it. Quitting stops microphone capture.
- Resizing the text or panel preserves the current word. The panel tracks the
  built-in display even when an external monitor is primary. An open MacBook
  display is required.

Default global shortcuts (customize under **Keyboard shortcuts**):

| Action | Shortcut |
| --- | --- |
| Play / pause | ⌥⌘P |
| Previous paragraph | ⌥⌘← |
| Next paragraph | ⌥⌘→ |
| Restart | ⌥⌘R |
| Show / hide panel | ⌥⌘H |

Conflicting shortcuts are reported in the editor. Use a different combination if
another app already owns one. Capturing a shortcut requires Command or Control;
Escape cancels.

## Voice-follow

Select the microphone you speak into, then start reading. macOS asks for
microphone access on first use. If denied, enable Teleprompter under
**System Settings → Privacy & Security → Microphone**.

Recognition uses Apple's `SpeechAnalyzer` and `SpeechTranscriber`, with English
(US) as the language. Required speech assets download from Apple when missing;
recognition runs on device after setup. Microphone audio is never saved by
Teleprompter. There is no account, cloud transcription, or camera permission.
Live prompting uses Apple's faster partial results to reduce recognition delay.
The text still needs a confident nearby match before it moves.

The matcher compares nearby script words, tolerates small omissions, and handles
revised partial transcripts. Two exact words near your current position can
start movement; longer or fuzzy matches require more evidence. Recognized words
move the panel continuously through each line, with gradual acceleration and
deceleration. A delayed batch cannot snap it several lines ahead. It holds
during silence, unrelated ad-libs, or
uncertain matches. It does not jump across the whole script looking for a phrase.
When you return from an ad-lib, a nearby exact three-word suffix can rejoin the
script without waiting for the ad-lib to disappear from the transcript.
Routine microphone configuration notifications keep a working input running;
if the audio engine stops or its format changes, the app rebuilds the input
without resetting your reading position.
For a large skip or retake, move to the intended line and resume. If the microphone
disconnects or recognition fails, playback pauses without discarding your place;
**Use auto-scroll** is available in the editor.

## Keep the panel out of Cap recordings

1. Launch Teleprompter and **show the reading panel before recording**.
2. In Cap 0.6.0, open **Settings → General → Excluded windows**.
3. Add **Teleprompter**. Its stable bundle identifier is
   `com.bitl8byteshort.Teleprompter`; Cap can match all visible windows belonging
   to the app.
4. Start a short **Studio** recording with the screen, built-in camera, and your
   microphone. Inspect the saved recording before a full take.
5. Keep Teleprompter running during the take. If it is restarted, start a new
   Cap recording so Cap can resolve the new window IDs.

This setting belongs to Cap. Teleprompter cannot guarantee invisibility in every
recorder. Cap's bundled CLI has a separate recording path; its capture options
do not expose the desktop app's excluded-window setting, so use the **Cap desktop
app** to verify exclusion.

For **OBS**, use a capture source that excludes Teleprompter (for example, a
specific demonstrated app/window), and inspect a sample. For **macOS capture**,
record the external display or a selected area below the panel. Match the
microphone choice in your recorder and Teleprompter, and test simultaneous access.

## Test and develop

```sh
swift test
```

The focused suite covers timing, countdowns, pause/resume, finish behavior,
paragraph navigation, speech matching, local recovery, and notch placement.
An optional integration test runs real on-device recognition against generated
speech (it may download Apple's English assets):

```sh
mkdir -p artifacts
say -v Samantha -o artifacts/voice-fixture.caf 'Today we are building a native teleprompter application for recording YouTube videos. Keep your eyes near the camera and speak at your own pace.'
TELEPROMPTER_SPEECH_FIXTURE="$PWD/artifacts/voice-fixture.caf" swift test
```

To compare default and fast recognition using the same fixture streamed at
real-time speed (no microphone or speaker playback):

```sh
afconvert -f caff -d LEI16@16000 artifacts/voice-fixture.caf artifacts/voice-fixture-16k.caf
swiftc Core/Script.swift Core/SpeechAlignment.swift script/benchmark_speech.swift -o artifacts/benchmark_speech
artifacts/benchmark_speech artifacts/voice-fixture-16k.caf
```

`Core/` contains the shared timing, matching, placement, and persistence logic.
`App/` owns the SwiftUI editor, nonactivating AppKit panel, global shortcuts,
and microphone/recognition lifecycle. No microphone input is started by tests.

After adding a Swift source file, regenerate the checked-in Xcode project with
`python3 script/generate_project.py`. The generator requires only Python's
standard library.

Draft storage: `~/Library/Application Support/Teleprompter/draft.json`.
Unreadable drafts are backed up before new autosaves; if backup fails, autosave
is suspended and the editor offers export. Generated media and build outputs
are ignored by Git.

See [validation notes](docs/VALIDATION.md) for verified behavior and outstanding
live recording checks.
