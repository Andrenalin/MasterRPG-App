// @copyright André Trettin

import Foundation
import SwiftUI

@MainActor
struct FileUrlViewModel: Equatable, Hashable, Identifiable, Sendable {
    enum FileType: Equatable, Hashable, Comparable {
        case folder
        case file

        var icon: String {
            switch self {
            case .folder:
                return "folder.badge.plus"
            case .file:
                return "doc.badge.plus"
            }
        }
    }

    let id: UUID
    var name: String
    var path: String
    var type: FileType
    var hasData: Bool
    var hasAccess: Bool
    var isDownloaded: Bool?
    var fileUrl: FileUrl?

}
