import AppKit
import Foundation
import YTSubsCore

@MainActor
final class AvatarCache {
    private struct Entry: Codable {
        let url: String
        let savedAt: Date
        let data: Data
    }
    private let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("com.ytsubs.mac/avatars", isDirectory: true)
    private func file(_ channelID: String) -> URL? {
        guard ChannelInput.id(from: channelID) == channelID else { return nil }
        return directory.appendingPathComponent(channelID + ".json")
    }
    private func entry(_ channelID: String) -> Entry? {
        guard let file = file(channelID), let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }
    func cached(_ channelID: String) -> NSImage? { entry(channelID).flatMap { NSImage(data: $0.data) } }
    func update(channelID: String, url: String?) async -> NSImage? {
        let previous = entry(channelID)
        guard let raw = url, let url = URL(string: raw), url.scheme == "https",
              ["yt3.ggpht.com", "yt3.googleusercontent.com"].contains(url.host), let file = file(channelID) else {
            return previous.flatMap { NSImage(data: $0.data) }
        }
        if let previous, previous.url == raw, Date().timeIntervalSince(previous.savedAt) < 86400 {
            return NSImage(data: previous.data)
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 15))
            try Task.checkCancellation()
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 2_000_000,
                  let image = NSImage(data: data) else { return previous.flatMap { NSImage(data: $0.data) } }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(Entry(url: raw, savedAt: Date(), data: data)).write(to: file, options: .atomic)
            return image
        } catch { return previous.flatMap { NSImage(data: $0.data) } }
    }
}
