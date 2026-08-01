// @copyright André Trettin

import SwiftUI

struct SheetEntryConvertToGroupView: View {
    let rootModel: SheetRootModel?
    let source: ItemRowModel
    
    var body: some View {
        if let rootModel {
            SheetEntryConvertToGroupModalView(rootModel: rootModel, source: source)
        }
    }
}


struct SheetEntryConvertToGroupModalView: View {
    enum Step {
        case alreadyGroup
        case choosing([FolderRepresentable])
        case result(name: String, description: String)
    }

    let rootModel: SheetRootModel
    let source: ItemRowModel

    @State private var step: Step
    @State private var isConverting = false
    
    @Environment(\.navigator) private var navigator

    init(rootModel: SheetRootModel, source: ItemRowModel) {
        self.rootModel = rootModel
        self.source = source
                
        self._step = State(initialValue: .choosing(rootModel.convertibleGroupCandidates(source: source)))
    }

    var body: some View {
        ManagedNavigationStack(name: "Convert2Group") {
            content
                .navigationTitle(Text("Convert to Group", bundle: .module))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            navigator.back()
                        } label: {
                            Text("Close", bundle: .module)
                        }
                    }
                }
        }
        .frame(minWidth: 280, minHeight: 240)
        .task {
            if case .choosing(let candidates) = step, candidates.isEmpty {
                await convert(existingItemId: nil)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .alreadyGroup:
            alreadyGroupView
        case .choosing(let candidates):
            if isConverting {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                choosingView(candidates: candidates)
            }
        case .result(let name, let description):
            resultView(name: name, description: description)
        }
    }

    private var alreadyGroupView: some View {
        VStack(alignment: .leading, spacing: 12) {
            let name = "Not yet found" // entryModel.name.withoutLink()
            Text("\(name) is already a group.", bundle: .module)
            Spacer()
            Button {
                navigator.back()
            } label: {
                Text("OK", bundle: .module)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func choosingView(candidates: [FolderRepresentable]) -> some View {
        List {
            if !candidates.isEmpty {
                Section {
                    ForEach(candidates) { candidate in
                        Button {
                            Task { await convert(existingItemId: candidate.id) }
                        } label: {
                            Label {
                                Text(candidate.name)
                            } icon: {
                                Image(systemName: "link")
                            }
                        }
                    }
                } header: {
                    Text("Use an existing link as the group", bundle: .module)
                }
            }
            Section {
                Button {
                    Task { await convert(existingItemId: nil) }
                } label: {
                    Label {
                        Text("Create New Group", bundle: .module)
                    } icon: {
                        Image(systemName: "plus.square.fill.on.square.fill")
                    }
                }
            }
        }
    }

    private func resultView(name: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Converted to group.", bundle: .module)
                .font(.headline)
            LabeledContent {
                Text(name)
            } label: {
                Text("Name", bundle: .module)
            }
            LabeledContent {
                Text(description)
            } label: {
                Text("Description", bundle: .module)
            }
            Spacer()
            Button {
                navigator.back()
            } label: {
                Text("Done", bundle: .module)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    @MainActor private func convert(existingItemId: UUID?) async {
        isConverting = true
        defer { isConverting = false }
        guard let group = await rootModel.convertEntryToGroup(source: source, existingItemId: existingItemId) else {
            navigator.back()
            return
        }
        step = .result(name: group.name, description: group.description)
    }
}

#Preview("Convert to Group") {
    SheetEntryConvertToGroupModalView(
        rootModel: .fake,
        source: ItemRowModel(itemId: UUID(), entryId: UUID(), typeId: .adventure)
    )
}
