// @copyright André Trettin

import SwiftUI

public struct TableRootSheet<LinkType: LinkDataTransferable, BottomAccessory: View>: View {
    public init(
        root: ItemRootController,
        itemId: UUID,
        module: NetworkModules,
        configuration: ViewerConfiguration,
        dismissAction: (() -> Void)? = nil
    ) where LinkType == LinkDiceData, BottomAccessory == EmptyView {
        self.init(
            root: root,
            itemId: itemId,
            module: module,
            configuration: configuration,
            dismissAction: dismissAction,
            isEditor: false,
            linkTypes: LinkDiceData.self,
            bottomAccessory: { _ in EmptyView() }
        )
    }

    public init(
        root: ItemRootController,
        itemId: UUID,
        module: NetworkModules,
        configuration: ViewerConfiguration,
        dismissAction: (() -> Void)? = nil,
        isEditor: Bool,
        linkTypes: LinkType.Type,
        @ViewBuilder bottomAccessory: @escaping (SheetRootModel) -> BottomAccessory
    ) {
        guard let rootManager = root.rootManager else {
            preconditionFailure("TableRootSheet requires ItemRootController.rootManager to be set before presentation.")
        }

        self.root = root
        self.configuration = configuration
        self.dismissAction = dismissAction
        self.isEditor = isEditor
        self.linkTypes = linkTypes
        self.bottomAccessory = bottomAccessory
        self._sheetRootModel = State(
            wrappedValue: SheetRootModel(
                rootManager: rootManager,
                linkControllable: root.linkControllable,
                sheetControllable: root.sheetControllable,
                itemId: itemId,
                isEditor: isEditor
            )
        )
    }
        
    let root: ItemRootController
    let configuration: ViewerConfiguration
    let dismissAction: (() -> Void)?
    let isEditor: Bool
    let linkTypes: LinkType.Type
    let bottomAccessory: (SheetRootModel) -> BottomAccessory

    @Environment(AppWindowSizeModel.self) private var appSizeModel
    @Environment(AppGameStateModel.self) private var appGameStateModel

    @Environment(\.dismiss) var dismiss

    @State private var sheetRootModel: SheetRootModel
    @State private var generationSelection: WindowItemSelection?
    
    public var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        @Bindable var sheetRootModel = sheetRootModel

        TableSheetView(
            root: root,
            model: sheetRootModel,
            addSearchable: valueFor(iOS: true, macOS: false, tvOS: true, visionOS: true),
            isEditor: isEditor,
            linkTypes: linkTypes
        )
#if os(macOS) || os(visionOS)
            .padding(.top)
#endif
            .themedSurface()
#if os(visionOS)
            .glassBackgroundEffect()
#endif
            .overlay(alignment: .topTrailing) {
                if configuration.isGame && valueFor(iOS: false, macOS: true, tvOS: false, visionOS: false) {
                    InlineSheetSearchControl(
                        module: root.configurable.module,
                        searchText: $sheetRootModel.searchText
                    )
                    .padding()
                }
            }
            .overlay(alignment: .bottomTrailing) {
                bottomAccessory(sheetRootModel)
                    .padding(.horizontal)
                    .padding(.bottom)
            }
            .toolbar {
                toolbarContent
            }
            .applyIf(!configuration.isGame) {
                $0.navigationTitle(Text(verbatim: sheetRootModel.sheetModel.name))
            }
            .navigationVisibility(true)
            .itemGenerationPresentation(
                root: root,
                selection: $generationSelection
            )
    }
}

private extension TableRootSheet {
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        if configuration.closeButton {
            ToolbarItem(placement: .cancellationAction) {
                closeButton
            }
        }
    }

    var closeButton: some View {
        Button {
            if let dismissAction {
                dismissAction()
            } else {
                dismiss()
            }
        } label: {
            Image(systemName: "xmark.circle")
        }
        .accessibilityLabel(Text("Close", bundle: .module))
    }
}

#Preview {
    TableRootSheet(root: ItemRootController.fake, itemId: SheetRootModel.fake.sheetModel.id, module: .none, configuration: .init())
        .environment(AppWindowSizeModel())
        .environment(AppGameStateModel())
        .environment(ScenesManager())
}
