import Foundation

public enum SubscriberFormat {
    public static func string(_ count: UInt64) -> String {
        if count < 10_000 {
            return count.formatted(.number.locale(Locale(identifier: "en_US")))
        }
        let divisor: Double = count >= 1_000_000_000 ? 1_000_000_000 : count >= 1_000_000 ? 1_000_000 : 1_000
        let suffix = count >= 1_000_000_000 ? "b" : count >= 1_000_000 ? "m" : "k"
        // Truncate, so compact formatting never claims subscribers not reported by YouTube.
        let value = floor(Double(count) / divisor * 10) / 10
        return value.formatted(.number.locale(Locale(identifier: "en_US")).grouping(.never).precision(.fractionLength(0...1))) + suffix
    }
}

public enum PollPolicy {
    public static func delay(interval: TimeInterval, failed: Bool) -> TimeInterval {
        let safe = interval.isFinite ? max(60, interval) : 60
        return failed ? min(safe, 600) : safe
    }
}

public enum ChannelInput {
    public static func id(from input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate: String
        if let url = URL(string: text), ["youtube.com", "www.youtube.com", "m.youtube.com"].contains(url.host?.lowercased() ?? ""), url.scheme == "https" {
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count == 2, parts[0] == "channel" else { return nil }
            candidate = parts[1]
        } else { candidate = text }
        return candidate.range(of: "^UC[A-Za-z0-9_-]{22}$", options: .regularExpression) != nil ? candidate : nil
    }
}

public struct ChannelSnapshot: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let count: UInt64
    public let fetchedAt: Date
    public let avatarURL: String?
    public let source: String?
    public init(id: String, title: String, count: UInt64, fetchedAt: Date = Date(), avatarURL: String? = nil, source: String? = nil) {
        self.id = id; self.title = title; self.count = count; self.fetchedAt = fetchedAt; self.avatarURL = avatarURL; self.source = source
    }
}

public enum APIError: Error, LocalizedError {
    case response, unavailable
    public var errorDescription: String? {
        switch self {
        case .response: "Could not fetch subscribers. Check the API key, API restrictions, and YouTube Data API quota."
        case .unavailable: "Channel not found or subscriber count is unavailable. Check the channel ID."
        }
    }
}

public enum YouTubeAPI {
    public static func decode(_ data: Data, channelID: String) throws -> ChannelSnapshot {
        struct Response: Decodable {
            struct Item: Decodable {
                struct Snippet: Decodable {
                    struct Thumbnail: Decodable { let url: String }
                    let title: String
                    let thumbnails: [String: Thumbnail]?
                }
                struct Statistics: Decodable { let subscriberCount: String?; let hiddenSubscriberCount: Bool? }
                let id: String; let snippet: Snippet; let statistics: Statistics
            }
            let items: [Item]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let item = response.items.first(where: { $0.id == channelID }), item.statistics.hiddenSubscriberCount != true,
              let raw = item.statistics.subscriberCount, let count = UInt64(raw) else { throw APIError.unavailable }
        return ChannelSnapshot(id: item.id, title: item.snippet.title, count: count, avatarURL: (item.snippet.thumbnails?["medium"] ?? item.snippet.thumbnails?["default"])?.url, source: "api")
    }
    public static func fetch(channelID: String, key: String) async throws -> ChannelSnapshot {
        var url = URLComponents(string: "https://www.googleapis.com/youtube/v3/channels")!
        url.queryItems = [URLQueryItem(name: "part", value: "snippet,statistics"), URLQueryItem(name: "id", value: channelID)]
        var request = URLRequest(url: url.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.response }
        return try decode(data, channelID: channelID)
    }
}
