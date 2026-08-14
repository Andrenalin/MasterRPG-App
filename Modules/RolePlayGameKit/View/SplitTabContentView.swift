// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Renders a single `RootRoute` tab's content, wrapping it in a `NavigationSplitView`
/// when the route has a detail view, or showing it flat otherwise.
///
/// Shared between `SplitEditorNavigation` and `SplitVisionNavigation`, which both
/// present the same set of module tabs in a split layout on macOS/visionOS.
struct SplitTabContentView: View {
    let tab: RootRoute
    let appModel: AppModel
    @Binding var column: NavigationSplitViewVisibility
    @Binding var preferredCompactColumn: NavigationSplitViewColumn

    var body: some View {
        if tab.hasDetailView {
            NavigationSplitView(columnVisibility: $column, preferredCompactColumn: $preferredCompactColumn) {
                contentView
            } detail: {
                SplitDetailView(module: tab.module)
                    .environment(appModel.itemRootController(for: tab.module))
            }
        } else {
            contentView
        }
    }

    private var contentView: some View {
        ManagedPresentationView {
            tab
        }
        .environment(appModel.itemRootController(for: tab.module))
    }
}

/// The set of quick-open buttons for every module window, shown in the trailing ornament
/// on visionOS. Shared between `SplitEditorNavigation` and `SplitVisionNavigation`.
struct ModuleWindowMenuView: View {
    var body: some View {
        Group {
            MenuWindowButtonView(valueType: .adventure)
            MenuWindowButtonView(valueType: .audio)
            MenuWindowButtonView(valueType: .dice)
            MenuWindowButtonView(valueType: .map)
            MenuWindowButtonView(valueType: .pdf)
            MenuWindowButtonView(valueType: .photo)
            MenuWindowButtonView(valueType: .rule)
            MenuWindowButtonView(valueType: .space)
            MenuWindowButtonView(valueType: .table)
            MenuWindowButtonView(valueType: .value)
            MenuWindowButtonView(valueType: .weather)
        }
    }
}
