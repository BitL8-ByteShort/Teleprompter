import SwiftUI

struct ScriptWorkspaceView: View {
    @Bindable var model: AppModel
    @State private var columns: NavigationSplitViewVisibility = .all
    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            ScriptLibraryView(model: model)
        } detail: {
            EditorView(model: model)
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(item: $model.scriptToRename) { script in
            RenameScriptView(script: script, model: model)
        }
        .alert("Script library", isPresented: Binding(
            get: { model.libraryError != nil },
            set: { if !$0 { model.libraryError = nil } }
        )) {
            Button("OK") { model.libraryError = nil }
        } message: { Text(model.libraryError ?? "") }

    }
}
