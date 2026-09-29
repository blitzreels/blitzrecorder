import Foundation

struct CaptureStopProgress: Equatable {
    enum Phase: Equatable {
        case closingTracks
        case synchronizingAudio
    }

    let phase: Phase
    let completed: Int
    let total: Int
    let pendingSources: [CaptureSource]
    var synchronizationProgress: Double? = nil

    var title: String {
        phase == .closingTracks ? "Saving tracks" : "Synchronizing audio"
    }

    var detail: String {
        switch phase {
        case .closingTracks:
            pendingSources.isEmpty ? "Tracks processed" : pendingSources.map(\.rawValue).joined(separator: " · ")
        case .synchronizingAudio:
            "Keeping your microphone aligned with the video"
        }
    }

    var fraction: Double? {
        if phase == .synchronizingAudio { return synchronizationProgress }
        guard phase == .closingTracks, total > 0 else { return nil }
        return Double(completed) / Double(total)
    }

    var label: String {
        if phase == .closingTracks { return "\(completed)/\(total) tracks" }
        guard let synchronizationProgress else { return "" }
        return "\(Int(synchronizationProgress * 100))%"
    }
}
