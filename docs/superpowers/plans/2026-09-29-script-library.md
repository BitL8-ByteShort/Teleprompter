# Script Library Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this approved plan in this session. Steps use checkbox syntax for tracking.

**Goal:** Save and reopen named scripts from a local sidebar without losing edits or reading positions.

**Architecture:** A Codable library owns stable script IDs, text, positions, timestamps, Trash, last selection, and global settings. Atomic store transactions commit before navigation changes. AppModel continues owning playback and speech; a native sidebar selects scripts in the existing editor.

**Tech Stack:** Swift 6, SwiftUI/AppKit, macOS 26, Foundation JSON storage, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-29-script-library.md`

## Global Constraints

- Local only; no accounts or cloud sync.
- Default welcome script is the first selected saved script.
- Preserve the original draft file and recover distinct draft text into a separate script.
- Switching saves edits and pauses playback; reading settings remain global.
- Keep the repository private and refresh the installable app.

## Review Focus

- Failed writes must leave the current script and unsaved edits in place.
- Corrupt or future library files must not be silently overwritten.
- Deleting the last script must leave an understandable empty state and allow restoration.
- Switching scripts must clear editor undo history and invalidate speech/manual-scroll work.
- Importing must create a script, never overwrite the open one.

### Task 1: Library and persistence

**Files:** Create `Core/ScriptLibrary.swift`, `Core/ScriptLibraryStore.swift`, `Tests/ScriptLibraryTests.swift`.

**Interfaces:** `SavedScript` contains UUID, title, text, position, dates; `ScriptLibrary` exposes activeScript, matching(query:trashed:), create/select/rename/duplicate/trash/restore. `ScriptLibraryStore.loadOrCreate(defaultText:)` migrates once; `update(_:change:)` commits a candidate before replacing in-memory state.

- [ ] Add tests for default seed/migration, independent positions and relaunch, search, duplicate/rename, Trash/restore/empty state, write failure, unreadable/future data.
- [ ] Run `swift test --filter ScriptLibraryTests`, observe missing-library compile failure.
- [ ] Implement value operations and atomic validated storage; preserve legacy draft untouched.
- [ ] Run focused tests; require all pass. Commit core changes.

### Task 2: Editor integration

**Files:** Modify `App/AppModel.swift`, `App/EditorView.swift`, `App/ScriptEditor.swift`, `App/TeleprompterApp.swift`; create `App/ScriptLibraryView.swift`; regenerate Xcode project.

**Interfaces:** AppModel exposes library actions. Selection saves and stops playback before loading text/position; failed saves block navigation. ScriptEditor resets selection, scroll, and undo on ID change. New/import/duplicate select the created script; restore returns it to My Scripts.

- [ ] Replace single-draft autosave with library transactions and per-script position restoration.
- [ ] Add collapsible sidebar with title/text search, New, context actions, rename sheet, and recoverable Trash.
- [ ] Add empty editor state, active title, named exports, and import-as-new; retain existing playback/settings controls.
- [ ] Build app and verify launch; run full Swift tests once after integration. Inspect selection and undo paths. Commit integration.

### Task 3: Deliver

**Files:** Update `README.md`, `docs/DEVELOPMENT.md`, `docs/VALIDATION.md`, `App/Info.plist`; refine `script/build_and_run.sh` to target only this bundle.

- [ ] Document library, migration, and storage; increment version to 1.1 (build 2).
- [ ] Review complete diff with one independent reviewer; fix substantive findings and rerun affected checks.
- [ ] Package/sign/notarize app with existing `script/package_dmg.sh`, verify Gatekeeper and DMG.
- [ ] Commit, merge into main, push, and publish a private prerelease with DMG/checksum. Verify repository remains private.
