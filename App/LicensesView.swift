import SwiftUI

struct LicensesView: View {
    @State private var selection = "LICENSE"
    private var files: [String] {
        guard let resources = Bundle.main.resourceURL else { return [] }
        let root = resources.appendingPathComponent("Licenses")
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        var result = ["LICENSE", "THIRD_PARTY_NOTICES.md"]
        while let file = enumerator?.nextObject() as? URL {
            guard file.pathExtension != "pdf", file.lastPathComponent != "manifest.json",
                  (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            result.append("Licenses/" + String(file.path.dropFirst(root.path.count + 1)))
        }
        return result.sorted()
    }
    private var contents: String {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent(selection),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "This document could not be opened. Reinstall Teleprompter to restore the license documents."
        }
        return text
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Licenses & Credits").font(.title2.bold())
            Text("Teleprompter is maintained by Salty Panda LLC. Libraries and models keep their own license terms.")
                .foregroundStyle(.secondary)
            Picker("Document", selection: $selection) {
                ForEach(files, id: \.self) { file in
                    Text(file.replacingOccurrences(of: "Licenses/", with: "")).tag(file)
                }
            }
            ScrollView {
                Text(contents).font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(24).frame(minWidth: 640, minHeight: 450)
    }
}
