import Foundation

/// Keeps the model's own terms beside its downloaded files, including models
/// installed by older app versions. Never changes or removes model weights.
public enum ModelLicenses {
    public static var bundledFolder: URL? {
        #if SWIFT_PACKAGE
        let resources = Bundle.module.resourceURL
        #else
        let resources = Bundle.main.resourceURL
        #endif
        return resources?.appendingPathComponent("Licenses", isDirectory: true)
    }

    public static func install(for engine: VoiceEngine, besideModels destination: URL,
                               from licenses: URL? = bundledFolder) throws {
        let name: String
        switch engine {
        case .apple: return
        case .moonshine: name = "Moonshine"
        case .parakeet: name = "Parakeet"
        case .whisper: name = "Whisper"
        }
        guard let source = licenses?.appendingPathComponent("Models/\(name)", isDirectory: true),
              FileManager.default.fileExists(atPath: source.path) else {
            throw NSError(domain: "Teleprompter.Licenses", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The model's license documents are missing. Reinstall Teleprompter to restore them."
            ])
        }
        let target = destination.appendingPathComponent("Licenses", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for file in try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isRegularFileKey]) {
            guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let data = try Data(contentsOf: file)
            let output = target.appendingPathComponent(file.lastPathComponent)
            if (try? Data(contentsOf: output)) != data {
                try data.write(to: output, options: .atomic)
            }
        }
    }
}
