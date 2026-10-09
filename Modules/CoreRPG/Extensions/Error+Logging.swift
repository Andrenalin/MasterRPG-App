// @copyright André Trettin

import Foundation

public extension Error {
    /// The error's domain and code, safe to log as public. Log `localizedDescription` next to it
    /// as private: Cocoa file errors name the user's file or path, and Core Data errors can quote
    /// item content. See CODE_AUDIT_Folder §6.5.
    ///
    /// Public: the helper was internal, so the other modules could not use it and kept logging
    /// the description as public. See CODE_AUDIT_21 §6.9.
    var logIdentifier: String {
        let error = self as NSError
        return "\(error.domain) \(error.code)"
    }
}
