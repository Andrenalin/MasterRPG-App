// @copyright André Trettin

import CoreRPG
import Foundation

/// What a message that cannot be decoded says about the app version on the other side of a
/// connection. Only envelope version `GameNetworkModel.currentVersion` decodes, so a device with
/// another build would otherwise look connected and receive nothing. See
/// CODE_AUDIT_Game_Shareplay §5.9.
enum GameVersionMismatch: Hashable, Sendable {
    /// The peer sent an envelope of another wire version.
    case peerWrites(version: Int)
    /// The peer told us it cannot read our envelopes; it reads `version`.
    case peerReads(version: Int)

    /// Whether this device is the older one and has to be updated.
    var thisDeviceNeedsUpdate: Bool {
        switch self {
        case let .peerWrites(version), let .peerReads(version):
            version > GameNetworkModel.currentVersion
        }
    }

    private struct Probe: Decodable {
        let version: Int?
        let incompatibleNotice: Int?
    }

    /// The mismatch `data` shows, or `nil` when it is no envelope of another version and no
    /// notice (plain garbage, a truncated frame).
    static func detect(in data: Data?) -> GameVersionMismatch? {
        guard let data, let probe = try? JSONCoding.decoder.decode(Probe.self, from: data) else { return nil }
        if let supported = probe.incompatibleNotice {
            return supported == GameNetworkModel.currentVersion ? nil : .peerReads(version: supported)
        }
        if let version = probe.version, version != GameNetworkModel.currentVersion {
            return .peerWrites(version: version)
        }
        return nil
    }

    /// The text for the game log of this device.
    var logText: String {
        if thisDeviceNeedsUpdate {
            String(localized: "Another device uses a newer version of the app and its messages cannot be read. Update the app on this device.", bundle: .module)
        } else {
            String(localized: "Another device uses an older version of the app and cannot take part. Ask its owner to update the app.", bundle: .module)
        }
    }
}

/// The minimal answer to an envelope of another wire version. It carries the one version this
/// device reads, in a shape every build that knows this notice can read whatever its envelope.
struct GameVersionNotice: Codable, MessageMapper, Equatable {
    var incompatibleNotice: Int = GameNetworkModel.currentVersion
}
