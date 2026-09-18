import Foundation
import XCTest
@testable import BlitzRecorderDomain

final class TakeJSONTests: XCTestCase {
    func testScreenAndAudioProjectRoundTripsWithCameraPip() throws {
        let project = PortableProject.screenAndAudio(
            hasMicrophone: true,
            hasSystemAudio: true,
            hasCamera: true
        )
        XCTAssertTrue(project.hasCamera)
        XCTAssertEqual(project.scene.camera, .cameraPip)
        let data = try TakeJSON.encode(project)
        let decoded = try JSONDecoder().decode(PortableProject.self, from: data)
        XCTAssertEqual(decoded.sources.map(\.path), [
            TakeFolderLayout.screenName,
            TakeFolderLayout.cameraName,
            TakeFolderLayout.microphoneName,
            TakeFolderLayout.systemAudioName
        ])
        XCTAssertEqual(decoded.scene.cameraPixels()?.width, project.scene.cameraPixels()?.width)
    }

    func testCameraPipPixelsStayEvenAndOnCanvas() {
        let pip = NormalizedRect.cameraPip.pixelRect(canvasWidth: 1280, canvasHeight: 720)
        XCTAssertEqual(pip.width % 2, 0)
        XCTAssertEqual(pip.height % 2, 0)
        XCTAssertGreaterThanOrEqual(pip.x, 0)
        XCTAssertGreaterThanOrEqual(pip.y, 0)
        XCTAssertLessThanOrEqual(pip.x + pip.width, 1280)
        XCTAssertLessThanOrEqual(pip.y + pip.height, 720)
    }

    func testMediaTimeHundredNanosecondsRoundTrip() {
        let time = MediaTime(seconds: 1.5)
        XCTAssertEqual(time.hundredNanoseconds, 15_000_000)
        XCTAssertEqual(MediaTime(hundredNanoseconds: 15_000_000).seconds, 1.5, accuracy: 0.001)
    }

    func testProjectJSONCameraObjectIsWhatWindowsPipParserReads() throws {
        let json = String(
            decoding: try TakeJSON.encode(
                PortableProject.screenAndAudio(hasMicrophone: true, hasSystemAudio: true, hasCamera: true)
            ),
            as: UTF8.self
        )
        guard let cameraKey = json.range(of: "\"camera\"") else {
            return XCTFail("missing camera key")
        }
        let tail = json[cameraKey.lowerBound...]
        guard let brace = tail.firstIndex(of: "{"), let end = tail[brace...].firstIndex(of: "}") else {
            return XCTFail("camera key is not a JSON object")
        }
        let object = tail[brace...end]
        XCTAssertTrue(object.contains("\"x\""))
        XCTAssertTrue(object.contains("\"y\""))
        XCTAssertTrue(object.contains("\"width\""))
        XCTAssertTrue(object.contains("\"height\""))
        XCTAssertTrue(object.contains("0.68"))
        XCTAssertTrue(object.contains("0.28"))
        if let role = json.range(of: "\"role\"") {
            XCTAssertLessThan(cameraKey.lowerBound, role.lowerBound)
        }
    }

    func testProjectJSONCutsAreWhatWindowsKeptRangeParserReads() throws {
        var project = PortableProject.screenAndAudio(hasMicrophone: true, hasSystemAudio: false)
        project.cuts = [
            TimelineCut(start: 1.25, end: 3.5, kind: .manual, source: .user, isEnabled: true),
            TimelineCut(start: 8, end: 9, kind: .silence, source: .automatic, isEnabled: false)
        ]
        let json = String(decoding: try TakeJSON.encode(project), as: UTF8.self)
        XCTAssertTrue(json.contains("\"cuts\""))
        XCTAssertTrue(json.contains("\"start\""))
        XCTAssertTrue(json.contains("\"end\""))
        XCTAssertTrue(json.contains("\"isEnabled\""))
        XCTAssertTrue(json.contains("1.25"))
        XCTAssertTrue(json.contains("3.5") || json.contains("3.50"))
        XCTAssertTrue(json.contains("false"))
        let map = TimelineTimeMap(takeDuration: MediaTime(seconds: 10), cuts: project.cuts)
        XCTAssertEqual(map.keptRangesHNS.count, 2)
        XCTAssertEqual(map.keptRangesHNS[0].takeStart, 0)
        XCTAssertEqual(map.keptRangesHNS[0].takeEnd, MediaTime(seconds: 1.25).hundredNanoseconds)
        XCTAssertEqual(map.keptRangesHNS[1].takeStart, MediaTime(seconds: 3.5).hundredNanoseconds)
    }

    func testWindowsFixtureSidecarJSONDecodes() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(
            TakeManifest.self,
            from: Data(
                """
                {
                  "createdAt" : "2026-09-17T16:00:00Z",
                  "id" : "550E8400-E29B-41D4-A716-446655440000"
                }
                """.utf8
            )
        )
        XCTAssertEqual(manifest.id, UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000"))
        let project = try JSONDecoder().decode(
            PortableProject.self,
            from: Data(
                """
                {
                  "cuts" : [

                  ],
                  "scene" : {
                    "camera" : {
                      "height" : 0.28,
                      "width" : 0.28,
                      "x" : 0.68,
                      "y" : 0.68
                    },
                    "canvasHeight" : 1080,
                    "canvasWidth" : 1920,
                    "screen" : {
                      "height" : 1,
                      "width" : 1,
                      "x" : 0,
                      "y" : 0
                    }
                  },
                  "sources" : [
                    {
                      "path" : "screen.mp4",
                      "role" : "screen"
                    },
                    {
                      "path" : "camera.mp4",
                      "role" : "camera"
                    },
                    {
                      "path" : "audio.m4a",
                      "role" : "microphone"
                    }
                  ],
                  "version" : 1
                }
                """.utf8
            )
        )
        XCTAssertTrue(project.hasCamera)
        XCTAssertEqual(project.scene.camera, .cameraPip)
        XCTAssertEqual(project.sources.map(\.role), ["screen", "camera", "microphone"])
    }

    func testWindowsStopSyncJSONKeepsCutsAndPipWhenCameraFileMissing() throws {
        let project = try JSONDecoder().decode(
            PortableProject.self,
            from: Data(
                """
                {
                  "cuts" : [
                    {
                      "end" : 3.5,
                      "id" : "550E8400-E29B-41D4-A716-446655440000",
                      "isEnabled" : false,
                      "kind" : "manual",
                      "source" : "user",
                      "start" : 1.25
                    }
                  ],
                  "scene" : {
                    "camera" : {
                      "height" : 0.28,
                      "width" : 0.28,
                      "x" : 0.68,
                      "y" : 0.68
                    },
                    "canvasHeight" : 1080,
                    "canvasWidth" : 1920,
                    "screen" : {
                      "height" : 1,
                      "width" : 1,
                      "x" : 0,
                      "y" : 0
                    }
                  },
                  "sources" : [
                    {
                      "path" : "screen.mp4",
                      "role" : "screen"
                    },
                    {
                      "path" : "audio.m4a",
                      "role" : "microphone"
                    }
                  ],
                  "version" : 1
                }
                """.utf8
            )
        )
        XCTAssertEqual(project.cuts.count, 1)
        XCTAssertFalse(project.cuts[0].isEnabled)
        XCTAssertEqual(project.cuts[0].start, 1.25, accuracy: 0.0001)
        XCTAssertEqual(project.scene.camera, .cameraPip)
        XCTAssertFalse(project.hasCamera)
        XCTAssertEqual(project.sources.map(\.role), ["screen", "microphone"])
    }

    func testMacProjectJSONKeysWindowsCaptureParsersRead() {
        let json = """
        {
          "sceneEvents" : [
            {
              "scene" : {
                "sceneLayout" : {
                  "cameraFrame" : {
                    "height" : 0.25,
                    "width" : 0.5,
                    "x" : 0.455,
                    "y" : 0.045
                  }
                }
              }
            }
          ],
          "timelineEdits" : {
            "cuts" : [
              {
                "enabled" : false,
                "end" : 3.5,
                "kind" : "silence",
                "source" : "auto",
                "start" : 1.25
              }
            ]
          }
        }
        """
        XCTAssertTrue(json.contains("\"cameraFrame\""))
        XCTAssertTrue(json.contains("\"enabled\""))
        XCTAssertTrue(json.contains("\"cuts\""))
        XCTAssertFalse(json.contains("\"isEnabled\""))
        XCTAssertTrue(json.contains("0.455"))
    }
}
