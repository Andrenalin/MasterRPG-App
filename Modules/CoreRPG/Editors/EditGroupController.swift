// @copyright André Trettin

import Foundation
import SwiftUI

@Observable
public final class EditGroupModel: @unchecked Sendable {
    init(id: UUID, name: String = "", nameIsDifferent: Bool = false, category: ItemListCategory = .all, categoryIsDifferent: Bool = false, description: String = "", descriptionIsDifferent: Bool = false, tags: [String] = [], displayState: Int = 0, tagsIsDifferent: Bool = false, isGroupHiddenToggle: Bool = false, hiddenIsDifferent: Bool = false) {
        self.id = id
        self.name = name
        self.nameIsDifferent = nameIsDifferent
        self.category = category
        self.categoryIsDifferent = categoryIsDifferent
        self.description = description
        self.descriptionIsDifferent = descriptionIsDifferent
        self.tags = tags
        self.tagsIsDifferent = tagsIsDifferent
        self.isGroupHiddenToggle = isGroupHiddenToggle
        self.hiddenIsDifferent = hiddenIsDifferent
    }
    
    public let id: UUID
    
    public var name: String = ""
    var nameIsDifferent: Bool = false

    public var category: ItemListCategory = .all
    var categoryIsDifferent: Bool = false

    public var description: String = ""
    var descriptionIsDifferent: Bool = false

    public var tags: [String] = []
    var tagsIsDifferent: Bool = false
    
    public var displayState: Int = 0
    
    public var isGroupHiddenToggle: Bool
    var hiddenIsDifferent: Bool = false
    
    public var fileUrl: FileUrl? = nil
    
    public var entries: [FakeEntryModel] = []
    
    public var parentId: UUID?
}

extension EditGroupModel: ItemDataAccessable & ItemDiffComparable {
    public var url: URL? {
        fileUrl?.rawUrl
    }
    
    public static let empty: EditGroupModel = empty(UUID())
    public static func empty(_ id: UUID) -> EditGroupModel {
        EditGroupModel(id: id)
    }
            
    public func copy() -> Self {
        .init(id: id, name: name, category: category, description: description, tags: tags, displayState: displayState, isGroupHiddenToggle: isGroupHiddenToggle)
    }
    
    public func duplicate() -> Self {
        .init(id: id, name: name, category: category, description: description, tags: tags, displayState: displayState, isGroupHiddenToggle: isGroupHiddenToggle)
    }
    
    public func filter(_ filter: String) -> Bool {
        true
    }
    
    public func isEqual(other: EditGroupModel) -> Bool { false }
    
    public func replace(with model: EditGroupModel) -> Bool { false }
    
    public func isSame(_ other: EditGroupModel) -> Bool { false }
    
    public func merge(_ other: EditGroupModel) -> Self { self }
    
    public static func == (lhs: EditGroupModel, rhs: EditGroupModel) -> Bool { false }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public subscript(id: UUID) -> FakeEntryModel {
        get { entries.first ?? .empty }
        set { entries = [newValue] }
    }
    
    public typealias Entry = FakeEntryModel
}

public struct EditGroupController<ItemDataController: ItemControllable, ItemEditController: EditControllable> {
    
    @MainActor
    public init(itemControllable: ItemDataController, editControllable: ItemEditController,
                rootControllable: any RootControllable, selections: [ItemRowTreeModel]) {
        self.itemControllable = itemControllable
        self.editControllable = editControllable
        self.rootControllable = rootControllable
        self.selections = selections.filter { $0.model.entryId == nil && $0.model.typeId == itemControllable.itemDataModel.networkModule }
        self.editorModel = ItemEditorModel()
        self.cacheItemListModel = CacheItemListModel()

        processEditorModel()
    }

    public var itemControllable: any ItemControllable
    public var fileUrlDataController: FileUrlDataController?
    public let editControllable: ItemEditController
    public let rootControllable: any RootControllable
    public let editorModel: ItemEditorModel
    public let cacheItemListModel: CacheItemListModel

    public let selections: [ItemRowTreeModel]
}

extension EditGroupController: EditControllable {
    @MainActor public var linkRegisterControllable: any LinkRegisterControllable {
        rootControllable.linkRegisterControllable
    }
    
    public typealias Model = EditGroupModel
}

public extension EditGroupController {
    @MainActor
    func save() async {
        for item in selections {
            guard var groupModel = itemControllable.copy(of: item.model.itemId) else { return }
            if !model.name.isEmpty {
                groupModel.name <=> model.name
            }
            if model.category != .all {
                groupModel.category <=> model.category
            }
            if !model.hiddenIsDifferent {
                groupModel.isGroupHiddenToggle <=> model.isGroupHiddenToggle
            }
            if !model.tags.isEmpty {
                groupModel.tags <=> model.tags
            }
            if !model.description.isEmpty {
                groupModel.description <=> model.description
            }
            itemControllable.replace(model: groupModel, isInsert: false, shouldRepairLinks: true)
        }
    }

    @MainActor
    func model(for itemId: UUID) -> ItemEditController.Model? {
        guard var mappedModel = itemControllable.copy(of: itemId) else { return nil}
        mappedModel.name = model.name.isEmpty ? mappedModel.name : model.name
        mappedModel.category = model.category == .all ? mappedModel.category : model.category
        mappedModel.isGroupHiddenToggle = model.hiddenIsDifferent ? mappedModel.isGroupHidden : model.isGroupHiddenToggle
        mappedModel.tags = model.tags.isEmpty ? mappedModel.tags : model.tags
        mappedModel.description = model.description.isEmpty ? mappedModel.description : model.description

        return mappedModel as? ItemEditController.Model
    }
}

extension EditGroupController {
    @MainActor func processEditorModel() {
        var name = ""
        var nameIsDifferent = false
        var category: ItemListCategory = .all
        var categoryIsDifferent = false
        var description = ""
        var descriptionIsDifferent = false
        var hidden: Bool?
        var hiddenIsDifferent = false
        var tags: [String] = []
        var tagsIsDifferent = false

        for itemModel in selections {
            guard let model = itemControllable.itemSync(for: itemModel.model.itemId) else { continue }
            if !nameIsDifferent && name.isEmpty {
                name = model.name
            } else if !nameIsDifferent && name != model.name {
                nameIsDifferent = true
                name = ""
            }
            
            if !categoryIsDifferent && category == .all {
                category = model.category
            } else if !categoryIsDifferent && category != model.category {
                categoryIsDifferent = true
                category = .all
            }
            if !descriptionIsDifferent && description.isEmpty {
                description = model.description
            } else if !descriptionIsDifferent && description != model.description {
                descriptionIsDifferent = true
                description = ""
            }
            if !hiddenIsDifferent && hidden == nil {
                hidden = model.isGroupHidden
            } else if !hiddenIsDifferent && hidden != model.isGroupHidden {
                hiddenIsDifferent = true
                hidden = nil
            }
            if !tagsIsDifferent && tags.isEmpty {
                tags = model.tags
            } else if !tagsIsDifferent && tags != model.tags {
                tagsIsDifferent = true
                tags = []
            }
        }
        
        model.name = name
        model.nameIsDifferent = nameIsDifferent
        model.category = category
        model.categoryIsDifferent = categoryIsDifferent
        model.description = description
        model.descriptionIsDifferent = descriptionIsDifferent
        model.isGroupHiddenToggle = hidden ?? false
        model.hiddenIsDifferent = hiddenIsDifferent
        model.tags = tags
        model.tagsIsDifferent = tagsIsDifferent
    }
}

public extension EditGroupController {
    @MainActor func reset(category: ItemListCategory) {
        guard model.category != category else { return }
        model.category = category
    }
    
    @MainActor func reset(description: String) {
        guard model.description != description else { return }
        model.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        cacheItemListModel.reset(cacheType: .description, itemId: model.id, text: model.description.markDownText())
    }
    
    @MainActor func reset(name: String) {
        guard model.name != name else { return }
        model.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        cacheItemListModel.reset(cacheType: .name, itemId: model.id, text: model.name.markDownText())
    }
    
    @MainActor func reset(hidden: Bool) {
        guard model.isGroupHiddenToggle != hidden else { return }
        model.isGroupHiddenToggle = hidden
    }
    
    @MainActor func add(tag: String) {
        guard !tag.isEmpty else { return }
        guard !model.tags.contains(where: { $0 == tag }) else { return }
        var tags = model.tags
        tags.append(tag)
        model.tags = tags.sorted(by: { $0.localizedCompare($1) == .orderedAscending })
    }
    
    @MainActor func remove(tag: String) {
        var tags = model.tags
        guard let index = tags.firstIndex(of: tag) else { return }
        tags.remove(at: index)
        model.tags = tags
    }
}

public extension EditGroupController {
    @MainActor func save(with name: String) {
        // do nothing to prevent writing this model into the db
    }
}
