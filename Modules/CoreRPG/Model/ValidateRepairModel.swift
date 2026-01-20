// @copyright André Trettin

import SwiftUI

@MainActor @Observable public final class ValidateRepairModel {
    public init(total: Int = 0, current: Int = 0, currentModule: NetworkModules = .none, currentSection: String = "") {
        self.total = total
        self.current = current
        self.currentModule = currentModule
        self.currentSection = currentSection
    }
    
    public var total: Int = 0
    public var current: Int = 0
    
    public var currentModule: NetworkModules = .none
    public var currentSection: String = ""
    
    public func increaseCurrent() {
        current += 1
    }

    public func update(module: NetworkModules) {
        self.currentModule = module
    }

    public func update(section: String) {
        self.currentSection = section
    }

    public func update(total: Int) {
        self.total = total
    }
}

