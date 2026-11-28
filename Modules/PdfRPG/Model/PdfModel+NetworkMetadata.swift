// @copyright André Trettin

import CoreRPG
import Foundation

/// A metadata edit (name, description, entries) reaches players who already hold the
/// file: it changes the package version, not the file's asset version. See CODE_AUDIT_Edit_Save §5.10.
extension PdfModel: NetworkMetadataDigestible {
    public var networkMetadataDigest: Int {
        NetworkPackageVersion.metadataDigest(name: name, description: description, entries: entries)
    }
}
