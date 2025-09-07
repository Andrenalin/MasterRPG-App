// @copyright André Trettin

import Foundation
import SwiftUI

public protocol LinkControllable: Sendable {
    @MainActor func handleTextLink(url: URL, in text: String) -> String
    
    // Sheet Entries
    @MainActor func toggleSheet(itemId: UUID, level: Int, module: NetworkModules) -> SheetModel?
    
    // Collect Links
    @MainActor func collectLinks(of module: NetworkModules, from itemId: UUID) -> [UUID]
}

extension LinkControllable {
    @MainActor public func handleTextLink(url: URL, in text: String) -> String { text }    
    @MainActor func toggleSheet(itemId: UUID, level: Int, module: NetworkModules) -> SheetModel? { nil }
    @MainActor func collectLinks(of module: NetworkModules, from itemId: UUID) -> [UUID] { [] }
}
