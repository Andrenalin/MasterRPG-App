// @copyright André Trettin

import SwiftUI

@MainActor @Observable
public final class ListDisplayModel {
    public init(isSelectionMode: Bool = false, displayMode: ListDisplayModel.DisplayMode = .medium, listMode: ListDisplayModel.ListMode = .list, isPadStyle: Bool = false) {
        self.isSelectionMode = isSelectionMode
        self.displayMode = displayMode
        self._listMode = listMode
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
        
        public var title: LocalizedStringKey {
            switch self {
            case .list: return "List"
            case .folder: return "Folder"
            }
        }
        
        public var id: Self { self }
    }
    var _listMode: ListMode
    public var listMode: ListMode {
        get {
            _listMode
        }
        set {
            _listMode = newValue
        }
    }

    public var isListMode: Bool {
        get { listMode == .list }
        set {
            if listMode != .list && newValue {
                print("*** Change from isListMode")
                listMode = .list
            }
        }
    }
    public var isFolderMode: Bool {
        get { listMode == .folder }
        set {
            if listMode != .folder && newValue {
                print("*** Change from isFolderMode")
                listMode = .folder
            }
        }
    }
    
    var imageHeight: CGFloat {
        switch displayMode {
        case .compact: 64
        case .medium: 80
        case .regular: 96
        }
    }

    var isPadStyle: Bool
    
    public var newListDisplayModel: ListDisplayModel {
        ListDisplayModel(isSelectionMode: isSelectionMode, displayMode: displayMode, listMode: listMode, isPadStyle: isPadStyle)
    }
}
