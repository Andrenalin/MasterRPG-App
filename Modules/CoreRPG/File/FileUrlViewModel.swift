//
//  FileUrlViewModel.swift
//  MasterRPG
//
//  Created by Andre Trettin on 8/7/2568 BE.
//


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

    var hasDataText: String {
        hasData ? "Yes" : "No"
    }

    var hasDataLabel: LocalizedStringResource {
        hasData ? "Yes" : "No"
    }

    var isDownloadedIcon: String {
        guard let isDownloaded else { return "icloud.slash" }
        return isDownloaded ? "checkmark.icloud" : "xmark.icloud"
    }

    var hasAccessIcon: String {
        hasAccess ? "lock.open" : "lock"
    }
}
