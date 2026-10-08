import FluidAudio
import Foundation
import XCTest
@testable import BlitzRecorderApp

final class CompiledTranscriptionModelTests: XCTestCase {
    func testMissingWeightsInvalidateAnInstalledModel() throws {
        let store = try fixture()
        defer { try? FileManager.default.removeItem(at: store.rootDirectory) }
        XCTAssertTrue(store.isInstalled)
        try FileManager.default.removeItem(at: weightsURL(store))
        XCTAssertFalse(store.isInstalled)
        XCTAssertThrowsError(try store.validateParakeetModels()) { error in
            guard case LocalTranscriptionError.incompleteModel("weight.bin") = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRestoredWeightsMakeTheModelAvailableAgain() throws {
        let store = try fixture()
        defer { try? FileManager.default.removeItem(at: store.rootDirectory) }
        try FileManager.default.removeItem(at: weightsURL(store))
        XCTAssertFalse(store.isInstalled)
        try Data([1]).write(to: weightsURL(store))
        XCTAssertTrue(store.isInstalled)
        XCTAssertNoThrow(try store.validateParakeetModels())
    }

    func testEmptyWeightsAreRejected() throws {
        let store = try fixture()
        defer { try? FileManager.default.removeItem(at: store.rootDirectory) }
        try Data().write(to: weightsURL(store))
        XCTAssertFalse(store.isInstalled)
    }

    func testDirectoryInPlaceOfWeightsIsRejected() throws {
        let store = try fixture()
        defer { try? FileManager.default.removeItem(at: store.rootDirectory) }
        try FileManager.default.removeItem(at: weightsURL(store))
        try FileManager.default.createDirectory(at: weightsURL(store), withIntermediateDirectories: true)
        XCTAssertFalse(store.isInstalled)
    }

    func testMissingCoreMLMetadataIsRejected() throws {
        let store = try fixture()
        defer { try? FileManager.default.removeItem(at: store.rootDirectory) }
        let metadata = store.parakeetModelDirectory.appendingPathComponent("Decoder.mlmodelc/coremldata.bin")
        try FileManager.default.removeItem(at: metadata)
        XCTAssertFalse(store.isInstalled)
    }

    private func fixture() throws -> LocalTranscriptionModelStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = LocalTranscriptionModelStore(rootDirectory: root)
        for name in ModelNames.ASR.requiredModelsV3() {
            let model = store.parakeetModelDirectory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
            try Data([1]).write(to: model.appendingPathComponent("coremldata.bin"))
            try "program {}".write(to: model.appendingPathComponent("model.mil"), atomically: true, encoding: .utf8)
        }
        try FileManager.default.createDirectory(at: weightsURL(store).deletingLastPathComponent(),
                                               withIntermediateDirectories: true)
        try Data([1]).write(to: weightsURL(store))
        let program = #"BLOBFILE(path = tensor<string, []>("@model_path/weights/weight.bin"))"#
        try program.write(to: store.parakeetModelDirectory.appendingPathComponent("Encoder.mlmodelc/model.mil"),
                          atomically: true, encoding: .utf8)
        try Data("{}".utf8).write(to: store.parakeetModelDirectory.appendingPathComponent(ModelNames.ASR.vocabularyFile))
        try store.markInstalled()
        return store
    }

    private func weightsURL(_ store: LocalTranscriptionModelStore) -> URL {
        store.parakeetModelDirectory.appendingPathComponent("Encoder.mlmodelc/weights/weight.bin")
    }
}
