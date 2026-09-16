import Foundation

enum EditorAssetTracks {
    struct Item: Equatable {
        let id: String
        let kind: EditorAsset.Kind
    }

    struct Request {
        let assets: [Item]
        let hiddenKinds: Set<SceneLayerKind>
        let hideableKinds: Set<SceneLayerKind>
        let mutedSources: Set<CaptureSource>
        let muteableSources: Set<CaptureSource>
    }

    struct Snapshot: Equatable {
        var hiddenIDs: Set<String> = []
        var mutedIDs: Set<String> = []
        var toggleableIDs: Set<String> = []
    }

    static func layerKind(_ kind: EditorAsset.Kind) -> SceneLayerKind? {
        switch kind {
        case .screen: return .screen
        case .camera: return .camera
        case .output, .microphone, .systemAudio, .other: return nil
        }
    }

    static func audioSource(_ kind: EditorAsset.Kind) -> CaptureSource? {
        switch kind {
        case .microphone: return .microphone
        case .systemAudio: return .systemAudio
        case .output, .screen, .camera, .other: return nil
        }
    }

    static func snapshot(_ request: Request) -> Snapshot {
        let visibleVideoCount = request.hideableKinds.subtracting(request.hiddenKinds).count
        var snapshot = Snapshot()
        for asset in request.assets {
            if let kind = layerKind(asset.kind) {
                if request.hiddenKinds.contains(kind) {
                    snapshot.hiddenIDs.insert(asset.id)
                }
                if request.hideableKinds.contains(kind),
                   request.hiddenKinds.contains(kind) || visibleVideoCount > 1 {
                    snapshot.toggleableIDs.insert(asset.id)
                }
            } else if let source = audioSource(asset.kind) {
                if request.mutedSources.contains(source) {
                    snapshot.mutedIDs.insert(asset.id)
                }
                if request.muteableSources.contains(source) {
                    snapshot.toggleableIDs.insert(asset.id)
                }
            }
        }
        return snapshot
    }
}
