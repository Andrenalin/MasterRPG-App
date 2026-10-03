// @copyright André Trettin

import SwiftUI

// Hoisted out of `QuickEntryEditorView` (rather than nested, as it was before) because a
// `@FocusState`'s field type must be nameable from the extracted subview structs below —
// and a type nested inside a *generic* type can't be referenced from unrelated top-level
// declarations in the same file without fully specializing the outer type's generic
// parameters. `fileprivate` keeps it scoped to this file only, matching its previous
// `private` intent.
fileprivate enum QuickEntryEditorFocusField: Hashable {
    case editor
}

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
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @FocusState private var focusedField: QuickEntryEditorFocusField?

    @State private var textEditModel: TextEditModel

    @State private var model: EditController.Model
    
    @State private var showHelp = false
    @State private var showInspector = false
    @State private var showResult = false
    
    @State private var showAffectedLinksAlert: Bool = false
    @State private var editorModel = RemoveEntryListModel()
    
    public var body: some View {
        ManagedNavigationStack(name: "QuickEntryEditor") {
            QuickEntryEditorContentView(root: root, editController: editController, referenceText: referenceText, inspector: inspector, pdfOverlay: pdfOverlay, model: model, textEditModel: textEditModel, initialText: initialText, focusedField: $focusedField, createMultiLineEntries: createMultiLineEntries, showResult: $showResult, showInspector: $showInspector)
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
                    .allowsHitTesting(showHelp)
                    .accessibilityHidden(!showHelp)
                    .animation(accessibilityReduceMotion ? nil : .default, value: showHelp)
                }
                .sizedSheet(isPresented: $showAffectedLinksAlert, idealSize: CGSize(width: 400, height: 600)) {
                    AffectedLinkActionPanelView(root: root, overwrite: true) { rowModels in
                        editorModel.removeItems.removeAll(where: { rowModels.contains($0) })
                        // The standalone item editor always persists, even while a game
                        // is running — unlike in-game quick-edit surfaces, which stay memory-only.
                        _ = editController.merge(itemId: model.id, entries: model.entries, recoverEntries: editorModel.removeItems, forceSave: true)
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
                .padding()
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
    private var initialText: String {
        parser.format(model.entries.map { (name: $0.name, content: $0.content) })
    }
}

#Preview {
    let fixture = FakeItemRootControllerFixture()
    QuickEntryEditorView(
        root: fixture.root,
        editController: fixture.editController,
        model: FakeItemModel.empty,
        referenceText: DebouncerModel(initialValue: ""),
        pdfEditorRoute: InternalRoute.removeAlert,
        inspector: { EmptyView() },
        pdfOverlay: { EmptyView() }
    )
    .environment(AppWindowSizeModel())
    .environment(ScenesManager())
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
            .accessibilityLabel(Text("Cancel", bundle: .module))
        }

#if os(macOS)
        ToolbarItemGroup(placement: .automatic) {
            QuickEntryEditorShowHelpButtonView(showHelp: $showHelp)
            Divider()
            QuickEntryEditorRemoveLineBreakButtonView(referenceText: referenceText, removeLineBreak: removeLineBreak)
            QuickEntryEditorShowResultButtonView(showResult: $showResult)
            Divider()
            QuickEntryEditorPdfButtonView(pdfEditorRoute: pdfEditorRoute, showResult: $showResult)
            if canShowInspector {
                QuickEntryEditorShowInspectorButtonView(showInspector: $showInspector)
            }
        }
#else
        ToolbarItem(placement: .secondaryActionAll) {
            QuickEntryEditorSecondaryActionMenuView(pdfEditorRoute: pdfEditorRoute, canShowInspector: canShowInspector, referenceText: referenceText, removeLineBreak: removeLineBreak, showHelp: $showHelp, showResult: $showResult, showInspector: $showInspector)
        }
#endif

        ToolbarItem(placement: .confirmationAction) {
            ControlGroup {
                Button(role: .confirm) {
                    let parsedEntries = createMultiLineEntries(referenceText.input)
                    let entries = editController.merge(itemId: model.id, entries: parsedEntries)
                    model.entries = entries
                    // The standalone item editor always persists, even while a game
                    // is running — unlike in-game quick-edit surfaces, which stay memory-only.
                    editorModel.removeItems = editController.merge(itemId: model.id, entries: entries, recoverEntries: nil, forceSave: true)
                    if editorModel.removeItems.isEmpty {
                        root.editControllable.editorModel.sheetRootModel?.updateParent()
                        navigator.dismiss()
                    } else {
                        root.removeEntryListModel.removeItems = editorModel.removeItems
                        showAffectedLinksAlert.toggle()
                    }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .accessibilityLabel(Text("Apply", bundle: .module))
            }
        }
    }
    
    var canShowInspector: Bool {
        valueFor(iOS: appSizeModel.mode == .regular, macOS: true, tvOS: true, visionOS: false)
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct QuickEntryEditorContentView<EditController: EntryDataEditable, Inspector: View, PDFOverlay: View>: View {
    let root: any ItemRootControllable
    let editController: EditController
    let referenceText: DebouncerModel<String>
    let inspector: Inspector
    let pdfOverlay: PDFOverlay
    let model: EditController.Model
    let textEditModel: TextEditModel
    let initialText: String
    let focusedField: FocusState<QuickEntryEditorFocusField?>.Binding
    let createMultiLineEntries: (String) -> [EditController.Model.Entry]
    @Binding var showResult: Bool
    @Binding var showInspector: Bool

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                if showResult {
                    QuickEntryEditorEntryListView(root: root, editController: editController, model: model, pdfOverlay: pdfOverlay)
                }

                QuickEntryEditorEditorView(textEditModel: textEditModel, referenceText: referenceText, focusedField: focusedField)
            }
            .animation(accessibilityReduceMotion ? nil : .bouncy, value: showResult)

            #if !os(iOS) && !os(macOS)
            if showInspector {
                inspector
                    .frame(width: 300)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .navigationVisibility(true)

            }
            #endif
        }
        .animation(accessibilityReduceMotion ? nil : .bouncy, value: showInspector)
#if os(iOS) || os(macOS)
        .inspector(isPresented: $showInspector) {
            inspector
                .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
#endif
        .onAppear {
            referenceText.input = initialText
            focusedField.wrappedValue = .editor
            textEditModel.reset(text: referenceText.input, source: ItemRowModel(itemId: model.id, typeId: editController.itemControllable.config.module))
        }
        .onChange(of: referenceText.output) {
            let parsedEntries = createMultiLineEntries(referenceText.output)
            let entries = editController.merge(itemId: model.id, entries: parsedEntries)
            model.entries <=> entries
        }
    }
}

private struct QuickEntryEditorEntryListView<EditController: EntryDataEditable, PDFOverlay: View>: View {
    let root: any ItemRootControllable
    let editController: EditController
    let model: EditController.Model
    let pdfOverlay: PDFOverlay

    var body: some View {
        List {
            ForEach(model.entries, id: \.id) { entry in
                EntryEditRow(root: root, editController: editController, itemId: model.id, entry: entry, cacheItemListModel: editController.cacheItemListModel, listDisplayModel: root.folderListControllable.listDisplayModel, searchModel: root.searchModel, resolvedModel: model)
            }
        }
        .themedListSurface()
        .environment(SearchModel.preview())
        .overlay {
            pdfOverlay
        }
    }
}

private struct QuickEntryEditorEditorView: View {
    let textEditModel: TextEditModel
    let referenceText: DebouncerModel<String>
    let focusedField: FocusState<QuickEntryEditorFocusField?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
#if !os(tvOS)
            TextEditorLinkView(model: textEditModel, maxHeight: .infinity)
                .focused(focusedField, equals: .editor)
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
}

private struct QuickEntryEditorSecondaryActionMenuView: View {
    let pdfEditorRoute: any NavigationDestination
    let canShowInspector: Bool
    let referenceText: DebouncerModel<String>
    let removeLineBreak: (String) -> String
    @Binding var showHelp: Bool
    @Binding var showResult: Bool
    @Binding var showInspector: Bool

    @ViewBuilder var body: some View {
        ControlGroup {
            QuickEntryEditorShowHelpButtonView(showHelp: $showHelp)
        }

        ControlGroup {
            QuickEntryEditorRemoveLineBreakButtonView(referenceText: referenceText, removeLineBreak: removeLineBreak)
            QuickEntryEditorShowResultButtonView(showResult: $showResult)
        }

        ControlGroup {
            QuickEntryEditorPdfButtonView(pdfEditorRoute: pdfEditorRoute, showResult: $showResult)
            if canShowInspector {
                QuickEntryEditorShowInspectorButtonView(showInspector: $showInspector)
            }
        }
    }
}

private struct QuickEntryEditorPdfButtonView: View {
    let pdfEditorRoute: any NavigationDestination
    @Binding var showResult: Bool

    @Environment(\.navigator) private var navigator
    @Environment(ScenesManager.self) private var scenesManager

    var body: some View {
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
}

private struct QuickEntryEditorRemoveLineBreakButtonView: View {
    let referenceText: DebouncerModel<String>
    let removeLineBreak: (String) -> String

    var body: some View {
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
}

private struct QuickEntryEditorShowInspectorButtonView: View {
    @Binding var showInspector: Bool

    var body: some View {
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
}

private struct QuickEntryEditorShowHelpButtonView: View {
    @Binding var showHelp: Bool

    var body: some View {
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
}

private struct QuickEntryEditorShowResultButtonView: View {
    @Binding var showResult: Bool

    var body: some View {
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
