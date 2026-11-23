// @copyright André Trettin

import Foundation

/// What identifies one load of a 3D model in the viewer: the item, the version of its file and
/// the number of retries. The viewer is keyed on it, so a file replaced in place reloads (the
/// model is a class that is mutated in place) and a failed load can be tried again, like
/// `PdfViewerLoadKey`. See CODE_AUDIT_28 §5.20.
struct SpaceViewerLoadKey: Hashable {
    let id: UUID
    let version: Int
    var attempt = 0
}
