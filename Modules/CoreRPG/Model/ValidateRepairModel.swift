// @copyright André Trettin

import SwiftUI

public enum ValidatePhase: String, Sendable {
    case repairFolders
    case validateLinks
    case saveChanges

    public var title: String {
        switch self {
        case .repairFolders: "Repair Folders"
        case .validateLinks: "Validate Links"
        case .saveChanges: "Saving Changes"
        }
    }
}

@MainActor @Observable public final class ValidateRepairModel {
    public init(total: Int = 0, current: Int = 0, currentModule: NetworkModules = .none, currentSection: String = "", currentPhase: ValidatePhase = .repairFolders) {
        self.total = total
        self.current = current
        self.currentModule = currentModule
        self.currentSection = currentSection
        self.currentPhase = currentPhase
    }

    public var total: Int = 0
    public var current: Int = 0

    public var currentModule: NetworkModules = .none
    public var currentSection: String = ""
    public var currentPhase: ValidatePhase = .repairFolders

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

    public func update(phase: ValidatePhase) {
        self.currentPhase = phase
    }
}

