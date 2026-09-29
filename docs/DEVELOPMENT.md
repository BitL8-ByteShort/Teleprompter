# Development

## Run from source


Requires an Apple Silicon Mac, macOS 26+, and Xcode 26+.

1. Open **Teleprompter.xcodeproj**.
2. Select the **Teleprompter** scheme and **My Mac**.
3. Press **⌘R**.

The project is configured for the existing Salty Panda Apple Development signing
team on Chris's Mac. On another Mac, select your own team or **Sign to Run Locally**
in Signing & Capabilities. Xcode resolves the pinned MoonshineVoice, FluidAudio,
and WhisperKit packages automatically. Speech models are optional downloads in
the app; they are not bundled with the source or app.

The Codex **Run** action and this command build and launch the same app:

```sh
./script/build_and_run.sh --verify
```

Optional script modes: `--debug`, `--logs`, and `--telemetry`.
The local app bundle is `build/Build/Products/Debug/Teleprompter.app`.

## Tests and diagnostics


```sh
swift test
```

The focused suite covers timing, countdowns, pause/resume, finish behavior,
paragraph navigation, speech matching (including long cumulative transcripts),
model-selection persistence, bounded Whisper audio windows, local recovery,
and notch placement.
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

To exercise the actual downloadable engines without microphone or speaker use:

```sh
swift build --product VoiceEngineCheck
ffmpeg -i artifacts/voice-fixture.caf -ar 16000 -ac 1 artifacts/voice-fixture-16k.wav
.build/debug/VoiceEngineCheck moonshine artifacts/voice-fixture-16k.wav --download
.build/debug/VoiceEngineCheck parakeet artifacts/voice-fixture-16k.wav --download
.build/debug/VoiceEngineCheck whisper artifacts/voice-fixture-16k.wav --download
```

Omit `--download` to use only the already-installed model. The harness prints
partial and final transcripts, streams at real-time speed, and flushes trailing
silence. Add `--retake` to verify a second take after suspending and resetting
recognition with the same loaded model. It uses the same backends as the app. Fixture accuracy
and this Mac's timings are not measurements on an 8 GB Mac or proof of Cap
recording performance.

`Core/` contains the shared timing, matching, placement, and persistence logic.
`App/` owns the SwiftUI editor, nonactivating AppKit panel, global shortcuts,
and microphone/recognition lifecycle. `Speech/` implements local model downloads
and the three optional engines. No microphone input is started by tests.

After adding a Swift source file, regenerate the checked-in Xcode project with
`python3 script/generate_project.py`. The generator requires only Python's
standard library.

Library storage: `~/Library/Application Support/Teleprompter/library.json`.
It contains script IDs, titles, text, fractional word positions, timestamps,
Trash, active selection, and shared settings. Version 1 is written atomically.
The legacy `draft.json` stays untouched. Migration seeds the welcome script and
keeps distinct existing text as a separate Recovered draft.
Model storage: `~/Library/Application Support/Teleprompter/Models/`.
Incomplete downloads are not offered for selection; retry **Download** after a
failure or cancellation. Download receipts check that installed files remain
present and complete before use.
Unreadable or newer library versions block autosave instead of replacing user
data. Failed transactions retain the current in-memory library; the editor
keeps its unsaved text and blocks selection changes until saving works again.
Generated media and build outputs are ignored by Git.

`./script/check_library_integration.sh` compiles the real AppModel and AppKit
editor with silent speech doubles and temporary storage. It checks saving on
switch, playback/manual-resume cancellation, cancellation during speech startup,
import as a new script, cross-script Undo isolation, failed writes, and relaunch.
It does not test actual speech recognition. Add `--snapshot` to render the real
SwiftUI workspace to `build/script-library/library-preview.png`.

See [validation notes](VALIDATION.md) for verified behavior and outstanding
live recording checks.


AppKit bitmap previews can omit native glass/sidebar layers. Inspect the actual
running window when checking appearance; a white region in the bitmap alone
isn't evidence of a missing control.
