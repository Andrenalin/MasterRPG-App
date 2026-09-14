// @copyright André Trettin

import SwiftUI

public extension View {
    func pdfViewerActions(_ actions: PdfViewerActions) -> some View {
        environment(\.pdfViewerActions, actions)
    }
}

public struct PdfViewerActions: Equatable {
    /// A fixed identity reserved for the `@Entry` environment default with no
    /// writer configured yet. Unlike the `UUID()` `init` default below, this
    /// must always compare equal to itself across evaluations, or every
    /// access to the unconfigured default would compare unequal to every
    /// other access and defeat SwiftUI's diffing. A computed property (not a
    /// stored `static let`) because `AnyHashable` isn't unconditionally
    /// `Sendable`, so a stored global would fail Swift 6's concurrency-safety
    /// check — the string literal it wraps compares equal on every call
    /// regardless, so nothing is lost by recomputing it. See CODE_AUDIT §8.1.
    static var unconfiguredId: AnyHashable { "PdfViewerActions.unconfigured" }

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
    // Explicitly passes a fixed sentinel `id` rather than relying on
    // `init`'s `UUID()` default — `@Entry`'s generated default is
    // re-evaluated on every environment read that hasn't been overridden by
    // a real writer, so a fresh `UUID()` here would make every such read
    // compare unequal to the last, defeating SwiftUI's diffing before any
    // writer even exists. Every real writer in the app already passes an
    // explicit `id` (the owning item's id), so this doesn't change their
    // behavior. See CODE_AUDIT §8.1.
    @Entry var pdfViewerActions: PdfViewerActions = PdfViewerActions(id: PdfViewerActions.unconfiguredId)
}
