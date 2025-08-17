// @copyright André Trettin

import SwiftUI

@Observable @MainActor
public final class ListDisplayModel {
    public init(isSelectionMode: Bool = false, displayMode: ListDisplayModel.DisplayMode = .medium, listMode: ListDisplayModel.ListMode = .list, isPadStyle: Bool = false) {
        self.isSelectionMode = isSelectionMode
        self.displayMode = displayMode
        self.listMode = listMode
        self.isPadStyle = isPadStyle
    }
    
    public var isSelectionMode: Bool

    public enum DisplayMode: Int, Equatable, Hashable, Codable, Sendable {
        case compact
        case medium
        case regular
    }
    public var displayMode: DisplayMode
    
    public var isCompactDisplayMode: Bool {
        get { displayMode == .compact }
        set {
            guard newValue, displayMode != .compact else { return }
            displayMode = .compact
        }
    }
    public var isMediumDisplayMode: Bool {
        get { displayMode == .medium }
        set {
            guard newValue, displayMode != .medium else { return }
            displayMode = .medium
        }
    }
    public var isRegularDisplayMode: Bool {
        get { displayMode == .regular }
        set {
            guard newValue, displayMode != .regular else { return }
            displayMode = .regular
        }
    }
    
    public enum ListMode: Int, Equatable, Hashable, Codable, Sendable, CaseIterable, Identifiable {
        case list
        case folder
        
        public var title: String {
            switch self {
            case .list: return "List"
            case .folder: return "Folder"
            }
        }
        
        public var id: Self { self }
    }    
    public var listMode: ListMode

    public var isListMode: Bool {
        get { listMode == .list }
        set {
            guard newValue, listMode != .list else { return }
            listMode = .list
        }
    }
    public var isFolderMode: Bool {
        get { listMode == .folder }
        set {
            guard newValue, listMode != .folder else { return }
            listMode = .folder
        }
    }
    
    var isPadStyle: Bool
    
    public var newListDisplayModel: ListDisplayModel {
        ListDisplayModel(isSelectionMode: isSelectionMode, displayMode: displayMode, listMode: listMode, isPadStyle: isPadStyle)
    }
}
