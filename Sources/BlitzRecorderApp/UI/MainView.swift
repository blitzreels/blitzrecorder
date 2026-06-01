import AppKit
import BlitzRecorderCore
import SwiftUI

struct MainView: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        let screenshotVariant = ScreenshotVariant.current

        HStack(spacing: 0) {
            AppTabRail(vm: vm)

            ZStack {
                backgroundLayer

                switch vm.appTab {
                case .recorder:
                    recorderContent(screenshotVariant: screenshotVariant)
                case .iphone:
                    RemoteCameraPage(vm: vm)
                case .recording:
                    RecordingSettingsPage(vm: vm)
                case .permissions:
                    PermissionsPage(vm: vm)
                case .creator:
                    BlitzReelsCreatorPage(access: vm.accessController)
                }
            }
            .overlay(alignment: .topTrailing) {
                if vm.appTab == .recorder {
                    screenshotOverlay
                        .padding(.top, 58)
                        .padding(.trailing, 22)
                }
            }
        }
        .overlay {
            if vm.showsFirstRunOnboarding {
                RecordingAccessCover(vm: vm)
            }
        }
        .task {
            await vm.refreshSources()
            vm.syncSettings()
            vm.refreshTargetWindow()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            vm.refreshTargetWindow()
        }
    }

    private func recorderContent(screenshotVariant: ScreenshotVariant) -> some View {
        VStack(spacing: 0) {
            TopBar(vm: vm)
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 14)

            HStack(alignment: .top, spacing: 14) {
                SourcesSidebar(vm: vm)

                VStack(spacing: 0) {
                    ZStack {
                        PreviewStageRepresentable(view: vm.previewStage)

                        if ScreenshotVariant.isScreenshotModeEnabled {
                            ScreenshotPreviewCanvas(variant: screenshotVariant)
                        }

                        CropToolbarOverlay(vm: vm)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                    BottomDock(vm: vm)
                        .padding(.top, 16)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
        }
    }

}

private struct ProductIconImage: View {
    let image: NSImage?
    let fallbackSystemImage: String
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                Image(systemName: fallbackSystemImage)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

private extension Bundle {
    var blitzRecorderCameraIcon: NSImage? {
        guard let url = url(forResource: "Icon-App-60x60@3x", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

struct CropToolbarOverlay: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        GeometryReader { proxy in
            if let frame = vm.cropToolbarFrame,
               vm.isScreenCropModeEnabled || vm.isCameraCropModeEnabled {
                CropFloatingToolbar(vm: vm)
                    .fixedSize()
                    .position(
                        x: frame.midX,
                        y: proxy.size.height - frame.midY
                    )
            }
        }
    }
}

private struct CropFloatingToolbar: View {
    @Bindable var vm: RecorderViewModel

    private let accent = Color(red: 1.0, green: 0.66, blue: 0.16)
    private var isCameraCrop: Bool { vm.isCameraCropModeEnabled }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                if isCameraCrop {
                    vm.applyCameraCropMode()
                } else {
                    vm.applyScreenCropMode()
                }
            } label: {
                Label("Done cropping", systemImage: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black.opacity(0.88))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(accent, in: .rect(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()

            Button {
                if isCameraCrop {
                    vm.resetCameraCrop()
                } else {
                    vm.resetScreenCropMode()
                }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .blitzGlassButton()
            .controlSize(.small)
            .pointingHandCursor()

            Button {
                if isCameraCrop {
                    vm.cancelCameraCropMode()
                } else {
                    vm.cancelScreenCropMode()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .blitzGlassButton()
            .controlSize(.small)
            .pointingHandCursor()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .foregroundStyle(.white)
        .background(.black.opacity(0.70), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.32), radius: 16, y: 8)
    }
}

private struct RemoteCameraPage: View {
    @Bindable var vm: RecorderViewModel

    private let accent = Color(red: 0.09, green: 1.0, blue: 0.65)

	var body: some View {
		Group {
			if vm.isRemoteCameraSelected {
				connectedLayout
			} else {
				disconnectedLayout
			}
		}
		.onAppear {
			vm.startRemoteCameraDiscovery()
		}
	}

    private var disconnectedLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                onboardingHeader
                setupStepsCard
                nearbyDevicesCard
            }
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 28)
            .padding(.vertical, 28)
        }
        .foregroundStyle(.white)
    }

    private var onboardingHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Film with your iPhone")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
            Text("Your iPhone has a better camera than a webcam. It records the video while your Mac shows it live.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var setupStepsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SET UP IN 4 STEPS")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.52))

            VStack(alignment: .leading, spacing: 16) {
                downloadStep
                stepRow(
                    2,
                    title: "Open it",
                    detail: "Open the app. Use the same Wi-Fi as this Mac."
                )
                stepRow(
                    3,
                    title: "Connect them",
                    detail: "Your iPhone shows up below. Click it, then type the 6 numbers it shows you."
                )
                stepRow(
                    4,
                    title: "Hit record",
                    detail: "Pick your iPhone on the Capture tab and press record."
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .blitzGlassSurface(cornerRadius: 16)
    }

    private var downloadStep: some View {
        HStack(alignment: .top, spacing: 12) {
            stepBadge(1)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Get the app")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                    Text("Put BlitzRecorder Camera on your iPhone.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                companionAppLink
            }
            Spacer(minLength: 0)
        }
    }

    private func stepRow(_ number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            stepBadge(number)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func stepBadge(_ number: Int) -> some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.16))
            Circle()
                .stroke(accent.opacity(0.45), lineWidth: 1)
            Text("\(number)")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(accent)
        }
        .frame(width: 24, height: 24)
    }

    private var nearbyDevicesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("NEARBY IPHONES")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.7)
                    .foregroundStyle(.white.opacity(0.52))
                Spacer(minLength: 0)
                if vm.remoteCameraDeviceSummaries.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if vm.remoteCameraDeviceSummaries.isEmpty {
                searchingRow
            } else {
                VStack(spacing: 8) {
                    ForEach(vm.remoteCameraDeviceSummaries) { device in
                        remoteCameraDeviceRow(device)
                    }
                }
            }

            Button {
                vm.appTab = .recorder
            } label: {
                Label("Open Capture", systemImage: "record.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
            }
            .blitzGlassButton()
            .pointingHandCursor()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .blitzGlassSurface(cornerRadius: 16)
    }

    private var searchingRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi")
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.62))
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text("Looking for your iPhone…")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Text("Open the app on your iPhone. Use the same Wi-Fi as this Mac.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var companionAppLink: some View {
        Link(destination: BlitzRecorderProductIdentity.companionInstallURL) {
            HStack(spacing: 12) {
                ProductIconImage(
                    image: Bundle.main.blitzRecorderCameraIcon,
                    fallbackSystemImage: "iphone.gen3",
                    size: 42,
                    cornerRadius: 9
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(BlitzRecorderProductIdentity.companionDisplayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                    Text("iPhone app")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.52))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.055), in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help("Open \(BlitzRecorderProductIdentity.companionDisplayName)")
    }

    private var connectedLayout: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(vm.selectedRemoteCameraDeviceDescription)
                        .font(.system(size: 20, weight: .semibold))
                    Text("The iPhone records the sharp video. The Mac shows a quick preview.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            HSplitView {
                previewColumn
                settingsColumn
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            remotePreview

            previewLegend

            remoteStatusDetails
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.trailing, 20)
    }

    private var settingsColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pairingSection
                RemoteCameraControlsPane(vm: vm)
            }
            .padding(.leading, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
        .frame(maxHeight: .infinity)
        .scrollIndicators(.visible)
    }

    @ViewBuilder
    private var remotePreview: some View {
        GeometryReader { proxy in
            let previewSize = fittedRemotePreviewSize(in: proxy.size)

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.black)

                CameraPreviewRepresentable(view: vm.remoteCameraPreviewSurface)
                    .frame(width: previewSize.width, height: previewSize.height)
                    .clipped()

                if !vm.hasRemoteCameraPreviewImage {
                    VStack(spacing: 8) {
                        Image(systemName: vm.isRemoteCameraSelected ? "iphone.gen3.radiowaves.left.and.right" : "iphone.gen3")
                            .font(.system(size: 32, weight: .regular))
                            .foregroundStyle(.tertiary)
                        Text(previewEmptyTitle)
                            .font(.system(size: 14, weight: .medium))
                        Text(previewEmptyDetail)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: 320)
                    .frame(width: previewSize.width, height: previewSize.height)
                    .background(.black.opacity(0.82))
                }

            }
            .frame(width: previewSize.width, height: previewSize.height)
            .border(Color(nsColor: .separatorColor).opacity(0.3), width: 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewLegend: some View {
        Label("Source records on iPhone", systemImage: "iphone.gen3.radiowaves.left.and.right")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .allowsHitTesting(false)
    }

    private var pairingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Pairing")

            if vm.remoteCameraDeviceSummaries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Open BlitzRecorder Camera on your iPhone", systemImage: "iphone.gen3")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(vm.remoteCameraDeviceSummaries) { device in
                        remoteCameraDeviceRow(device)
                    }
                }
            }
        }
    }

    private func remoteCameraDeviceRow(_ device: RemoteCameraDeviceSummary) -> some View {
        Button {
            vm.setCamera(device.cameraID)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(device.isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.08))
                    Image(systemName: device.isReady ? "iphone.gen3.radiowaves.left.and.right" : "iphone.gen3")
                        .font(.system(size: 14, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(device.isSelected ? .white : .white.opacity(0.72))
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                    Text(device.detail)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    if let lensCount = device.lensCount, lensCount > 0 {
                        lensDots(count: lensCount)
                            .help("\(lensCount) camera lenses available")
                    }

                    Text(device.status)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(device.isSelected ? .black.opacity(0.78) : .white.opacity(0.6))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(device.isSelected ? Color.white : Color.white.opacity(0.08), in: .capsule)
                }
            }
            .padding(8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(vm.state != .idle)
        .opacity(vm.state == .idle || device.isSelected ? 1 : 0.48)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(device.isSelected ? Color.white.opacity(0.10) : Color.white.opacity(0.04))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(device.isSelected ? Color.white.opacity(0.22) : Color.white.opacity(0.08), lineWidth: 1)
        }
        .pointingHandCursor()
        .help("Use \(device.name) as the iPhone camera")
    }

    private func lensDots(count: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<min(count, 4), id: \.self) { _ in
                Circle()
                    .fill(.white.opacity(0.42))
                    .frame(width: 4, height: 4)
            }
        }
        .frame(width: 24, alignment: .trailing)
    }

    private var remoteStatusDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("iPhone")
            statusRow("Device", value: vm.selectedRemoteCameraDeviceDescription)
            statusRow("Status", value: vm.selectedRemoteCameraStatus ?? (vm.isRemoteCameraSelected ? "Waiting" : "No iPhone selected"))
            statusRow("Video", value: vm.selectedRemoteCameraReviewStatus)
            statusRow("Controls", value: vm.selectedRemoteCameraCapabilities == nil ? "Waiting" : "Ready")
        }
        .frame(maxWidth: 460, alignment: .leading)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .medium))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }

    private func statusRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 12, weight: .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private var previewEmptyTitle: String {
        vm.isRemoteCameraSelected ? "Waiting for iPhone video" : "No iPhone selected"
    }

    private var previewEmptyDetail: String {
        vm.isRemoteCameraSelected
            ? "Keep the iPhone app open. The good video records on the iPhone."
            : "Choose a nearby iPhone from Pairing."
    }

    private func fittedRemotePreviewSize(in availableSize: CGSize) -> CGSize {
        let aspectRatio = max(0.1, vm.remoteCameraPreviewAspectRatio)
        let availableWidth = max(1, availableSize.width)
        let availableHeight = max(1, availableSize.height)
        let widthFittedToHeight = availableHeight * aspectRatio

        if widthFittedToHeight <= availableWidth {
            return CGSize(width: widthFittedToHeight, height: availableHeight)
        }

        return CGSize(width: availableWidth, height: availableWidth / aspectRatio)
    }
}

private struct AppTabRail: View {
    @Bindable var vm: RecorderViewModel
    @State private var hoveredTab: AppTab?

    var body: some View {
        VStack(spacing: 2) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                railButton(tab)
            }
            Spacer()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .frame(width: 154)
        .background(Color(red: 0.025, green: 0.025, blue: 0.03))
    }

    private func railButton(_ tab: AppTab) -> some View {
        let isSelected = vm.appTab == tab
        let isHovered = hoveredTab == tab
        let hasIssues = tab == .permissions && vm.permissionIssueCount > 0
        return Button {
            vm.appTab = tab
        } label: {
            HStack(spacing: 9) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 18, height: 18)
                    .foregroundStyle(isSelected ? Color(red: 0.09, green: 1.0, blue: 0.65) : .white.opacity(0.38))

                Text(tab.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? .white.opacity(0.92) : .white.opacity(0.52))
                    .lineLimit(1)
                    .minimumScaleFactor(0.92)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .topTrailing) {
                if hasIssues {
                    Circle()
                        .fill(.yellow)
                        .frame(width: 7, height: 7)
                        .offset(x: -4, y: 7)
                }
            }
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tabBackground(isSelected: isSelected, isHovered: isHovered))
        )
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredTab = hovering ? tab : (hoveredTab == tab ? nil : hoveredTab)
        }
        .pointingHandCursor()
        .help(tab.title)
    }

    private func tabBackground(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return Color.white.opacity(isHovered ? 0.11 : 0.08)
        }
        if isHovered {
            return Color.white.opacity(0.055)
        }
        return Color.clear
    }
}

private extension MainView {
    var backgroundLayer: some View {
        LinearGradient(
            colors: [
                Color(red: 0.03, green: 0.03, blue: 0.04),
                Color(red: 0.06, green: 0.06, blue: 0.08)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var screenshotOverlay: some View {
        switch ScreenshotVariant.current {
        case .plan:
            ScreenshotCard(width: 320) {
                VStack(alignment: .leading, spacing: 12) {
                    screenshotEyebrow("PLAN")
                    Text("3 free videos left")
                        .font(.system(size: 16, weight: .bold))
                    Text("Pro lets you save as many videos as you want.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.62))
                    Text("It renews until you cancel it in your Apple settings.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.54))

                    Label("Get Pro for $49.99/year", systemImage: "creditcard.fill")
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.16), in: .rect(cornerRadius: 8))

                    HStack(spacing: 8) {
                        screenshotSmallButton("Restore", icon: "arrow.clockwise")
                        screenshotSmallButton("Sign in with BlitzReels", icon: "person.crop.circle.badge.checkmark")
                    }

                    Divider().background(.white.opacity(0.12))

                    HStack(spacing: 12) {
                        Text("Terms")
                        Text("Privacy")
                        Text("Support")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.66))
                }
            }
        case .iphoneControls:
            ScreenshotCard(width: 330) {
                VStack(alignment: .leading, spacing: 12) {
                    screenshotEyebrow("IPHONE CAMERA")
                    HStack(spacing: 9) {
                        Image(systemName: "iphone.gen3")
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Connected to iPhone")
                                .font(.system(size: 15, weight: .bold))
                            Text("Monitor preview, local recording, transfer back to Mac")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.56))
                        }
                    }

                    HStack(spacing: 7) {
                        screenshotPill("Wide")
                        screenshotPill("1.4x")
                        screenshotPill("4K")
                        screenshotPill("30 fps")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        screenshotControlRow("Lens", value: "Wide", icon: "camera.aperture")
                        screenshotControlRow("Focus", value: "Continuous", icon: "scope")
                        screenshotControlRow("Exposure", value: "Auto", icon: "sun.max")
                        screenshotControlRow("Transfer", value: "Ready", icon: "arrow.up.doc")
                    }
                }
            }
        case .none:
            EmptyView()
        }
    }

    private func screenshotEyebrow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(.white.opacity(0.55))
    }

    private func screenshotSmallButton(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.10), in: .rect(cornerRadius: 8))
    }

    private func screenshotPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.10), in: .capsule)
    }

    private func screenshotControlRow(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 16)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08), in: .rect(cornerRadius: 8))
    }
}

private enum ScreenshotVariant: Equatable {
    case none
    case plan
    case iphoneControls

    static var current: ScreenshotVariant {
        let environment = ProcessInfo.processInfo.environment
        guard isScreenshotModeEnabled else {
            return .none
        }

        switch environment["BLITZRECORDER_SCREENSHOT_VARIANT"] {
        case "plan": return .plan
        case "iphone-controls": return .iphoneControls
        default: return .none
        }
    }

    static var isScreenshotModeEnabled: Bool {
        ProcessInfo.processInfo.environment["BLITZRECORDER_SCREENSHOT_MODE"] == "1"
    }
}

private struct ScreenshotPreviewCanvas: View {
    let variant: ScreenshotVariant

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.02, green: 0.03, blue: 0.04),
                        Color(red: 0.04, green: 0.07, blue: 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                screenshotWorkspace(width: proxy.size.width, height: proxy.size.height)
            }
            .clipShape(.rect(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
        }
        .padding(.horizontal, 4)
    }

    private func screenshotWorkspace(width: CGFloat, height: CGFloat) -> some View {
        let stageHeight = min(height * 0.78, 560)
        let stageWidth = min(stageHeight * 9 / 16, width * 0.34)

        return HStack(alignment: .center, spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
                screenshotTimeline
                screenshotAudioMeters
            }
            .frame(width: min(width * 0.28, 260), alignment: .leading)

            screenshotShortsFrame
                .frame(width: stageWidth, height: stageHeight)

            VStack(alignment: .leading, spacing: 14) {
                screenshotStatusCard
                screenshotRenderCard
            }
            .frame(width: min(width * 0.24, 230), alignment: .leading)
        }
        .padding(.horizontal, 28)
    }

    private var screenshotShortsFrame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.06, green: 0.09, blue: 0.11),
                            Color(red: 0.08, green: 0.05, blue: 0.11)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.12, green: 0.16, blue: 0.18))
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 6) {
                            Circle().fill(Color(red: 1.0, green: 0.36, blue: 0.34))
                            Circle().fill(Color(red: 1.0, green: 0.77, blue: 0.28))
                            Circle().fill(Color(red: 0.25, green: 0.86, blue: 0.48))
                        }
                        .frame(width: 54, height: 8)
                        .padding(12)
                    }
                    .overlay {
                        VStack(alignment: .leading, spacing: 10) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.white.opacity(0.72))
                                .frame(width: 112, height: 12)
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color(red: 0.14, green: 0.88, blue: 0.68).opacity(0.72))
                                .frame(width: 154, height: 12)
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.white.opacity(0.24))
                                .frame(width: 132, height: 12)
                        }
                    }
                    .padding(18)

                ZStack(alignment: .bottomTrailing) {
                    LinearGradient(
                        colors: [
                            Color(red: 0.09, green: 0.12, blue: 0.16),
                            Color(red: 0.06, green: 0.06, blue: 0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(.rect(cornerRadius: 16))

                    ScreenshotRuleOfThirdsShape()
                        .stroke(.white.opacity(0.14), lineWidth: 1)

                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(red: 0.08, green: 0.09, blue: 0.12))
                        .frame(width: 96, height: 132)
                        .overlay {
                            VStack(spacing: 8) {
                                Circle()
                                    .fill(Color(red: 0.18, green: 0.9, blue: 0.76).opacity(0.72))
                                    .frame(width: 34, height: 34)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.68))
                                    .frame(width: 48, height: 7)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.34))
                                    .frame(width: 60, height: 7)
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                        )
                        .padding(16)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }

            VStack {
                Spacer()
                HStack {
                    Label(variant == .iphoneControls ? "iPhone camera linked" : "Ready to export", systemImage: variant == .iphoneControls ? "iphone.gen3" : "square.and.arrow.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.36), in: .capsule)
                    Spacer()
                }
                .padding(16)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: Color(red: 0.0, green: 0.8, blue: 0.62).opacity(0.18), radius: 28)
    }

    private var screenshotTimeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SCENE")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.48))
            screenshotTrack(label: "Screen", color: Color(red: 0.20, green: 0.74, blue: 0.96), width: 164)
            screenshotTrack(label: "Camera", color: Color(red: 0.18, green: 0.9, blue: 0.72), width: 116)
            screenshotTrack(label: "Cursor", color: Color(red: 0.95, green: 0.72, blue: 0.25), width: 136)
        }
        .padding(14)
        .background(Color.white.opacity(0.07), in: .rect(cornerRadius: 14))
    }

    private func screenshotTrack(label: String, color: Color, width: CGFloat) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.62))
                .frame(width: width * 0.36, height: 7)
        }
    }

    private var screenshotAudioMeters: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AUDIO")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.48))
            screenshotMeter("Mic", fill: 0.68)
            screenshotMeter("System", fill: 0.46)
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 14))
    }

    private func screenshotMeter(_ label: String, fill: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule()
                        .fill(Color(red: 0.18, green: 0.9, blue: 0.72).opacity(0.76))
                        .frame(width: proxy.size.width * fill)
                }
            }
            .frame(height: 7)
        }
    }

    private var screenshotStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Vertical Shorts layout", systemImage: "rectangle.portrait")
                .font(.system(size: 11, weight: .bold))
            Text("Screen, face camera, cursor, and safe-zone overlays are arranged for export.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(Color.white.opacity(0.07), in: .rect(cornerRadius: 14))
    }

    private var screenshotRenderCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("EXPORT")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.48))
                Spacer()
                Text("1080x1920")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.56))
            }
            ProgressView(value: 0.72)
                .progressViewStyle(.linear)
                .tint(Color(red: 0.18, green: 0.9, blue: 0.72))
            Text(exportStatusText)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.66))
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 14))
    }

    private var exportStatusText: String {
        switch variant {
        case .plan:
            return "3 free exports included"
        case .iphoneControls:
            return "Transfer ready from iPhone"
        case .none:
            return "Export preview ready"
        }
    }
}

private struct ScreenshotRuleOfThirdsShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let firstX = rect.minX + rect.width / 3
            let secondX = rect.minX + rect.width * 2 / 3
            let firstY = rect.minY + rect.height / 3
            let secondY = rect.minY + rect.height * 2 / 3

            path.move(to: CGPoint(x: firstX, y: rect.minY))
            path.addLine(to: CGPoint(x: firstX, y: rect.maxY))
            path.move(to: CGPoint(x: secondX, y: rect.minY))
            path.addLine(to: CGPoint(x: secondX, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX, y: firstY))
            path.addLine(to: CGPoint(x: rect.maxX, y: firstY))
            path.move(to: CGPoint(x: rect.minX, y: secondY))
            path.addLine(to: CGPoint(x: rect.maxX, y: secondY))
        }
    }
}

private struct ScreenshotCard<Content: View>: View {
    let width: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(width: width, alignment: .leading)
            .foregroundStyle(.white)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 22, y: 14)
    }
}
