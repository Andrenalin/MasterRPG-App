// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct ViewController: Sendable {
    weak var _root: AudioRootModel?
    var root: AudioRootModel {
        _root.unsafelyUnwrapped
    }
    
    public let goupViewType: GroupViewType = .item
    public let thumbnailRowViewType: ThumbnailRowViewType = .none
}

extension ViewController: ViewControllable {}

// MARK: Viewer

public extension ViewController {
    @MainActor
    func linkWindow() -> some View {
        LinkRootView(isInspector: false)
            .environment(root)
    }
}
