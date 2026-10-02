import Foundation
import YTSubsCore

// Chrome owns this process. stdout is reserved for its length-prefixed protocol.
func readExactly(_ length: Int) -> Data? {
    var data = Data()
    while data.count < length {
        let chunk = FileHandle.standardInput.readData(ofLength: length - data.count)
        if chunk.isEmpty { return nil }
        data.append(chunk)
    }
    return data
}
func send(_ data: Data) {
    var length = UInt32(data.count).littleEndian
    let header = withUnsafeBytes(of: &length) { Data($0) }
    FileHandle.standardOutput.write(header + data)
}

DispatchQueue.global().async {
    var lastID = ""
    var heartbeat = Date.distantPast
    while true {
        if Date().timeIntervalSince(heartbeat) >= 15 {
            try? StudioFiles.write(Date().timeIntervalSince1970, name: "connected.json")
            heartbeat = Date()
        }
        if let request = StudioFiles.read(StudioRequest.self, name: "request.json"), request.requestID != lastID,
           Date().timeIntervalSince1970 - request.createdAt < 50,
           ChannelInput.id(from: request.channelID) == request.channelID,
           let data = try? JSONEncoder().encode(request) {
            lastID = request.requestID
            send(data)
        }
        Thread.sleep(forTimeInterval: 1)
    }
}
while let header = readExactly(4) {
    let length = header.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset * 8) }
    guard length > 0, length < 65536, let data = readExactly(Int(length)) else { break }
    guard
          let response = try? JSONDecoder().decode(StudioResponse.self, from: data),
          let request = StudioFiles.read(StudioRequest.self, name: "request.json"),
          request.requestID == response.requestID, request.channelID == response.channelID else { continue }
    try? StudioFiles.write(response, name: "response.json")
}
