// @copyright André Trettin

import Combine
import SwiftUI

public protocol CompareMergeStore: ObservableObject {
    func apply(merge: CompareMergeStrategy, to id: UUID)
}

public enum CompareMergeStrategy: Equatable, Hashable, CaseIterable {
    case new
    case old
    case merged
    case own
}

public protocol ItemDiffComparable {
    func isSame(_ other: Self) -> Bool
    func merge(_ other: Self) -> Self
    var version: Int { get }
}

public extension ItemDiffComparable {
    var version: Int {
        0
    }
}

public struct CompareViewModel<Value: ItemDiffComparable>: Identifiable {
    public init(id: UUID, newValue: Value, oldValue: Value?, mergeValue: Value?, ownValue: Value, mergeStrategy: CompareMergeStrategy) {
        self.id = id
        self.newValue = newValue
        self.oldValue = oldValue
        self.mergeValue = mergeValue
        self.ownValue = ownValue
        self.mergeStrategy = mergeStrategy
    }

    public let id: UUID
    public let newValue: Value
    public let oldValue: Value?
    public let mergeValue: Value?
    public var ownValue: Value
    public var mergeStrategy: CompareMergeStrategy
}

public struct CompareValueView<Store: CompareMergeStore, Model: ItemDiffComparable, Value: Equatable, Viewer: View, Editor: View>: View {
    public init(store: Store, compareViewModel: CompareViewModel<Model>, title: String, keyPath: WritableKeyPath<Model, Value>, viewer: @escaping (Value) -> Viewer, editor: @escaping () -> Editor) {
        self.store = store
        self.compareViewModel = compareViewModel
        self.title = title
        self.keyPath = keyPath
        self.viewer = viewer
        self.editor = editor
    }

    @ObservedObject var store: Store
    let compareViewModel: CompareViewModel<Model>
    let title: String
    let keyPath: WritableKeyPath<Model, Value>
    let viewer: (Value) -> Viewer
    let editor: () -> Editor

    @State private var mergeStrategy: CompareMergeStrategy = .merged
    @State private var isEditing = false

    public var body: some View {
        VStack(alignment: .leading) {
            if isEditing == false && oldValue == nil {
                HStack {
                    Label(title, systemImage: "checkmark")

                    newValueView

                    Spacer()
                    Button {
                        withAnimation { isEditing.toggle() }
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
            } else {
                newValueView
                    .selectionLabel(title: "New:", imageName: "sparkles.tv") {
                        mergeStrategy = .new
                    } isSelected: {
                        mergeStrategy == .new
                    }

                if let oldValue {
                    viewer(oldValue)
                        .selectionLabel(title: "Old:", imageName: "tv") {
                            mergeStrategy = .old
                        } isSelected: {
                            mergeStrategy == .old
                        }
                }

                if let mergeValue {
                    viewer(mergeValue)
                        .selectionLabel(title: "Merge:", imageName: "arrow.triangle.merge") {
                            mergeStrategy = .merged
                        } isSelected: {
                            mergeStrategy == .merged
                        }
                }

                if isEditing {
                    editor()
                        .selectionLabel(title: "Edit:", imageName: "scribble.variable") {
                            mergeStrategy = .own
                        } isSelected: {
                            mergeStrategy == .own
                        }
                }
            }
        }
        .animation(.default, value: isEditing)
        .detailSectionRow(isActive: isEditing) {
            HStack {
                Text(title)
                Spacer()
                Button {
                    withAnimation { isEditing.toggle() }
                } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .onChange(of: mergeStrategy) {
            store.apply(merge: mergeStrategy, to: compareViewModel.id)
        }
    }
}

private extension CompareValueView {
    var newValueView: some View {
        viewer(compareViewModel.newValue[keyPath: keyPath])
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var oldValue: Value? {
        guard let oldValue = compareViewModel.oldValue?[keyPath: keyPath] else { return nil }
        if oldValue == compareViewModel.newValue[keyPath: keyPath] {
            return nil
        }
        return oldValue
    }

    var mergeValue: Value? {
        compareViewModel.mergeValue?[keyPath: keyPath]
    }
}

extension View {
    func selectionLabel(title: String, imageName: String, action: @escaping () -> Void, isSelected: @escaping () -> Bool) -> some View {
        modifier(SelectionLabelViewModifier(title: title, imageName: imageName, action: action, isSelected: isSelected))
    }
}

struct SelectionLabelViewModifier: ViewModifier {
    let title: String
    let imageName: String
    let action: () -> Void
    let isSelected: () -> Bool

    func body(content: Content) -> some View {
        HStack {
            Label(title, systemImage: imageName)
            content
        }
        .selectListItem(action: action, isSelected: isSelected)
    }
}
