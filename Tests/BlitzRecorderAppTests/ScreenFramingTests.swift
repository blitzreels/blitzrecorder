import CoreGraphics
@testable import BlitzRecorderApp
import XCTest

final class ScreenFramingTests: XCTestCase {
    @MainActor
    func testNativeResizeWaitsForDeferredWindowUpdates() async throws {
        var current = CGRect(x: 200, y: 200, width: 1324, height: 960)
        var pending: CGRect?
        let target = CGRect(x: 800, y: 30, width: 600, height: 1067)
        let applied = try await WindowFrameWriter.apply(.init(
            frame: target,
            write: { change in
                var next = current
                switch change {
                case .size(let size): next.size = size
                case .position(let position): next.origin = position
                }
                pending = next
            },
            settle: {
                if let pending { current = pending }
                pending = nil
            },
            read: { current }
        ))
        XCTAssertEqual(applied, target)
    }

    @MainActor
    func testNativeResizeRetriesHeightAfterMovingAwayFromMonitorEdge() async throws {
        var current = CGRect(x: 200, y: 400, width: 1324, height: 500)
        let target = CGRect(x: 800, y: 30, width: 600, height: 1067)
        let applied = try await WindowFrameWriter.apply(.init(
            frame: target,
            write: { change in
                switch change {
                case .size(let size):
                    current.size = CGSize(width: size.width, height: min(size.height, 1440 - current.minY))
                case .position(let position): current.origin = position
                }
            },
            settle: {},
            read: { current }
        ))
        XCTAssertEqual(applied, target)
    }

    @MainActor
    func testSupersededResizeStopsBeforeTheNextWindowWrite() async {
        var writes = 0
        do {
            _ = try await WindowFrameWriter.apply(.init(
                frame: CGRect(x: 0, y: 0, width: 600, height: 1067),
                write: { _ in writes += 1 },
                settle: { throw CancellationError() },
                read: { .zero }
            ))
            XCTFail("A superseded fit must stop")
        } catch is CancellationError {
            XCTAssertEqual(writes, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWindowScalePreservesSceneAspectWhenItReachesMonitorEdges() {
        let plan = TargetWindowFitting.plan(
            screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1050),
            captureLayout: .vertical,
            screenSlot: CGRect(x: 0, y: 0, width: 1, height: 1),
            zoom: 0.5
        )
        XCTAssertEqual(plan.windowFrame.width / plan.windowFrame.height, 590.0 / 1050, accuracy: 0.001)
        XCTAssertLessThanOrEqual(plan.windowFrame.height, 1050)
    }

    func testBrowserMinimumWidthAlsoExpandsHeightToPreserveSceneAspect() {
        let frame = TargetWindowFitting.fittedFrame(.init(
            requested: CGRect(x: 100, y: 100, width: 300, height: 400),
            minimumSize: CGSize(width: 500, height: 0),
            available: CGRect(x: 0, y: 0, width: 1440, height: 900)
        ))
        XCTAssertEqual(frame.width, 500, accuracy: 0.001)
        XCTAssertEqual(frame.height, 500 / 0.75, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(frame.minY, 0)
    }

    func testHiddenCameraDoesNotReserveHalfTheBrowserWindow() {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .camera]
        settings.hiddenSources = [.camera]
        settings.layout = .vertical
        settings.sceneLayout = SceneLayout.presetLayout(.stackedHalves, for: .vertical)
        XCTAssertEqual(TargetWindowFitting.sourceAspectRatio(for: settings), 9.0 / 16.0, accuracy: 0.001)
    }

    func testWindowSizeSnapshotRoundTripAndLegacyDefault() throws {
        var settings = RecordingSettings()
        settings.screenWindowZoom = 1.5
        let snapshot = RecordingSceneSnapshot(settings: settings)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(RecordingSceneSnapshot.self, from: data)
        XCTAssertEqual(decoded.screenWindowZoom, 1.5)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        payload.removeValue(forKey: "screenWindowZoom")
        let legacy = try JSONDecoder().decode(
            RecordingSceneSnapshot.self, from: JSONSerialization.data(withJSONObject: payload)
        )
        XCTAssertEqual(legacy.screenWindowZoom, 1)
    }

    @MainActor
    func testWindowSizeRestoresWithItsScene() throws {
        let suite = "ScreenFramingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        let originalID = try XCTUnwrap(coordinator.sceneLibrary.selectedScene(layout: .vertical)?.id)
        let otherID = try XCTUnwrap(coordinator.sceneLibrary.scenes(for: .vertical).first { $0.id != originalID }?.id)
        coordinator.setScreenWindowZoom(1.5)
        coordinator.selectScene(id: otherID)
        coordinator.setScreenWindowZoom(0.75)
        coordinator.selectScene(id: originalID)
        XCTAssertEqual(coordinator.settings.screenWindowZoom, 1.5)
        coordinator.selectScene(id: otherID)
        XCTAssertEqual(coordinator.settings.screenWindowZoom, 0.75)
    }

}
