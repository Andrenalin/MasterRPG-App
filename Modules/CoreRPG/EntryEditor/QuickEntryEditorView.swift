// @copyright André Trettin

import SwiftUI

public struct QuickEntryEditorView<EditController: EntryDataEditable, Inspector: View, PDFOverlay: View>: View {
    public init(root: any ItemRootControllable, editController: EditController, model: EditController.Model, referenceText: DebouncerModel<String>, pdfEditorRoute: any NavigationDestination, @ViewBuilder inspector: () -> Inspector, @ViewBuilder pdfOverlay: () -> PDFOverlay) {
        self.root = root
        self.editController = editController
        self.referenceText = referenceText
        self.pdfEditorRoute = pdfEditorRoute
        self.inspector = inspector()
        self.pdfOverlay = pdfOverlay()
        self.textEditModel = TextEditModel(linkRegisterController: editController.linkRegisterController)
        self.model = model.copy()
    }
    
    let root: any ItemRootControllable
    let editController: EditController
    let referenceText: DebouncerModel<String>
    let pdfEditorRoute: any NavigationDestination
    let inspector: Inspector
    let pdfOverlay: PDFOverlay
    
    @Environment(\.navigator) private var navigator
    @Environment(AppWindowSizeModel.self) private var appSizeModel
    @Environment(ScenesManager.self) private var scenesManager

    private enum Field: Hashable {
        case editor
    }
    @FocusState private var focusedField: Field?

    @State private var textEditModel: TextEditModel

    @State private var model: EditController.Model
    //@State private var entries: [EditController.Model.Entry] = []
    
    @State private var showHelp = false
    @State private var showInspector = false
    @State private var showResult = false
    
    @State private var showEffectedLinksAlert: Bool = false
    @State private var editorModel = RemoveEntryListModel()
    
    public var body: some View {
        ManagedNavigationStack(name: "QuickEntryEditor") {
            contentView
                .overlay(alignment: .top) {
                    VStack {
                        Text("The quick editor allows you to add all entries for the table at once. The first line is the title and the next text represents the content of the entry. An empty line is used to separate entries.", bundle: .module)
                            .padding()
                    }
                    .rowEditColor()
                    .background {
                        RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.8))
                    }
                    .padding(.horizontal)
                    .offset(x: 0, y: -8)
                    .opacity(showHelp ? 1 : 0)
                    .animation(.default, value: showHelp)
                }
                .sizedSheet(isPresented: $showEffectedLinksAlert, idealSize: CGSize(width: 400, height: 600)) {
                    EffectedLinkActionPanelView(root: root, overwrite: true) { rowModels in
                        editorModel.removeItems.removeAll(where: { rowModels.contains($0) })
                        _ = editController.merge(itemId: model.id, entries: model.entries, recoverEntries: editorModel.removeItems)
                        root.editControllable.editorModel.hasChangedEntries += 1
                        root.editControllable.editorModel.sheetRootModel?.updateParent()
                        navigator.dismiss()
                    }
                }
                .navigationTitle(model.name)
                .navigationBarBackButtonHidden(true)
                .navigationBarTitleDisplayModeAll(.inline)
#if os(iOS) || os(visionOS)
                .toolbarBackgroundVisibility(.visible, for: .navigationBar)
#endif
                .toolbar {
                    toolbarContent
                }
#if os(macOS)
                .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
#endif
#if !os(tvOS)
                .toolbarRole(.editor)
#endif
        }
#if os(macOS)
        .frame(minWidth: 800, minHeight: 600)
#endif
    }
}

private extension QuickEntryEditorView {
    private var contentView: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                if showResult {
                    entryListView
                }

                editorView
            }
            .animation(.bouncy, value: showResult)
            
            if showInspector {
                inspector
                    .frame(width: 300)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
#if !os(macOS)
                    .toolbarVisibility(.visible, for: .navigationBar)
#endif

            }
        }
        .animation(.bouncy, value: showInspector)
        .onAppear {
            referenceText.input = initialText
            focusedField = .editor
            textEditModel.reset(text: referenceText.input, source: ItemRowModel(itemId: model.id, typeId: editController.itemControllable.config.module))
        }
        .onChange(of: referenceText.output) {
            let parsedEntries = createMultiLineEntries(referenceText.output)
            let entries = editController.merge(itemId: model.id, entries: parsedEntries)
            model.entries <=> entries
        }
    }

    private var entryListView: some View {
        List {
            ForEach(model.entries, id: \.id) { entry in
                EntryEditRow(root: root, editController: editController, itemId: model.id, entry: entry, cacheItemListModel: editController.cacheItemListModel, listDisplayModel: root.folderListControllable.listDisplayModel, searchModel: root.searchModel)
            }
        }
#if !os(tvOS)
        .scrollContentBackground(.hidden)
#endif
        .environment(SearchModel.preview())
        .overlay {
            pdfOverlay
        }
    }
    
    private var editorView: some View {
        VStack(alignment: .leading, spacing: 8) {
#if !os(tvOS)
            TextEditorLinkView(model: textEditModel, maxHeight: .infinity)
                .focused($focusedField, equals: .editor)
                .onChange(of: textEditModel.attributedText) {
                    textEditModel.updateLinks()
                }
                .onChange(of: textEditModel.text) {
                    referenceText.input = textEditModel.text
                }
                .padding(.horizontal, 4)
#endif
        }
    }
    
    private var initialText: String {
        parser.format(model.entries.map { (name: $0.name, content: $0.content) })
    }
}

#Preview {
    QuickEntryEditorView(
        root: ItemRootController.fake,
        editController: FakeEditController.fake,
        model: FakeItemModel.empty,
        referenceText: DebouncerModel(initialValue: ""),
        pdfEditorRoute: InternalRoute.removeAlert,
        inspector: { EmptyView() },
        pdfOverlay: { EmptyView() }
    )
}

private extension QuickEntryEditorView {
    private var parser: EntryTextParser { EntryTextParser() }

    func createMultiLineEntries(_ text: String) -> [EditController.Model.Entry] {
        parser.parse(text).compactMap { parsed in
            createEntry(with: parsed.name, content: parsed.content)
        }
    }

    private func createEntry(with name: String, content: String) -> EditController.Model.Entry? {
        guard !name.isEmpty else { return nil }
        return editController.create(name: name, content: content)
    }

    func removeLineBreak(_ text: String) -> String {
        parser.removeLineBreaks(from: text)
    }
}

private extension QuickEntryEditorView {
    @ToolbarContentBuilder var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(role: .cancel) {
                navigator.dismiss()
            } label: {
                Image(systemName: "xmark.circle")
            }
        }

#if os(macOS)
        ToolbarItemGroup(placement: .automatic) {
            showHelpButton
            Divider()
            removeLineBreak
            showResultButton
            Divider()
            pdfButton
            if canShowInspector {
                showInspectorButton
            }
        }
#else
        ToolbarItem(placement: .secondaryActionAll) {
            secondaryActionMenu
        }
#endif

        ToolbarItem(placement: .confirmationAction) {
            ControlGroup {
                Button(role: .confirm) {
                    let parsedEntries = createMultiLineEntries(referenceText.input)
                    let entries = editController.merge(itemId: model.id, entries: parsedEntries)
                    model.entries = entries
                    editorModel.removeItems = editController.merge(itemId: model.id, entries: entries, recoverEntries: nil)
                    if editorModel.removeItems.isEmpty {
                        root.editControllable.editorModel.hasChangedEntries += 1
                        root.editControllable.editorModel.sheetRootModel?.updateParent()
                        navigator.dismiss()
                    } else {
                        root.removeEntryListModel.removeItems = editorModel.removeItems
                        showEffectedLinksAlert.toggle()
                    }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
            }
        }
    }
    
    @ViewBuilder var secondaryActionMenu: some View {
        ControlGroup {
            showHelpButton
        }
        
        ControlGroup {
            removeLineBreak
            showResultButton
        }
        
        ControlGroup {
            pdfButton
            if canShowInspector {
                showInspectorButton
            }
        }
    }
    
    var canShowInspector: Bool {
        valueFor(iOS: appSizeModel.mode == .regular, macOS: true, tvOS: true, visionOS: false)
    }
        
    var pdfButton: some View {
        Button {
#if os(macOS) || os(visionOS)
            scenesManager.openWindow(SceneId(rawValue: NetworkModules.pdf.linkWindowId))
#else
            withAnimation { showResult <=> true }
            navigator.navigate(to: pdfEditorRoute, method: .sheet)
#endif
        } label: {
            Label { Text("Extract PDF", bundle: .module) } icon: { Image(systemName: "book") }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var removeLineBreak: some View {
        Button {
            withAnimation {
                referenceText.input = removeLineBreak(referenceText.output)
            }
        } label: {
            Label {
                Text("Remove Line Breaks", bundle: .module)
            } icon: {
                Image(systemName: "text.insert")
            }
        }
    }

    var showInspectorButton: some View {
        Button {
            withAnimation { showInspector.toggle() }
        } label: {
            Label {
                Text("Show Inspector", bundle: .module)
            } icon: {
                Image(systemName: "scope")
            }
        }
    }

    var showHelpButton: some View {
        Button {
            withAnimation { showHelp.toggle() }
        } label: {
            Label {
                Text("Show Help", bundle: .module)
            } icon: {
                Image(systemName: "questionmark")
            }
        }
    }
    
    var showResultButton: some View {
        Toggle(isOn: $showResult) {
            Label {
                Text("Show Result", bundle: .module)
            } icon: {
                Image(systemName: showResult ? "rectangle.split.2x1" : "rectangle.split.2x1.slash")
                    .contentTransition(.symbolEffect(.automatic))
            }
        }
    }
    
}
