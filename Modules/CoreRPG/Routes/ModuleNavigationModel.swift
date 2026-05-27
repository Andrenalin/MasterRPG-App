// @copyright André Trettin

import SwiftUI

@MainActor @Observable public final class ModuleNavigationModel {
    public init(selectedItemId: UUID? = nil, selectedEntryId: UUID? = nil) {
        self.selectedItemId = selectedItemId
        self.selectedEntryId = selectedEntryId
    }
    
    public var selectedItemId: UUID?
    public var selectedEntryId: UUID?
    
    public var folderItems: [UUID] = []
    @ObservationIgnored public var folderModels: [UUID: FolderListModel] = [:]
    
    // Inspector
    public var selectedInspectorItemId: UUID?
    public var showInspector: Bool = false

    // Trigger flags — set to true to fire the corresponding action for the current item
    public var openHeaderEditor: Bool = false
    public var triggerExport: Bool = false
    public var triggerGroupEditor: Bool = false
}
