extension SilenceEditingSession {
    enum Activity: Equatable {
        case analyzingAudio
        case analyzingSpeech
        case updatingSilences
        case preparingPreview
    }

    var activity: Activity? {
        if loading { return .analyzingAudio }
        if waitingForTranscript { return .analyzingSpeech }
        if calculating { return .updatingSilences }
        if preparingPreview { return .preparingPreview }
        return nil
    }

    var showsActionsFooter: Bool {
        activity != nil || !windows.isEmpty || hasRemovedSilence || error != nil
    }
}
