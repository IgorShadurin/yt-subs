import Foundation

public struct StudioRequest: Codable, Sendable {
    public let requestID: String
    public let channelID: String
    public let createdAt: Double
    public init(channelID: String) {
        self.requestID = UUID().uuidString
        self.channelID = channelID
        self.createdAt = Date().timeIntervalSince1970
    }
}

public struct StudioResponse: Codable, Sendable {
    public let requestID: String
    public let channelID: String
    public let count: String?
    public let title: String?
    public let avatarURL: String?
    public let error: String?

    public func snapshot(for request: StudioRequest) throws -> ChannelSnapshot {
        guard requestID == request.requestID, channelID == request.channelID else { throw StudioError.invalidResponse }
        if let error { throw StudioError.reported(error) }
        guard let count, !count.isEmpty, count.allSatisfy({ $0.isASCII && $0.isNumber }),
              let number = UInt64(count), let title, !title.isEmpty, title.count <= 200 else { throw StudioError.invalidResponse }
        let avatar = avatarURL.flatMap { raw -> String? in
            guard let url = URL(string: raw), url.scheme == "https",
                  ["yt3.ggpht.com", "yt3.googleusercontent.com"].contains(url.host) else { return nil }
            return raw
        }
        return ChannelSnapshot(id: channelID, title: title, count: number, avatarURL: avatar, source: "studio")
    }
}

public enum StudioError: Error, LocalizedError {
    case unavailable, timedOut, invalidResponse, reported(String)
    public var errorDescription: String? {
        switch self {
        case .unavailable: "Chrome extension is disconnected. Open Chrome and enable YT Subs Studio."
        case .timedOut: "Studio did not respond in time. Check your Chrome sign-in and internet connection."
        case .invalidResponse: "Studio returned an unreadable count. The last successful count is unchanged."
        case .reported(let message): String(message.prefix(300))
        }
    }
}

public enum StudioFiles {
    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/YT Subs/Bridge", isDirectory: true)
    }
    public static func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    public static func write<T: Encodable>(_ value: T, name: String) throws {
        try prepare()
        let url = directory.appendingPathComponent(name)
        try JSONEncoder().encode(value).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public static func read<T: Decodable>(_ type: T.Type, name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)), data.count < 65536 else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

public enum StudioClient {
    public static func fetch(channelID: String) async throws -> ChannelSnapshot {
        let request = StudioRequest(channelID: channelID)
        try StudioFiles.write(request, name: "request.json")
        for _ in 0..<100 {
            try Task.checkCancellation()
            if let response = StudioFiles.read(StudioResponse.self, name: "response.json"), response.requestID == request.requestID {
                return try response.snapshot(for: request)
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        let heartbeat = StudioFiles.read(Double.self, name: "connected.json") ?? 0
        if Date().timeIntervalSince1970 - heartbeat > 45 { throw StudioError.unavailable }
        throw StudioError.timedOut
    }
}
