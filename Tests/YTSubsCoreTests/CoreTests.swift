import XCTest
@testable import YTSubsCore

final class CoreTests: XCTestCase {
    func testDisplayBoundaries() {
        for (count, expected): (UInt64, String) in [(0,"0"),(999,"999"),(1526,"1,526"),(9999,"9,999"),(10000,"10k"),(10100,"10.1k"),(10999,"10.9k"),(999999,"999.9k"),(1000000,"1m"),(1200000000,"1.2b")] {
            XCTAssertEqual(SubscriberFormat.string(count), expected)
        }
    }
    func testRetryIntervals() {
        XCTAssertEqual(PollPolicy.delay(interval: 60, failed: true), 60)
        XCTAssertEqual(PollPolicy.delay(interval: 300, failed: true), 300)
        XCTAssertEqual(PollPolicy.delay(interval: 3600, failed: true), 600)
        XCTAssertEqual(PollPolicy.delay(interval: 3600, failed: false), 3600)
        XCTAssertEqual(PollPolicy.delay(interval: .infinity, failed: false), 60)
    }
    let channel = "UCabcdefghijklmnopqrstuv"
    func testChannelValidation() {
        XCTAssertEqual(ChannelInput.id(from: " https://www.youtube.com/channel/\(channel)/ "), channel)
        XCTAssertEqual(ChannelInput.id(from: channel), channel)
        XCTAssertNil(ChannelInput.id(from: "https://evil.example/channel/\(channel)"))
        XCTAssertNil(ChannelInput.id(from: "https://youtube.com/@example"))
    }
    func testRealResponseShapeAndZero() throws {
        let data = Data("""
        {"items":[{"id":"\(channel)","snippet":{"title":"Channel"},"statistics":{"subscriberCount":"0","hiddenSubscriberCount":false}}]}
        """.utf8)
        let result = try YouTubeAPI.decode(data, channelID: channel)
        XCTAssertEqual(result.count, 0)
        XCTAssertEqual(result.title, "Channel")
        XCTAssertThrowsError(try YouTubeAPI.decode(data, channelID: "different"))
    }
    func testAPIAlsoReturnsAutomaticAvatarAndSource() throws {
        let data = Data("""
        {"items":[{"id":"\(channel)","snippet":{"title":"Updated name","thumbnails":{"medium":{"url":"https://yt3.ggpht.com/new-avatar"}}},"statistics":{"subscriberCount":"1520"}}]}
        """.utf8)
        let result = try YouTubeAPI.decode(data, channelID: channel)
        XCTAssertEqual(result.title, "Updated name")
        XCTAssertEqual(result.avatarURL, "https://yt3.ggpht.com/new-avatar")
        XCTAssertEqual(result.source, "api")
    }
    func testMissingHiddenAndInvalidNeverBecomeZero() {
        for stats in ["{}", "{\"subscriberCount\":\"123\",\"hiddenSubscriberCount\":true}", "{\"subscriberCount\":\"invalid\"}"] {
            let data = Data("{\"items\":[{\"id\":\"\(channel)\",\"snippet\":{\"title\":\"Channel\"},\"statistics\":\(stats)}]}".utf8)
            XCTAssertThrowsError(try YouTubeAPI.decode(data, channelID: channel))
        }
        XCTAssertThrowsError(try YouTubeAPI.decode(Data("{\"items\":[]}".utf8), channelID: channel))
    }
}

final class SubscriberChangeTests: XCTestCase {
    func reading(_ count: UInt64, id: String = "channel", source: String = "studio") -> ChannelSnapshot {
        ChannelSnapshot(id: id, title: "Test", count: count, source: source)
    }

    func testSingleSubscriberAndCompactDisplayChanges() {
        XCTAssertEqual(SubscriberChange.between(reading(1526), reading(1527)), .increase)
        // Still animate when the formatted menu bar number stays at 10.1k.
        XCTAssertEqual(SubscriberFormat.string(10100), SubscriberFormat.string(10101))
        XCTAssertEqual(SubscriberChange.between(reading(10100), reading(10101)), .increase)
        XCTAssertEqual(SubscriberChange.between(reading(1527), reading(1526)), .decrease)
    }

    func testNoFalseChanges() {
        XCTAssertNil(SubscriberChange.between(nil, reading(1527)))
        XCTAssertNil(SubscriberChange.between(reading(1527), reading(1527)))
        XCTAssertNil(SubscriberChange.between(reading(1526), reading(1527, id: "other")))
        XCTAssertNil(SubscriberChange.between(reading(1520, source: "api"), reading(1527)))
    }

    func testPulseLastsThirtySecondsAndResets() {
        let effect = SubscriberChange.increase
        XCTAssertEqual(effect.duration, 30)
        XCTAssertEqual(effect.strength(at: 0), 1)
        XCTAssertEqual(effect.strength(at: 1), 0.65, accuracy: 0.001)
        XCTAssertEqual(effect.strength(at: 2), 1, accuracy: 0.001)
        XCTAssertGreaterThan(effect.strength(at: 29.99), 0)
        XCTAssertEqual(effect.strength(at: 30), 0)
        XCTAssertEqual(effect.strength(at: 31), 0)
        XCTAssertEqual(SubscriberChange.decrease.duration, 2)
        XCTAssertEqual(SubscriberChange.decrease.strength(at: 2), 0)
    }
}
