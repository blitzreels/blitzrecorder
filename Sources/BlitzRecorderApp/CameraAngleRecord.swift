import CoreGraphics
import CoreMedia
import Foundation

/// How one camera angle of a multicam project sits on the project timeline, and how that was found. Projects made
/// from files shot on several devices keep one record per angle; recorded takes keep none and place angles as before.
struct CameraAngleRecord: Codable, Equatable {
    enum SyncMethod: String, Codable {
        /// The angle the others were placed against.
        case reference
        /// Placed by comparing its sound with the reference.
        case audio
        /// Placed by hand.
        case manual
    }

    /// `camera` for Camera 1, `camera-2` and up for the other angles.
    let role: String
    /// What the person calls this angle, such as the speaker it frames or its file name.
    var title: String
    /// Seconds into the project timeline where the angle's first frame plays. Negative when it started earlier.
    var offsetSeconds: Double
    var method: SyncMethod
    /// 0 to 1 for audio sync; 1 for the reference and for manual placement.
    var confidence: Double
    /// How much faster the angle's clock runs, in seconds per second; 0 when the clocks agree.
    var drift: Double
    /// Where the framed person's face sits, as a fraction of the picture with the origin at the top left. Nil when
    /// no single face was found, as in a wide shot of several people.
    var face: CGRect?
    /// How many faces the angle usually shows: 2 or more for a wide shot.
    var faceCount: Int
    /// The upright picture's width over its height, so framing works without opening the file.
    var aspectRatio: Double

    enum CodingKeys: String, CodingKey {
        case role, title, offsetSeconds, method, confidence, drift, face, faceCount, aspectRatio
    }

    init(role: String, title: String, offsetSeconds: Double, method: SyncMethod, confidence: Double, drift: Double,
         face: CGRect?, faceCount: Int, aspectRatio: Double) {
        self.role = role
        self.title = title
        self.offsetSeconds = offsetSeconds
        self.method = method
        self.confidence = confidence
        self.drift = drift
        self.face = face
        self.faceCount = faceCount
        self.aspectRatio = aspectRatio
    }

    /// Records saved before the picture shape was kept assume the 16:9 every phone and pocket camera shoots.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
        title = try container.decode(String.self, forKey: .title)
        offsetSeconds = try container.decode(Double.self, forKey: .offsetSeconds)
        method = try container.decode(SyncMethod.self, forKey: .method)
        confidence = try container.decode(Double.self, forKey: .confidence)
        drift = try container.decode(Double.self, forKey: .drift)
        face = try container.decodeIfPresent(CGRect.self, forKey: .face)
        faceCount = try container.decode(Int.self, forKey: .faceCount)
        aspectRatio = try container.decodeIfPresent(Double.self, forKey: .aspectRatio) ?? 16.0 / 9.0
    }

    var timelineOffset: CMTime {
        CMTime(seconds: offsetSeconds, preferredTimescale: 600)
    }

    enum SyncStatus: Equatable {
        case reference
        case synced(confidence: Double)
        case speedsDiffer
        case checkSync
        case manual
    }

    var syncStatus: SyncStatus {
        switch method {
        case .reference: return .reference
        case .manual: return .manual
        case .audio:
            if abs(drift) > AngleAudioSync.Placement.driftLimit { return .speedsDiffer }
            return confidence >= 0.8 ? .synced(confidence: confidence) : .checkSync
        }
    }

    var needsReview: Bool {
        switch syncStatus {
        case .checkSync, .speedsDiffer: true
        case .reference, .synced, .manual: false
        }
    }

    /// Plain secondary text for the angle list.
    var syncStatusText: String {
        switch syncStatus {
        case .reference: "Sync reference"
        case .synced(let confidence): "Synced by audio · \(Int((confidence * 100).rounded())) %"
        case .speedsDiffer: "Check sync · speeds differ"
        case .checkSync: "Check sync"
        case .manual: "Placed by hand"
        }
    }
}

extension Array where Element == CameraAngleRecord {
    func record(role: String) -> CameraAngleRecord? {
        first { $0.role == role }
    }
}
