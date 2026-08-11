// @copyright André Trettin

import CoreRPG
import Foundation
import Network
import os.log

// Define the types of commands your game will use.
enum GameMessageType: UInt32 {
    case invalid = 0
    case version = 1
    case error = 2
    case gameData = 3
}

final class GameProtocol: NWProtocolFramerImplementation {
    static let definition = NWProtocolFramer.Definition(implementation: GameProtocol.self)

    // Set a name for your protocol for use in debugging.
    static var label: String { return "MasterRPG" }

    // Set the default behavior for most framing protocol functions.
    required init(framer _: NWProtocolFramer.Instance) {}
    func start(framer _: NWProtocolFramer.Instance) -> NWProtocolFramer.StartResult {
        return .ready
    }

    func wakeup(framer _: NWProtocolFramer.Instance) {}
    func stop(framer _: NWProtocolFramer.Instance) -> Bool {
        return true
    }

    func cleanup(framer _: NWProtocolFramer.Instance) {}

    /// Largest single message this framer accepts. `GameProtocolHeader.length`
    /// is a `UInt32` off the wire, so without a bound a peer could declare up
    /// to ~4 GB and force an unbounded buffer wait. Matches
    /// `SharePlayJournalPublicationQueue`'s own outstanding-attachment budget —
    /// the largest single Map/Photo/PDF/Space/Audio attachment this app is
    /// designed to move around — rather than an arbitrary new ceiling.
    static let maximumMessageByteCount: UInt32 = 512_000_000

    /// Pulled out of `handleInput` so the length bound can be unit tested
    /// without standing up a live `NWProtocolFramer.Instance`.
    static func isMessageLengthValid(_ length: UInt32) -> Bool {
        length <= maximumMessageByteCount
    }

    // Whenever the application sends a message, add your protocol header and forward the bytes.
    func handleOutput(framer: NWProtocolFramer.Instance, message: NWProtocolFramer.Message, messageLength: Int, isComplete _: Bool) {
        // Extract the type of message.
        let type = message.gameMessageType

        // Create a header using the type and length.
        let header = GameProtocolHeader(type: type.rawValue, length: UInt32(messageLength))

        // Write the header.
        framer.writeOutput(data: header.encodedData)

        // Ask the connection to insert the content of the application message after your header.
        do {
            try framer.writeOutputNoCopy(length: messageLength)
        } catch {
            Logger.networking.error("Hit error writing: \(error.localizedDescription, privacy: .public)")
        }
    }

    // Whenever new bytes are available to read, try to parse out your message format.
    func handleInput(framer: NWProtocolFramer.Instance) -> Int {
        while true {
            // Try to read out a single header.
            var tempHeader: GameProtocolHeader? = nil
            let headerSize = GameProtocolHeader.encodedSize
            let parsed = framer.parseInput(minimumIncompleteLength: headerSize, maximumLength: headerSize) { buffer, _ -> Int in
                guard let buffer else {
                    return 0
                }
                if buffer.count < headerSize {
                    return 0
                }
                tempHeader = GameProtocolHeader(buffer)
                return headerSize
            }

            // If you can't parse out a complete header, stop parsing and ask for headerSize more bytes.
            guard parsed, let header = tempHeader else {
                return headerSize
            }

            // A peer that completed the (pre-shared-key) TLS handshake could
            // otherwise declare an arbitrary length up to `UInt32.max` (~4 GB),
            // forcing this side to wait/buffer for that many bytes. Reject any
            // declared length past a sane maximum instead of handing it to
            // `deliverInputNoCopy` — see CODE_AUDIT §5.9.
            guard Self.isMessageLengthValid(header.length) else {
                Logger.networking.error("GameProtocol: declared message length \(header.length, privacy: .public) exceeds the \(Self.maximumMessageByteCount, privacy: .public)-byte maximum; failing the connection")
                framer.markFailed(error: .posix(.EMSGSIZE))
                return 0
            }

            // Create an object to deliver the message.
            var messageType = GameMessageType.invalid
            if let parsedMessageType = GameMessageType(rawValue: header.type) {
                messageType = parsedMessageType
            }
            let message = NWProtocolFramer.Message(gameMessageType: messageType)

            // Deliver the body of the message, along with the message object.
            if !framer.deliverInputNoCopy(length: Int(header.length), message: message, isComplete: true) {
                return 0
            }
        }
    }
}

// Extend framer messages to handle storing your command types in the message metadata.
extension NWProtocolFramer.Message {
    convenience init(gameMessageType: GameMessageType) {
        self.init(definition: GameProtocol.definition)
        self["GameMessageType"] = gameMessageType
    }

    var gameMessageType: GameMessageType {
        if let type = self["GameMessageType"] as? GameMessageType {
            return type
        } else {
            return .invalid
        }
    }
}

// FramerProtocol conformance — required so GameProtocol can be used with Framer<T>
// when Apple exposes PSK in the declarative TLS API.
extension GameProtocol: FramerProtocol {}

// Define a protocol header struct to help encode and decode bytes.
struct GameProtocolHeader: Codable {
    let type: UInt32
    let length: UInt32

    init(type: UInt32, length: UInt32) {
        self.type = type
        self.length = length
    }

    init(_ buffer: UnsafeMutableRawBufferPointer) {
        var tempType: UInt32 = 0
        var tempLength: UInt32 = 0
        withUnsafeMutableBytes(of: &tempType) { typePtr in
            typePtr.copyMemory(from: UnsafeRawBufferPointer(start: buffer.baseAddress!.advanced(by: 0),
                                                            count: MemoryLayout<UInt32>.size))
        }
        withUnsafeMutableBytes(of: &tempLength) { lengthPtr in
            lengthPtr.copyMemory(from: UnsafeRawBufferPointer(start: buffer.baseAddress!.advanced(by: MemoryLayout<UInt32>.size),
                                                              count: MemoryLayout<UInt32>.size))
        }
        type = tempType
        length = tempLength
    }

    var encodedData: Data {
        var tempType = type
        var tempLength = length
        var data = Data(bytes: &tempType, count: MemoryLayout<UInt32>.size)
        data.append(Data(bytes: &tempLength, count: MemoryLayout<UInt32>.size))
        return data
    }

    static var encodedSize: Int {
        return MemoryLayout<UInt32>.size * 2
    }
}
