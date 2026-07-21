// @copyright André Trettin

import Foundation

public final class Resources {
    private init() {}

    public static let bundle = Bundle.ruleModule
}

public extension Bundle {
    static let ruleModule = Bundle(for: Resources.self)
}
