// @copyright André Trettin

import Foundation

public extension URL {
    static let appScheme: String = "RPG"
    
    var isDeeplink: Bool {
        return scheme == URL.appScheme
    }
    
    var isGmzDocument: Bool {
        pathExtension == "gmz"
    }
    
    var moduleIdentifier: NetworkModules {
        guard isDeeplink, let host else { return .none }
        return UserActivity.extractModule(from: host)
    }
    
    var linkNumber: Int {
        guard pathComponents.count > 1,
              let number = Int(pathComponents[1])
        else {
            return 0
        }
        return number
    }
    
    var itemId: UUID? {
        guard pathComponents.count > 2,
              let uuid = UUID(uuidString: pathComponents[2])
        else {
            return nil
        }
        return uuid
    }
    
    var childId: UUID? {
        guard pathComponents.count > 3,
              let uuid = UUID(uuidString: pathComponents[3])
        else {
            return nil
        }
        return uuid
    }
    
    var commandKey: String? {
        if childId != nil {
            guard pathComponents.count > 4 else { return nil }
            return pathComponents[4]
        }
        guard pathComponents.count > 3 else { return nil }
        return pathComponents[3]
    }
    
    // MARK: - New Links
    
    var linkId: UUID? {
        guard pathComponents.count > 0,
              let uuid = UUID(uuidString: pathComponents[0])
        else {
            return nil
        }
        return uuid
    }
    
    var linkCommand: String? {
        guard pathComponents.count > 1 else { return nil }
        return pathComponents[1]
    }
}
