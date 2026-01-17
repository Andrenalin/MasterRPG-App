// @copyright André Trettin

import CoreRPG

import SwiftData
import SwiftUI

public enum AudioFactory {
    @MainActor public static func root(tagController: TagController) -> AudioRootModel {
        AudioRootModel(tagController: tagController)
    }

    @MainActor public static func rootView() -> some View {
        AudioRootView()
    }

    @MainActor @ViewBuilder public static func detailView(root: AudioRootModel) -> some View {
        ItemSplitDetailRootView(root: root.rootController)
    }
}
