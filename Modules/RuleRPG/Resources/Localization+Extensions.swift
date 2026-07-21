// @copyright André Trettin

import Foundation

extension Bundle {
    static var ruleResources: Bundle { .ruleModule }
}

extension String {
    var localizedRuleString: String {
        Bundle.ruleModule.localizedString(forKey: self, value: self, table: nil)
    }
}
