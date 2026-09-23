import CoreMedia
import Foundation
import BlitzRecorderDomain

extension MediaTime {
    init(_ time: CMTime) {
        let converted = time.isValid
            ? CMTimeConvertScale(time, timescale: MediaTime.timescale, method: .roundHalfAwayFromZero)
            : .zero
        self.init(value: converted.value, timescale: converted.timescale)
    }

    var cmTime: CMTime {
        CMTime(value: value, timescale: CMTimeScale(MediaTime.timescale))
    }
}

extension TimelineTimeMap {
    init(takeDuration: CMTime, cuts: [TimelineCut], playbackRate: Double = 1.0) {
        self.init(takeDuration: MediaTime(takeDuration), cuts: cuts, playbackRate: playbackRate)
    }

    static func identity(takeDuration: CMTime) -> TimelineTimeMap {
        identity(takeDuration: MediaTime(takeDuration))
    }

    static func time(_ seconds: TimeInterval) -> CMTime {
        guard seconds.isFinite else { return .zero }
        return MediaTime(seconds: max(0, seconds)).cmTime
    }

    func outputTime(forTake takeTime: CMTime) -> CMTime {
        outputTime(forTake: MediaTime(takeTime)).cmTime
    }

    func takeTime(forOutput outputTime: CMTime) -> CMTime {
        takeTime(forOutput: MediaTime(outputTime)).cmTime
    }

    func keptRange(containingOutput outputTime: CMTime) -> KeptRange? {
        keptRange(containingOutput: MediaTime(outputTime))
    }
}

extension TimelineMediaInsertionRequest {
    init(activeTakeStart: CMTime, sourceTimeAtActiveStart: CMTime, sourceEnd: CMTime) {
        self.init(
            activeTakeStart: MediaTime(activeTakeStart),
            sourceTimeAtActiveStart: MediaTime(sourceTimeAtActiveStart),
            sourceEnd: MediaTime(sourceEnd)
        )
    }
}
