// @copyright André Trettin

import SwiftUI

/// Labels and symbols of `InlineImporterView`'s importer buttons. The fan geometry lives in
/// CoreRPG's `ImporterFanView`. See CODE_AUDIT §9.10, CODE_AUDIT_Folder §9.6.
enum PhotoImporterButtonType: String {
    case file, url, library, camera, playground

    var systemImage: String {
        switch self {
        case .file:
            return "folder"
        case .url:
            return "link.badge.plus"
        case .library:
            return "photo.stack"
        case .camera:
            return "camera"
        case .playground:
            return "apple.image.playground"
        }
    }

    var localizedLabel: String {
        switch self {
        case .file:
            String(localized: "File", bundle: .module)
        case .url:
            String(localized: "URL", bundle: .module)
        case .library:
            String(localized: "Photo Library", bundle: .module)
        case .camera:
            String(localized: "Camera", bundle: .module)
        case .playground:
            String(localized: "Image Playground", bundle: .module)
        }
    }
}
