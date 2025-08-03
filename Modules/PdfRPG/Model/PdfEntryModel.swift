// @copyright André Trettin

import CoreRPG
import Foundation
import CoreGraphics

public struct PdfEntryModel: Identifiable, Equatable, Hashable, Codable, Sendable {
    public init(id: UUID, name: CRDT<String> = CRDT(wrappedValue: ""), content: CRDT<String> = CRDT(wrappedValue: ""), pageLabel: String = "", bounds: CGRect = .zero, displayState: Int = 0) {
        self.id = id
        self._name = name
        self._content = content
        self.pageLabel = pageLabel
        self.bounds = bounds
        self.displayState = displayState
    }

    public let id: UUID
    @CRDT public var name: String
    @CRDT public var content: String
    public var pageLabel: String
    public var bounds: CGRect
    public var displayState: Int = 0
}

extension PdfEntryModel: EntryDataAccessable {}
