// @copyright André Trettin

import SwiftUI

public extension View {
    func pdfViewerActions(_ actions: PdfViewerActions) -> some View {
        environment(\.pdfViewerActions, actions)
    }
}

public struct PdfViewerActions: Equatable {
    /// `id` should be a value stable across a writer's re-renders (e.g. the
    /// owning item's id) — not a fresh default — so SwiftUI's environment
    /// diffing (which uses `Equatable` conformance automatically) can tell an
    /// unchanged writer apart from a genuinely different one, instead of
    /// invalidating every reader on every write regardless of whether the
    /// closure's behavior actually changed.
    public init(id: AnyHashable = UUID(), selectedText: ((NSAttributedString) -> Void)? = nil) {
        self.id = id
        self.selectedText = selectedText
    }

    let id: AnyHashable
    public let selectedText: ((NSAttributedString) -> Void)?

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

extension EnvironmentValues {
    @Entry var pdfViewerActions: PdfViewerActions = PdfViewerActions()
}
