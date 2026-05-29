import SwiftUI

struct RecordingSettingsPage: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Export")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Text("Final video quality, file type, and save location.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }

            VStack(alignment: .leading, spacing: 16) {
                RecordingSettingsControls(vm: vm)
            }
            .padding(20)
            .frame(width: 520, alignment: .leading)
            .blitzGlassSurface(cornerRadius: 16)

            RecordingStorageSettings(vm: vm)
                .padding(20)
                .frame(width: 520, alignment: .leading)
                .blitzGlassSurface(cornerRadius: 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 28)
        .padding(.top, 28)
    }
}

private struct RecordingStorageSettings: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Storage")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.7)
                    .foregroundStyle(.white.opacity(0.52))

                HStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.52))
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Output folder")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.88))
                        Text(vm.settings.outputDirectory.path)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.56))
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 12)

                    Button {
                        vm.chooseOutputFolder()
                    } label: {
                        Label("Change", systemImage: "folder.badge.gearshape")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                    }
                    .blitzGlassButton()
                    .disabled(vm.state != .idle)
                    .pointingHandCursor()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.055), in: .rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
            }

            Toggle(isOn: Binding(
                get: { vm.settings.savesSourceFiles },
                set: { vm.setSourceFilesSaved($0) }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Save source files", systemImage: "folder.badge.plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.88))
                    Text("Keeps separate screen, camera, microphone, and system audio files next to the final export.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.52))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(vm.state != .idle)

            Toggle(isOn: Binding(
                get: { vm.settings.renamesRecordingsFromSpeech },
                set: { vm.setSpeechRenameEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Auto-name from speech", systemImage: "text.bubble")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.88))
                    Text("Requests Speech Recognition after a mic recording, then uses the transcript for the filename.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.52))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(vm.state != .idle)
        }
    }
}

private struct RecordingSettingsControls: View {
    @Bindable var vm: RecorderViewModel
    private var canEdit: Bool { vm.state == .idle }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            optionSection("Resolution") {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    ForEach(OutputResolution.allCases, id: \.self) { resolution in
                        let dimensions = resolution.dimensions(for: vm.settings.layout)
                        optionButton(
                            title: resolution.displayName,
                            detail: "\(dimensions.width)x\(dimensions.height)",
                            systemImage: "rectangle.dashed",
                            isSelected: vm.settings.outputResolution == resolution
                        ) {
                            vm.setResolution(resolution)
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 16) {
                optionSection("Framerate") {
                    HStack(spacing: 8) {
                        ForEach(RecordingSettings.supportedFrameRates, id: \.self) { fps in
                            compactOptionButton(
                                title: "\(fps)",
                                detail: "fps",
                                isSelected: vm.settings.framesPerSecond == fps
                            ) {
                                vm.setFrameRate(fps)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                optionSection("Container") {
                    HStack(spacing: 8) {
                        ForEach(OutputVideoFormat.allCases, id: \.self) { format in
                            compactOptionButton(
                                title: format.displayName,
                                detail: "",
                                isSelected: vm.settings.outputVideoFormat == format
                            ) {
                                vm.setFormat(format)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !canEdit {
                Label("Recording settings are locked while capture is active.", systemImage: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .opacity(canEdit ? 1 : 0.62)
    }

    private func optionSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.52))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func optionButton(
        title: String,
        detail: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? .black.opacity(0.78) : .white.opacity(0.52))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isSelected ? .black : .white.opacity(0.86))
                    Text(detail)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isSelected ? .black.opacity(0.58) : .white.opacity(0.46))
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.white : Color.white.opacity(0.055))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.white.opacity(0.0) : Color.white.opacity(0.08), lineWidth: 1)
        }
        .disabled(!canEdit)
        .pointingHandCursor()
        .help(title)
    }

    private func compactOptionButton(
        title: String,
        detail: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isSelected ? .black : .white.opacity(0.84))
                    .lineLimit(1)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isSelected ? .black.opacity(0.58) : .white.opacity(0.46))
                        .lineLimit(1)
                }
            }
            .frame(width: 58, height: 42)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.white : Color.white.opacity(0.055))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.white.opacity(0.0) : Color.white.opacity(0.08), lineWidth: 1)
        }
        .disabled(!canEdit)
        .pointingHandCursor()
        .help(detail.isEmpty ? title : "\(title) \(detail)")
    }
}

struct PermissionsPage: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Access")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Text("Grant access only when a selected source needs it.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }

            PermissionSetupCard(vm: vm)
                .frame(width: 520, alignment: .leading)

            VStack(spacing: 0) {
                ForEach(Array(vm.permissionStatusRows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Divider()
                            .background(.white.opacity(0.08))
                            .padding(.horizontal, 16)
                    }
                    PermissionStatusRowView(row: row) {
                        handleTap(row)
                    }
                }
            }
            .padding(.vertical, 4)
            .frame(width: 520, alignment: .leading)
            .blitzGlassSurface(cornerRadius: 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .foregroundStyle(.white)
        .onAppear {
            vm.refreshPermissionStatus()
        }
    }

    private func handleTap(_ row: PermissionStatusRow) {
        switch row.source {
        case .screen:
            if row.isActive, vm.shouldSuggestScreenPicker {
                vm.pickScreen()
            } else if row.isActive {
                vm.applyScreenRecordingPermission()
            } else {
                vm.refreshPermissionStatus(message: "\(row.title) is not enabled in the current setup.")
            }
        case .systemAudio:
            if row.isActive {
                vm.applyScreenRecordingPermission()
            } else {
                vm.refreshPermissionStatus(message: "\(row.title) is not enabled in the current setup.")
            }
        case .camera, .microphone:
            if row.isActive {
                vm.requestSourcePermissions()
            } else {
                vm.refreshPermissionStatus(message: "\(row.title) is not enabled in the current setup.")
            }
        case nil:
            vm.requestAccessibilityPermission()
        }
    }
}

private struct PermissionSetupCard: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: vm.recordingReadiness.isReady ? "checkmark.shield.fill" : "lock.shield")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.recordingReadiness.isReady ? "Ready to record" : "Recording access needs attention")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(vm.permissionSetupSummary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button {
                    vm.runPrimaryPermissionAction()
                } label: {
                    Label(vm.primaryPermissionActionTitle, systemImage: vm.shouldSuggestScreenPicker ? "rectangle.on.rectangle" : "lock.open")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                }
                .blitzGlassButton()
                .pointingHandCursor()

                Button {
                    vm.pickScreen()
                } label: {
                    Label("Pick Screen", systemImage: "rectangle.on.rectangle")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                }
                .blitzGlassButton()
                .pointingHandCursor()

                Button {
                    vm.openScreenRecordingSettings()
                } label: {
                    Label("System Settings", systemImage: "gearshape")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                }
                .blitzGlassButton()
                .pointingHandCursor()

                Spacer(minLength: 0)
            }

            Text("For iPhone camera pairing, allow Local Network in the iPhone app and keep both devices on the same network.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.46))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .blitzGlassSurface(cornerRadius: 16)
    }

    private var tint: Color {
        vm.recordingReadiness.isReady
            ? Color(red: 0.09, green: 1.0, blue: 0.65)
            : Color(red: 1.0, green: 0.66, blue: 0.16)
    }
}

struct PermissionStatusRowView: View {
    let row: PermissionStatusRow
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: row.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(row.status)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: statusSymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(rowBackground)
        .contentShape(Rectangle())
        .pointingHandCursor()
        .help(helpText)
    }

    private var tint: Color {
        switch row.level {
        case .granted:
            return Color(red: 0.09, green: 1.0, blue: 0.65)
        case .warning:
            return Color(red: 1.0, green: 0.66, blue: 0.16)
        case .blocked:
            return Color(red: 1.0, green: 0.24, blue: 0.22)
        case .inactive:
            return .white.opacity(0.34)
        }
    }

    private var rowBackground: some View {
        Rectangle()
            .fill(backgroundColor)
    }

    private var backgroundColor: Color {
        switch row.level {
        case .granted, .inactive:
            return .clear
        case .warning:
            return Color(red: 1.0, green: 0.66, blue: 0.16).opacity(0.08)
        case .blocked:
            return Color(red: 1.0, green: 0.24, blue: 0.22).opacity(0.10)
        }
    }

    private var statusSymbol: String {
        if row.isOptional, row.level == .inactive {
            return "info.circle.fill"
        }
        switch row.level {
        case .granted:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .blocked:
            return "xmark.octagon.fill"
        case .inactive:
            return "minus.circle.fill"
        }
    }

    private var helpText: String {
        if row.isOptional, row.level == .inactive {
            return "\(row.title) is optional. Click to enable target-window controls."
        }
        switch row.level {
        case .granted:
            return "\(row.title) access is active. Click to recheck."
        case .warning:
            return "\(row.title) needs confirmation. Click to request access."
        case .blocked:
            return "\(row.title) is blocked. Click to open the permission flow."
        case .inactive:
            return "\(row.title) is not enabled in the current setup."
        }
    }
}

private struct PopoverShell<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.55))
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
    }
}

@MainActor
func labeledPicker<Value: Hashable, Content: View>(
    _ title: String,
    selection: Binding<Value>,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.55))
        Picker("", selection: selection, content: content)
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}
