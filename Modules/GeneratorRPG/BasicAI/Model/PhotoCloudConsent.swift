// @copyright André Trettin

import Foundation

/// Whether the photo analysis may send a photo to Private Cloud Compute when the on-device model
/// cannot analyze it. Asked once, then remembered; the analysis view lets people change it.
public enum PhotoCloudConsent: String, Sendable, Equatable {
    case undecided
    case allowed
    case denied

    static let defaultsKey = "photoAnalysisCloudConsent"

    public static func stored(in defaults: UserDefaults = .standard) -> PhotoCloudConsent {
        defaults.string(forKey: defaultsKey).flatMap(PhotoCloudConsent.init(rawValue:)) ?? .undecided
    }

    public func store(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }

    /// Only an explicit "allowed" lets a photo leave the device.
    public var permitsCloud: Bool { self == .allowed }
}
