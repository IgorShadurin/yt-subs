import XCTest
@testable import YTSubsCore

final class StudioTests: XCTestCase {
    func response(_ request: StudioRequest, count: String = "1526", channel: String? = nil, error: String? = nil, avatar: String = "https://yt3.ggpht.com/avatar") throws -> StudioResponse {
        var object: [String: String] = ["requestID": request.requestID, "channelID": channel ?? request.channelID, "count": count, "title": "Test channel", "avatarURL": avatar]
        object["error"] = error
        return try JSONDecoder().decode(StudioResponse.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func testExactStudioResponse() throws {
        let request = StudioRequest(channelID: "UCabcdefghijklmnopqrstuv")
        let result = try response(request).snapshot(for: request)
        XCTAssertEqual(result.count, 1526)
        XCTAssertEqual(result.source, "studio")
        XCTAssertEqual(result.avatarURL, "https://yt3.ggpht.com/avatar")
    }
    func testWrongChannelStaleRequestAndErrorsRejected() throws {
        let request = StudioRequest(channelID: "UCabcdefghijklmnopqrstuv")
        XCTAssertThrowsError(try response(request, channel: "UCxxxxxxxxxxxxxxxxxxxxxx").snapshot(for: request))
        XCTAssertThrowsError(try response(request).snapshot(for: StudioRequest(channelID: request.channelID)))
        XCTAssertThrowsError(try response(request, error: "Sign in required").snapshot(for: request))
        for count in ["1.52k", "-1", "1,526", "", "18446744073709551616"] {
            XCTAssertThrowsError(try response(request, count: count).snapshot(for: request))
        }
        XCTAssertEqual(try response(request, count: "0").snapshot(for: request).count, 0)
        XCTAssertNil(try response(request, avatar: "https://untrusted.example/image").snapshot(for: request).avatarURL)
    }
    func testOldAPICacheRemainsReadable() throws {
        let old = Data("{\"id\":\"channel\",\"title\":\"Channel\",\"count\":1520,\"fetchedAt\":123}".utf8)
        let snapshot = try JSONDecoder().decode(ChannelSnapshot.self, from: old)
        XCTAssertNil(snapshot.source)
        XCTAssertNil(snapshot.avatarURL)
    }
}
