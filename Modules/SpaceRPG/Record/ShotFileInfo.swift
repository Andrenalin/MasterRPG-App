/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Value type for holding the various info about a particular snapshot file.
*/

import Foundation
import SwiftUI

struct ShotFileInfo {
    let fileUrl: URL
    let id: UInt32

    @MainActor init?(url: URL) {
        fileUrl = url
        guard let shotId = CaptureFolderManager.parseShotId(url: url) else {
            return nil
        }

        id = shotId
    }
}

extension ShotFileInfo: Identifiable { }
