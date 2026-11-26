// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
extension Text {
    /// A menu command's title: `named` ("Export \(name)") for a selected item, `plain`
    /// ("Export") without one. An empty name in `named` left titles such as "Lösche " or
    /// " duplizieren" in languages that put the verb after the name.
    static func itemMenuTitle(name: String?, plain: LocalizedStringKey, named: LocalizedStringKey) -> Text {
        guard let name, !name.isEmpty else { return Text(plain, bundle: .module) }
        return Text(named, bundle: .module)
    }
}
#endif
