import SwiftUI

struct VoiceDiscoverySection: View {
    let discovery: VoiceDiscoveryModel
    let player: SpeakersSettingsModel
    let openRecording: (RecordingProjectHistory.Entry) -> Void
    @State private var naming: DetectedVoice?
    @State private var name = ""
    @State private var destination = Destination.newSpeaker

    private enum Destination: Hashable {
        case newSpeaker
        case saved(UUID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let update = discovery.update {
                scanStatus(update)
                if !update.failures.isEmpty {
                    DisclosureGroup("\(update.failures.count) recordings could not be checked") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(update.failures) { failure in
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(failure.project.displayTitle).font(BlitzType.label)
                                        Text(failure.message).font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                                    }
                                    Spacer(minLength: 0)
                                    Button("Open recording") { openRecording(failure.project) }
                                        .blitzButton(.quiet).controlSize(.small)
                                }
                            }
                        }
                        .padding(.top, 10)
                    }
                    .font(BlitzType.body)
                    .foregroundStyle(BlitzUI.secondaryText)
                }
                if !discovery.voices.isEmpty {
                    LazyVStack(spacing: 0) {
                        ForEach(discovery.voices) { candidate in
                            if candidate.id != discovery.voices.first?.id { SettingsRowDivider() }
                            candidateRow(candidate)
                        }
                    }
                    .settingsSection(.init(
                        title: "Voices to review · \(discovery.voices.count)",
                        detail: "Listen, then assign a saved speaker or create a new one.", systemImage: "person.wave.2"
                    ))
                }
            } else {
                Text("Detect voices in your recordings to find speakers you haven’t saved yet.")
                    .font(BlitzType.body).foregroundStyle(BlitzUI.secondaryText).settingsSurface()
            }
            if let message = discovery.errorMessage {
                Text(message).font(BlitzType.body).foregroundStyle(BlitzUI.warning)
            }
        }
    }

    private func scanStatus(_ update: VoiceDiscoveryScanner.Update) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(discovery.isScanning ? (discovery.isStopping ? "Stopping scan…" : "Detecting voices…")
                         : discovery.wasCancelled ? "Scan stopped" : "Scan complete")
                        .font(BlitzType.section)
                    Text("\(update.checked - update.failures.count) of \(update.total) recordings checked · \(update.index.knownCount) saved voice matches")
                        .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                }
                Spacer(minLength: 0)
                if discovery.isScanning {
                    Button("Cancel", action: discovery.cancel)
                        .blitzButton(.secondary).controlSize(.small)
                        .disabled(discovery.isStopping)
                }
            }
            if discovery.isScanning {
                ProgressView(value: Double(update.checked), total: Double(max(update.total, 1))).tint(BlitzUI.mint)
                if let title = update.currentTitle {
                    Text(title).font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText).lineLimit(1)
                }
            } else if discovery.voices.isEmpty {
                Text("No unsaved voices to review in the recordings checked.")
                    .font(BlitzType.body).foregroundStyle(BlitzUI.secondaryText)
            }
            if update.index.insufficientCount > 0 {
                Text("\(update.index.insufficientCount) voices had too little clear speech for a reliable sample.")
                    .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
            }
        }
        .settingsSurface()
    }

    private func candidateRow(_ candidate: DetectedVoice) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(candidate.title).font(BlitzType.section)
                Text(discovery.sampleErrors[candidate.id] ?? (candidate.recordingCount == 1 ? candidate.reference.project.displayTitle
                     : "\(candidate.recordingCount) recordings · \(candidate.reference.project.displayTitle)"))
                    .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Task { await player.toggleSample(.init(id: candidate.id, loadURL: { try await discovery.sampleURL(candidate) })) }
            } label: {
                Label(discovery.preparingIDs.contains(candidate.id) ? "Loading…" : player.playingID == candidate.id ? "Stop" : "Listen",
                      systemImage: player.playingID == candidate.id ? "stop.fill" : "play.fill")
            }
            .blitzButton(.secondary).controlSize(.small)
            .disabled(discovery.preparingIDs.contains(candidate.id))
            .accessibilityLabel("\(player.playingID == candidate.id ? "Stop" : "Listen to") \(candidate.title)")
            BlitzGlassMenu(entries: assignmentActions(candidate), menuWidth: 240) {
                HStack(spacing: 6) {
                    Text("Assign speaker")
                    BlitzMenuChevron()
                }
                .padding(.horizontal, 10)
                .frame(height: BlitzControlMetrics.height(.small))
            }
            .controlSize(.small)
            .accessibilityLabel("Assign speaker to \(candidate.title)")
            .disabled(discovery.isScanning || discovery.isSaving || discovery.preparingIDs.contains(candidate.id))
            .popover(isPresented: Binding(get: { naming?.id == candidate.id }, set: { if !$0 { naming = nil } })) {
                namingEditor(candidate)
            }
            BlitzOverflowMenu(configuration: .init(
                entries: [
                    .item(.init(title: "Open recording", systemImage: "film", action: { openRecording(candidate.reference.project) })),
                    .item(.init(title: "Dismiss for now", systemImage: "xmark", action: {
                        if player.playingID == candidate.id { player.stop() }
                        discovery.dismiss(candidate.id)
                    }))
                ],
                menuWidth: 210,
                placement: .inline,
                isBusy: false,
                accessibilityLabel: "Actions for \(candidate.title)",
                help: "Open the recording or dismiss this voice"
            ))
            .controlSize(.small)
        }
        .settingsRow()
    }

    private func assignmentActions(_ candidate: DetectedVoice) -> [BlitzMenuEntry] {
        var entries: [BlitzMenuEntry] = []
        if !player.profiles.isEmpty {
            entries.append(.section("Assign to saved speaker"))
            entries += player.profiles.map { profile in
                .item(.init(title: profile.name, systemImage: "person", action: {
                    name = profile.name
                    destination = .saved(profile.id)
                    naming = candidate
                }))
            }
            entries.append(.divider)
        }
        entries.append(.item(.init(title: "New speaker…", systemImage: "plus", action: {
            name = candidate.nameHint
            destination = .newSpeaker
            naming = candidate
        })))
        return entries
    }

    private func namingEditor(_ candidate: DetectedVoice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(destination == .newSpeaker ? "New speaker" : "Assign to \(name)?")
                .font(BlitzType.section)
            if destination == .newSpeaker {
                TextField("Speaker’s name", text: $name)
                    .textFieldStyle(.plain).font(BlitzType.body)
                    .padding(.horizontal, 10)
                    .frame(height: BlitzControlMetrics.height(.regular))
                    .background(BlitzUI.controlFill, in: .rect(cornerRadius: BlitzControlMetrics.radius))
            }
            Text(destination == .newSpeaker
                 ? "Saves this sample as a new voice for future name suggestions."
                 : "Adds this sample to \(name)’s saved voice for future name suggestions.")
                .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let message = discovery.errorMessage {
                Text(message).font(BlitzType.caption).foregroundStyle(BlitzUI.warning)
            }
            HStack {
                Spacer()
                Button("Cancel") { naming = nil }.blitzButton(.secondary).keyboardShortcut(.cancelAction)
                Button(discovery.isSaving ? "Saving…" : destination == .newSpeaker ? "Save speaker" : "Assign voice") { save(candidate) }
                    .blitzButton(.accent).keyboardShortcut(.defaultAction)
                    .disabled(discovery.isSaving || !validName)
            }
        }
        .padding(16).frame(width: 340).background(BlitzUI.panelBackground)
    }

    private var validName: Bool {
        if case .saved = destination { return true }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "You"
    }

    private func save(_ candidate: DetectedVoice) {
        guard validName, !discovery.isSaving else { return }
        let profileID: UUID?
        if case .saved(let id) = destination { profileID = id } else { profileID = nil }
        Task {
            if await discovery.save(.init(candidate: candidate, name: name, profileID: profileID)) {
                player.stop()
                naming = nil
                await player.refreshProfiles()
            }
        }
    }
}
