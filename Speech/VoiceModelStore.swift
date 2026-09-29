import Foundation
import FluidAudio
@preconcurrency import MoonshineVoice
@preconcurrency import WhisperKit
#if canImport(TeleprompterCore)
import TeleprompterCore
#endif

public enum VoiceModelStore {
    private struct Receipt: Codable {
        let files: [String: Int]
    }

    public static func folder(_ engine: VoiceEngine) -> URL {
        VoiceBackends.modelDirectory.appendingPathComponent(engine.rawValue, isDirectory: true)
    }

    public static func isDownloaded(_ engine: VoiceEngine) -> Bool {
        if engine == .apple { return true }
        let root = folder(engine)
        guard let data = try? Data(contentsOf: root.appendingPathComponent("ready.json")),
              let receipt = try? JSONDecoder().decode(Receipt.self, from: data), !receipt.files.isEmpty else { return false }
        return receipt.files.allSatisfy { path, size in
            let attributes = try? FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(path).path)
            return (attributes?[.size] as? Int) == size
        }
    }

    public static func requireDownloaded(_ engine: VoiceEngine) throws {
        guard isDownloaded(engine) else {
            throw NSError(domain: "Teleprompter.Models", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Download \(engine.title) in Transcription models first, or select Apple Speech."])
        }
        try ModelLicenses.install(for: engine, besideModels: folder(engine))
    }

    /// Downloads only files and the small tokenizer; does not load a recognition
    /// model, open the microphone, or change the selected engine.
    public static func download(_ engine: VoiceEngine, progress: @escaping @Sendable (String) -> Void) async throws {
        let root = folder(engine)
        try ModelLicenses.install(for: engine, besideModels: root)
        switch engine {
        case .apple: return
        case .moonshine:
            try await AssetDownloader(timeout: 600).ensureModelPresent(root: root,
                spec: .stt(language: "en", modelArch: .smallStreaming)) { update in
                let percent = update.bytesTotal > 0 ? " · \(Int(100 * update.bytesDownloaded / update.bytesTotal))%" : ""
                progress("File \(update.fileIndex)/\(update.totalFiles)\(percent)")
            }
        case .parakeet:
            try await ModelHub.download(.parakeetEou320, to: root) { update in
                progress("\(Int(update.fractionCompleted * 100))%")
            }
        case .whisper:
            let modelFolder = try await WhisperKit.download(variant: "openai_whisper-large-v3-v20240930_626MB", downloadBase: root) { update in
                progress("\(Int(update.fractionCompleted * 100))%")
            }
            progress("Preparing tokenizer…")
            _ = try await ModelUtilities.loadTokenizer(for: .largev3, tokenizerFolder: root, additionalSearchPaths: [modelFolder])
            let path = String(modelFolder.path.dropFirst(root.path.count + 1))
            try path.write(to: root.appendingPathComponent("model-path.txt"), atomically: true, encoding: .utf8)
        }
        try Task.checkCancellation()
        // A receipt is committed only after the complete download succeeds. File
        // sizes detect removed/truncated assets on the next launch.
        var files: [String: Int] = [:]
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
        while let url = enumerator?.nextObject() as? URL {
            // License updates must not make intact weights appear missing.
            if url == root.appendingPathComponent("Licenses", isDirectory: true) {
                enumerator?.skipDescendants()
                continue
            }
            guard url.lastPathComponent != "ready.json" else { continue }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true, let size = values.fileSize {
                files[String(url.path.dropFirst(root.path.count + 1))] = size
            }
        }
        try JSONEncoder().encode(Receipt(files: files)).write(to: root.appendingPathComponent("ready.json"), options: .atomic)
    }
}
