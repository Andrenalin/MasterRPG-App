// @copyright André Trettin

import CoreRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(CharacterRootModel.self) var root
    DetailListView(
        root: root,
        model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]),
        folderListController: root.folderListController
    )
}

struct DetailListView: View {
    let root: CharacterRootModel
    let model: ValueModel
    let folderListController: any FolderListControllable

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        DetailFolderListView(root: root, model: model, folderListController: folderListController)
#if !os(tvOS)
            .toolbar {
                DetailListToolbarContent(root: root, model: model)
            }
#endif
            .themedSurface()
            .moduleTint(root.configurable.module)
            .userActivity(UserActivity.bundleIdentifierType, isActive: true) { activity in
                UserActivity.addPayLoad(for: activity, title: model.name, module: root.config.module, itemId: model.id)
#if !os(tvOS)
                root.addSiriContext(to: activity, itemId: model.id)
#endif
            }
#if !os(tvOS)
            .task(id: model.id) {
                await root.donateSiriViewingIntent(for: model.id)
            }
            .onChange(of: model.photoId) {
                withAnimation { root.editController.editorModel.sheetRootModel?.updateFromRoot() }
            }
            .sheetAIAssistant(
                generatorRoot: root.generatorRoot,
                rootModel: root.editController.editorModel.sheetRootModel,
                module: root.configurable.module
            )
#endif
    }
}

#if !os(tvOS)
/// The detail toolbar: "Extract Information" and, on iOS, the keyboard's link buttons.
struct DetailListToolbarContent: ToolbarContent {
    let root: CharacterRootModel
    let model: ValueModel

    @ToolbarContentBuilder var body: some ToolbarContent {
        ToolbarItemGroup(placement: .secondaryActionAll) {
            if !model.specialCategory && !root.openFileWindowModel.showItem {
                CharacterExtractToolBarButton(model: model)
            }
        }
#if os(iOS)
        // Disabled, not removed, while the AI composer is open: an emptied keyboard toolbar makes
        // UIKit swap the input accessory view during the focus-change keyboard animation, which
        // crashes on iPad (NSLayoutConstraint in -[UIInputWindowControllerHostingItem
        // inputAssistantHostView]).
        ToolbarItemGroup(placement: .keyboard) {
            ForEach(root.editorLinkModel.modulesRow, id: \.self) { module in
                AddLinkButton(root: root, model: model, module: module)
                    .disabled(root.editController.editorModel.sheetRootModel?.isAIModeActive == true)
            }
        }
#endif
    }
}

struct CharacterExtractToolBarButton: View {
    let model: ValueModel

    var body: some View {
        ExtractInformationToolBarButton(
            route: CharacterDetailRoute.characterExtraction(model.id),
            isDisabled: model.entries.allSatisfy(\.isGroupHidden)
        )
    }
}
#endif
