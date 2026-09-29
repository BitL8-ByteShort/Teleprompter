import SwiftUI

struct ScriptLibraryView: View {
    @Bindable var model: AppModel
    @State private var query = ""
    @State private var showTrash = false

    private var results: [SavedScript] { model.library.matching(query: query) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("My Scripts").font(.headline)
                Spacer()
                Button("New script", systemImage: "plus") {
                    query = ""
                    model.newScript()
                }.labelStyle(.iconOnly).help("New script (⌘N)")
            }.padding()
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search scripts", text: $query).textFieldStyle(.plain)
                if !query.isEmpty {
                    Button("Clear search", systemImage: "xmark.circle.fill") { query = "" }
                        .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }.padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal).padding(.bottom, 8)
            List(selection: Binding<UUID?>(get: { model.library.activeID }, set: { id in
                if let id { model.selectScript(id) }
            })) {
                ForEach(results) { script in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(script.title).font(.body.weight(.medium)).lineLimit(1)
                        Text(script.preview).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .padding(.vertical, 4)
                    .tag(script.id)
                    .contextMenu {
                        Button("Rename…") { model.scriptToRename = script }
                        Button("Duplicate") { model.duplicateScript(script.id) }
                        Divider()
                        Button("Move to Trash", role: .destructive) { model.trashScript(script.id) }
                    }
                }
            }.listStyle(.sidebar)
                .overlay {
                    if results.isEmpty {
                        Text(query.isEmpty ? "Your saved scripts appear here." : "No matching scripts")
                            .font(.callout).foregroundStyle(.secondary).padding().allowsHitTesting(false)
                    }
                }
            Divider()
            HStack {
                Button("Trash", systemImage: "trash") { showTrash = true }.buttonStyle(.plain)
                Spacer()
                Text("\(model.library.matching(query: "", trashed: true).count)")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding()
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 235, max: 320)
        .sheet(isPresented: $showTrash) { ScriptTrashView(model: model) }
    }
}

struct RenameScriptView: View {
    let script: SavedScript
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @FocusState private var focused: Bool

    init(script: SavedScript, model: AppModel) {
        self.script = script
        self.model = model
        _title = State(initialValue: script.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename script").font(.title2.weight(.semibold))
            TextField("Script name", text: $title).textFieldStyle(.roundedBorder).focused($focused)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    model.renameScript(script.id, title: title)
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 360).onAppear { focused = true }
    }
}

private struct ScriptTrashView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    private var scripts: [SavedScript] { model.library.matching(query: "", trashed: true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Trash").font(.title2.weight(.semibold))
            Text("Restore a script to put it back in My Scripts.").foregroundStyle(.secondary)
            List(scripts) { script in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(script.title).fontWeight(.medium).lineLimit(1)
                        Text(script.preview).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button("Restore") { model.restoreScript(script.id) }
                }.padding(.vertical, 4)
            }.overlay {
                if scripts.isEmpty { ContentUnavailableView("Trash is empty", systemImage: "trash") }
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 500, height: 390)
    }
}
