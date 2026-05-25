// @copyright André Trettin

import SwiftUI

public struct ImportReviewView: View {
    @Binding public var reviewItems: [ImportReviewItem]
    public let onApply: @MainActor @Sendable () async -> Void

    @State private var isApplying = false

    public init(reviewItems: Binding<[ImportReviewItem]>, onApply: @MainActor @Sendable @escaping () async -> Void) {
        self._reviewItems = reviewItems
        self.onApply = onApply
    }

    private var moduleNames: [String] {
        var seen = Set<String>()
        return reviewItems.compactMap { seen.insert($0.moduleName).inserted ? $0.moduleName : nil }.sorted()
    }

    public var body: some View {
        List {
            ForEach(moduleNames, id: \.self) { moduleName in
                let moduleItems = reviewItems.filter { $0.moduleName == moduleName }

                let newItems    = moduleItems.filter { $0.kind == .new }
                let updatedItems = moduleItems.filter { $0.kind == .updated }
                let deletedItems = moduleItems.filter { $0.kind == .deleted }

                if !newItems.isEmpty {
                    Section(header: Text("\(moduleName) — New", bundle: .module)) {
                        ForEach(newItems) { item in
                            reviewRow(for: item)
                        }
                    }
                }
                if !updatedItems.isEmpty {
                    Section(header: Text("\(moduleName) — Updated", bundle: .module)) {
                        ForEach(updatedItems) { item in
                            reviewRow(for: item)
                        }
                    }
                }
                if !deletedItems.isEmpty {
                    Section(header: Text("\(moduleName) — Not in Import", bundle: .module)) {
                        ForEach(deletedItems) { item in
                            reviewRow(for: item)
                        }
                    }
                }
            }
        }
        .disabled(isApplying)
        .overlay {
            if isApplying {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    isApplying = true
                    Task {
                        await onApply()
                        isApplying = false
                    }
                } label: {
                    Label { Text("Apply", bundle: .module) } icon: { Image(systemName: "checkmark.circle") }
                }
                .disabled(isApplying)
            }
        }
    }

    @ViewBuilder
    private func reviewRow(for item: ImportReviewItem) -> some View {
        if let index = reviewItems.firstIndex(where: { $0.id == item.id }) {
            let resolutionOptions: [ImportResolution] = item.kind == .deleted
                ? [.old, .new]
                : ImportResolution.allCases

            HStack {
                Text(item.name)
                    .lineLimit(1)
                Spacer()
                Picker("", selection: $reviewItems[index].resolution) {
                    ForEach(resolutionOptions, id: \.self) { resolution in
                        resolutionLabel(resolution, kind: item.kind).tag(resolution)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    @ViewBuilder
    private func resolutionLabel(_ resolution: ImportResolution, kind: ImportReviewItem.Kind) -> some View {
        switch (resolution, kind) {
        case (.old, .deleted):   Text("Keep", bundle: .module)
        case (.new, .deleted):   Text("Remove", bundle: .module)
        case (.old, _):          Text("Keep Existing", bundle: .module)
        case (.new, _):          Text("Use Imported", bundle: .module)
        case (.merge, _):        Text("Merge", bundle: .module)
        }
    }
}
