// @copyright André Trettin

import CoreRPG
import Foundation

/// A metadata edit (name, description, rotation, entries) reaches players who already hold the
/// file: it changes the package version, not the file's asset version. See CODE_AUDIT_Edit_Save §5.10.
extension PhotoModel: NetworkMetadataDigestible {
    public var networkMetadataDigest: Int {
        NetworkPackageVersion.metadataDigest(name: name, description: description, entries: entries, degrees: degrees)
    }
}
