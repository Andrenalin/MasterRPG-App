// @copyright André Trettin

import SwiftUI

public struct TableRootSheet<LinkType: LinkDataTransferable, BottomAccessory: View>: View {
    public init(
        root: ItemRootController,
        itemId: UUID,
        module: NetworkModules,
        configuration: ViewerConfiguration,
        searchContext: SheetSearchContext? = nil,
        dismissAction: (() -> Void)? = nil
    ) where LinkType == LinkDiceData, BottomAccessory == EmptyView {
        self.init(
            root: root,
            itemId: itemId,
            module: module,
            configuration: configuration,
            searchContext: searchContext,
            dismissAction: dismissAction,
            isEditor: false,
            linkTypes: LinkDiceData.self,
            sheetConfiguration: .init(),
            aiAssistantContent: { _ in EmptyView() }
        )
    }

    public init(
        root: ItemRootController,
        itemId: UUID,
        module: NetworkModules,
        configuration: ViewerConfiguration,
        searchContext: SheetSearchContext? = nil,
        dismissAction: (() -> Void)? = nil,
        isEditor: Bool,
        linkTypes: LinkType.Type,
        sheetConfiguration: SheetRootViewConfiguration = .init(showsAIAssistant: true),
        @ViewBuilder aiAssistantContent: @escaping (SheetRootModel) -> BottomAccessory
    ) {
        guard let rootManager = root.rootManager else {
            preconditionFailure("TableRootSheet requires ItemRootController.rootManager to be set before presentation.")
        }

        self.root = root
        self.configuration = configuration
        self.searchContext = searchContext
        self.dismissAction = dismissAction
        self.isEditor = isEditor
        self.linkTypes = linkTypes
        self.sheetConfiguration = sheetConfiguration
        self.aiAssistantContent = aiAssistantContent
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
    let searchContext: SheetSearchContext?
    let dismissAction: (() -> Void)?
    let isEditor: Bool
    let linkTypes: LinkType.Type
    let sheetConfiguration: SheetRootViewConfiguration
    let aiAssistantContent: (SheetRootModel) -> BottomAccessory

    @Environment(AppWindowSizeModel.self) private var appSizeModel
    @Environment(AppGameStateModel.self) private var appGameStateModel

    @Environment(\.dismiss) var dismiss

    @State private var sheetRootModel: SheetRootModel
    
    public var body: some View {
        @Bindable var sheetRootModel = sheetRootModel

        TableSheetView(
            root: root,
            model: sheetRootModel,
            addSearchable: configuration.addToolbar && !configuration.inlineSearch,
            isEditor: isEditor,
            linkTypes: linkTypes,
            configuration: sheetConfiguration,
            aiAssistantContent: {
                aiAssistantContent(sheetRootModel)
            }
        )
#if os(macOS) || os(visionOS)
            .padding(.top)
#endif
            .themedSurface()
#if os(visionOS)
            .glassBackgroundEffect()
#endif
            .overlay(alignment: .topTrailing) {
                if configuration.inlineSearch {
                    InlineSheetSearchControl(
                        module: root.configurable.module,
                        searchText: $sheetRootModel.searchText
                    )
                    .padding()
                }
            }
            .toolbar {
                toolbarContent
            }
            .navigationTitle(Text(verbatim: sheetRootModel.sheetModel.name))
            .onAppear {
                searchContext?.attachResults(sheetRootModel)
            }
            .onDisappear {
                searchContext?.detachResults(sheetRootModel)
            }
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
    TableRootSheet(root: ItemRootController.fake, itemId: UUID(), module: .none, configuration: .init())
}
