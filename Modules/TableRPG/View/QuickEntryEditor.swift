// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import PdfRPG
import SwiftUI

struct QuickEntryEditor: View {
    init(editController: EditController) {
        self.editController = editController
        self.textEditModel = TextEditModel(linkRegisterController: editController.linkRegisterControllable)
    }
    
    let editController: EditController
    
    @Environment(TableRootModel.self) private var root
    @Environment(\.dismiss) private var dismiss
    @Environment(\.navigator) private var navigator
    @Environment(\.appSizeMode) private var appSizeMode
    
#if os(macOS) || os(visionOS)
    @Environment(\.openWindow) private var openWindow
#endif

    private enum Field: Hashable {
        case editor
    }
    @FocusState private var focusedField: Field?

    @State private var textEditModel: TextEditModel

    @State private var referenceText = DebouncerModel(initialValue: "", delay: 2)
    @State private var model: TableModel = .empty
    @State private var entries: [TableEntryModel] = []
    
    @State private var showHelp = false
    @State private var showInspector = false
    @State private var showResult = false
    
    @State private var showEffectedLinksAlert: Bool = false
    @State private var editorModel = RemoveEntryListModel()
    
    var body: some View {
        ManagedNavigationStack(name: "TableQuickEditor") {
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
                    EffectedLinkAction(itemControllable: root.itemController, removeEntryList: editorModel, overwrite: true) { rowModels in
                        editorModel.removeItems.removeAll(where: { rowModels.contains($0) })
                        _ = await editController.merge(entries: entries, recoverEntries: editorModel.removeItems)
                        dismiss()
                    }
                }
                .navigationTitle(editController.model.name)
                .navigationBarBackButtonHidden(true)
#if os(iOS) || os(visionOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackgroundVisibility(.visible, for: .navigationBar)
#endif
                .toolbar {
                    toolbarContent
                }
#if !os(tvOS)
                .toolbarRole(.editor)
#endif
                .onChange(of: editController.model, initial: true) {
                    model = editController.model.copy()
                }
        }
#if os(macOS)
        .frame(minWidth: 800, minHeight: 600)
#endif
        .inspectorAll(isPresented: $showInspector) {
            LinkRootView(type: .inspector)
        }
    }
}

private extension QuickEntryEditor {
    private var contentView: some View {
        HStack(spacing: 8) {
            if showResult {
                entryListView
            }

            editorView
        }
        .animation(.bouncy, value: showResult)
        .onAppear {
            referenceText.input = initialText
            focusedField = .editor
            textEditModel.reset(text: referenceText.input, source: ItemRowModel(itemId: model.id, typeId: editController.itemControllable.itemDataModel.networkModule))
        }
        .onChange(of: referenceText.output) {
            entries = createMultiLineEntries(referenceText.output)
            model.entries = entries
        }
    }
    
    private var entryListView: some View {
        List {
            ForEach(model.entries) { entry in
                EntryEditRow(editController: editController, entry: entry, cacheItemListModel: editController.cacheItemListModel)
            }
        }
#if !os(tvOS)
        .scrollContentBackground(.hidden)
#endif
        .environment(CacheItemListModel())
        .environment(SearchModel.preview())
        .overlay {
#if os(iOS) || os(tvOS)
            if let selectedPdf = editController.tableEditModel.selectionPdf.itemId {
                root.pdfRoot.viewController.inlineViewer(root: root.pdfRoot, with: selectedPdf, withoutBookmark: true) {
                    withAnimation { editController.tableEditModel.selectionPdf.resetSelection(itemId: nil) }
                }
                .background(.black)
                .pdfViewerActions(PdfViewerActions(selectedText: usePdfSelection(selection:)))
            }
#endif
        }
    }
    
    private func usePdfSelection(selection: NSAttributedString) {
        withAnimation { referenceText.input.append(selection.string) }
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
#endif
        }
    }
    
    private var initialText: String {
        editController.model.entries.map {
            "\($0.name)\n\($0.content)"
        }.joined(separator: "\n\n")
    }
}

private extension QuickEntryEditor {
    func createMultiLineEntries(_ text: String) -> [TableEntryModel] {
        var newEntries: [TableEntryModel] = []
        var name = ""
        var content = ""
        
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .forEach { entryline in
                guard !entryline.isEmpty else {
                    if let entry = createEntry(with: name, content: content) {
                        newEntries.append(entry)
                    }
                    name = ""
                    content = ""
                    return
                }
                
                if name.isEmpty {
                    name = String(entryline.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    content.append(contentsOf: "\(entryline.trimmingCharacters(in: .whitespacesAndNewlines))\n")
                }
            }
        if let entry = createEntry(with: name, content: content) {
            newEntries.append(entry)
        }
        
        return newEntries
    }
    
    private func createEntry(with name: String, content: String) -> TableEntryModel? {
        guard !name.isEmpty else { return nil }
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return TableEntryModel(id: UUID(), name: name, content: trimmedContent)
    }
    
    func removeLineBreak(_ text: String) -> String {
        var updatedBlock: [String] = []
        var currentTitle: String = ""
        var currentContent: String = ""
        
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .forEach { entryline in
                if entryline.isEmpty {
                    if !currentTitle.isEmpty {
                        var newBlock = currentTitle
                        if !currentContent.isEmpty {
                            newBlock.append("\n\(currentContent)")
                        }
                        updatedBlock.append(newBlock)
                    }
                    currentTitle = ""
                    currentContent = ""
                } else {
                    var newLine = entryline.trimmingCharacters(in: .whitespacesAndNewlines)
                    if currentTitle.isEmpty {
                        currentTitle.append(newLine)
                    } else {
                        // content 2nd line and more
                        if newLine.last == "-" {
                            newLine = String(newLine.dropLast())
                        } else {
                            newLine.append(" ")
                        }
                        currentContent.append(newLine)
                    }
                }
            }

        if !currentTitle.isEmpty {
            var newBlock = currentTitle
            if !currentContent.isEmpty {
                newBlock.append("\n\(currentContent)")
            }
            updatedBlock.append(newBlock)
        }
        return updatedBlock.joined(separator: "\n\n")
    }
}

private extension QuickEntryEditor {
    @ToolbarContentBuilder var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle")
            }
        }
        
        ToolbarItem(placement: .secondaryActionAll) {
            secondaryActionMenu
        }
        
        ToolbarItem(placement: .confirmationAction) {
            ControlGroup {
                Button {
                    Task {
                        editorModel.removeItems = await editController.merge(entries: entries, recoverEntries: nil)
                        if editorModel.removeItems.isEmpty {
                            dismiss()
                        } else {
                            showEffectedLinksAlert.toggle()
                        }
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
        valueFor(iOS: appSizeMode == .regular, macOS: true, tvOS: true, visionOS: false)
    }
        
    var pdfButton: some View {
        Button {
#if os(macOS) || os(visionOS)
            openWindow(id: NetworkModules.pdf.linkWindowId)
#else
            withAnimation { showResult <=> true }
            navigator.navigate(to: TableEditorRoute.selectionPdf, method: .sheet)
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

#Preview {
    QuickEntryEditor(editController: .preview)
        .environment(TableRootModel.preview)
}
