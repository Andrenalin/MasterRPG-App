// @copyright André Trettin

import Foundation

extension Error {
    /// The error's domain and code, safe to log as public. Log `localizedDescription` next to it
    /// as private: Cocoa file errors name the user's file or path, and Core Data errors can quote
    /// item content. See CODE_AUDIT_Folder §6.5.
    var logIdentifier: String {
        let error = self as NSError
        return "\(error.domain) \(error.code)"
    }
}
