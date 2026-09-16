// @copyright André Trettin

import SwiftUI

/// Fan-out layout and labeling for `InlineImporterView`'s five importer buttons.
/// Extracted from `InlineImporterView.swift` — self-contained geometry/labeling with
/// nothing to do with view rendering. See CODE_AUDIT §9.10.
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

    var duration: CGFloat {
        switch self {
        case .file:
            return 0.3
        case .url:
            return 0.35
        case .library:
            return 0.4
        case .camera:
            return 0.5
        case .playground:
            return 0.6
        }
    }

    func offset(expanded: Bool, layoutDown: Bool) -> CGSize {
        guard expanded else {
            return .zero
        }

        switch self {
        case .file:
            return offset(atIndex: 0, layoutDown: layoutDown)
        case .url:
            return offset(atIndex: 1, layoutDown: layoutDown)
        case .library:
            return offset(atIndex: 2, layoutDown: layoutDown)
        case .camera:
            return offset(atIndex: 3, layoutDown: layoutDown)
        case .playground:
            return offset(atIndex: 4, layoutDown: layoutDown)
        }
    }

    private func offset(atIndex index: Int, layoutDown: Bool) -> CGSize {
        let radius: CGFloat = 120
        let startAngleDeg = -180.0
        let step = 90.0 / Double(5 - 1)

        let angleDeg = startAngleDeg + (Double(index) * step)
        let angleRad = angleDeg * .pi / 180

        let x = cos(angleRad) * radius
        let y = sin(angleRad) * radius * (layoutDown ? -1 : 1)

        return CGSize(width: x, height: y)
    }
}
