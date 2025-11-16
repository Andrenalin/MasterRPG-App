// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import RPGPdfs
import SwiftUI

struct QuickEntryEditor: View {
    let editController: EditController
    
    @Environment(TableRootModel.self) private var root
    @Environment(\.dismiss) private var dismiss
    @Environment(\.navigator) private var navigator

#if os(macOS) || os(visionOS)
    @Environment(\.openWindow) private var openWindow
#endif

    private enum Field: Hashable {
        case editor
    }
    @FocusState private var focusedField: Field?
    
    @StateObject private var referenceText = DebouncerStore(initialValue: "", delay: 2)
    @State private var model: TableModel = .empty
    @State private var entries: [TableEntryModel] = []
    
    @State private var showHelp = false
    @State private var showResult = false
    
    @State private var showEffectedLinksAlert: Bool = false
    @State private var editorModel = RemoveEntryListModel()

    var body: some View {
        NavigationStack {
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
#if os(iOS) || os(visionOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackgroundVisibility(.visible, for: .navigationBar)
#endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                    }
                    
                    ToolbarItem(placement: .automatic) {
                        Button {
                            withAnimation { showResult.toggle() }
                        } label: {
                            Image(systemName: showResult ? "rectangle.split.2x1" : "rectangle.split.2x1.slash")
                                .contentTransition(.symbolEffect(.automatic))
                        }
                    }

                    ToolbarItem(placement: .automatic) {
                        Button {
                            withAnimation { showHelp.toggle() }
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                    }
                    
                    ToolbarItem(placement: .confirmationAction) {
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
                .onChange(of: editController.model, initial: true) {
                    model = editController.model.copy()
                }
        }
#if os(macOS)
        .frame(minWidth: 800, minHeight: 600)
#endif
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
        }
        .onReceive(referenceText.$output) { text in
            entries = createMultiLineEntries(text)
            model.entries = entries
        }
    }
    
    private var entryListView: some View {
        List {
            ForEach(model.entries) { entry in
                EntryRow(model: model, item: ItemRowTreeModel(itemId: model.id, entryId: entry.id, typeId: root.itemController.itemDataModel.networkModule), isEditing: false, cacheItemListModel: CacheItemListModel())
                    .foregroundStyle(.primary)
                    .environment(ListModel.preview)
            }
        }
#if !os(tvOS)
        .scrollContentBackground(.hidden)
#endif
        .listTintStyle()
        .environment(CacheItemListModel())
        .overlay {
#if os(iOS) || os(tvOS)
            if let selectedPdf = editController.tableEditModel.pdfSelectionModel.selectedValue {
                root.pdfRoot.viewController.viewPdfInline(root: root.pdfRoot, with: selectedPdf, withoutBookmark: true) {
                    withAnimation { editController.tableEditModel.pdfSelectionModel.selectedValue = nil }
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
    
    private var textBinding: Binding<String> {
        Binding<String>(
            get: { referenceText.input },
            set: { referenceText.input = $0 }
        )
    }

    private var pdfButton: some View {
        Button {
#if os(macOS) || os(visionOS)
            openWindow(id: NetworkModules.pdf.linkWindowId)
#else
            showResult <=> true
            navigator.navigate(to: InternalRoute.selectPdf, method: .sheet)
#endif
        } label: {
            Label { Text("Extract PDF", bundle: .module) } icon: { Image(systemName: "book") }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var removeLineBreak: some View {
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
        .tint(Color.accentColor)
    }

    private var editorView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits {
                HStack {
                    pdfButton
                    removeLineBreak
                }
                
                VStack {
                    pdfButton
                    removeLineBreak
                }
            }
            .tint(Color.accentColor)
            .switchTVToggleStyle()
            .hideKeyboardView(show: focusedField == .editor)
            
#if !os(tvOS)
            TextEditor(text: textBinding)
                .foregroundStyle(.primary)
                .focused($focusedField, equals: .editor)
#endif
        }
#if !os(visionOS)
        .rowColorBackground(isSelected: false)
#endif
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

#Preview {
    QuickEntryEditor(editController: .preview)
        .environment(TableRootModel.preview)
}
