import Foundation

@MainActor
final class TranscriptSpeakerUndo {
    static let shared = TranscriptSpeakerUndo()
    static let didChange = Notification.Name("TranscriptSpeakerDidChange")

    struct Change {
        let locations: TranscriptArtifactStore.Locations
        let before: RecordingTranscript.Speaker
        let after: RecordingTranscript.Speaker
        weak var manager: UndoManager?
        let isAvailable: () -> Bool
        let onError: (Error) -> Void
    }

    func register(_ change: Change) {
        guard let manager = change.manager else { return }
        manager.registerUndo(withTarget: self) { target in target.apply(change) }
        manager.setActionName("Rename speaker")
    }

    private func apply(_ change: Change) {
        do {
            guard change.isAvailable() else { throw LocalTranscriptionError.transcriptBusy }
            let store = TranscriptArtifactStore()
            var transcript = try store.load(from: change.locations.jsonURL)
            guard let index = transcript.speakers.firstIndex(where: { $0 == change.after }) else {
                throw LocalTranscriptionError.transcriptBusy
            }
            transcript.speakers[index] = change.before
            try store.save(.init(transcript: transcript, locations: change.locations))
            register(.init(locations: change.locations, before: change.after, after: change.before,
                           manager: change.manager, isAvailable: change.isAvailable, onError: change.onError))
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        } catch {
            change.onError(error)
        }
    }
}
