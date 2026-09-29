import Foundation
import Testing
@testable import TeleprompterCore

struct ModelLicensesTests {
    @Test func optionalModelsReceiveCompleteTermsWithoutChangingWeights() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = try #require(ModelLicenses.bundledFolder)
        for (engine, group) in [(VoiceEngine.moonshine, "Moonshine"), (.parakeet, "Parakeet"), (.whisper, "Whisper")] {
            let destination = root.appendingPathComponent(engine.rawValue)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let weights = destination.appendingPathComponent("weights.bin")
            let receipt = destination.appendingPathComponent("ready.json")
            let original = Data([1, 2, 3, 4])
            try original.write(to: weights)
            try Data("existing receipt".utf8).write(to: receipt)
            try ModelLicenses.install(for: engine, besideModels: destination)
            try ModelLicenses.install(for: engine, besideModels: destination)
            for source in try FileManager.default.contentsOfDirectory(at: bundled.appendingPathComponent("Models/\(group)"), includingPropertiesForKeys: nil) {
                #expect(try Data(contentsOf: destination.appendingPathComponent("Licenses/\(source.lastPathComponent)")) == Data(contentsOf: source))
            }
            #expect(try Data(contentsOf: weights) == original)
            #expect(try String(contentsOf: receipt, encoding: .utf8) == "existing receipt")
        }
    }

    @Test func missingTermsStopOptionalInstallationButAppleNeedsNoDownload() throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(throws: (any Error).self) {
            try ModelLicenses.install(for: .parakeet, besideModels: destination, from: nil)
        }
        try ModelLicenses.install(for: .apple, besideModels: destination, from: nil)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}
