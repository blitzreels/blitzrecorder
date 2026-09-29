import XCTest
@testable import BlitzRecorderApp

final class BlitzReelsAccountDecodingTests: XCTestCase {
    func testConnectionDecodesTodaysServerAndTheRicherWorkspaceContract() throws {
        let current = #"{"user":{"id":"u","email":"a@b.c","display_name":null},"workspaces":[{"id":"w","name":"Studio"}],"default_workspace_id":"w"}"#
        let richer = #"{"user":{"id":"u","email":"a@b.c","display_name":"Ada","avatar_url":"https://cdn.test/a.png"},"workspaces":[{"id":"w","name":"Studio","plan":"pro","role":"owner"}],"default_workspace_id":"w"}"#
        let old = try JSONDecoder().decode(BlitzReelsAccount.self, from: Data(current.utf8))
        XCTAssertNil(old.workspaces.first?.plan)
        XCTAssertNil(old.user.avatar_url)
        let new = try JSONDecoder().decode(BlitzReelsAccount.self, from: Data(richer.utf8))
        XCTAssertEqual(new.workspaces.first?.plan, "pro")
        XCTAssertEqual(new.workspaces.first?.role, "owner")
        XCTAssertEqual(new.user.avatar_url, "https://cdn.test/a.png")
        let roundTrip = try JSONDecoder().decode(BlitzReelsAccount.self, from: JSONEncoder().encode(new))
        XCTAssertEqual(roundTrip.workspaces, new.workspaces)
    }
}
