#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"
mkdir -p build/script-library
swiftc -parse-as-library -swift-version 6 Core/*.swift App/AppModel.swift App/ScriptEditor.swift App/EditorView.swift App/ScriptLibraryView.swift App/ScriptWorkspaceView.swift App/OverlayController.swift \
  script/LibraryIntegrationCheck/*.swift -o build/script-library/integration-check
build/script-library/integration-check "$@"
