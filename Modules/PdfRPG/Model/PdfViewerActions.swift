// @copyright André Trettin

import SwiftUI

public extension View {
    func pdfViewerActions(_ actions: PdfViewerActions) -> some View {
        environment(\.pdfViewerActions, actions)
    }
}

public struct PdfViewerActions {
    public init(selectedText: ((NSAttributedString) -> Void)? = nil) {
        self.selectedText = selectedText
    }

    public let selectedText: ((NSAttributedString) -> Void)?
}

struct PdfViewerActionsKey: EnvironmentKey {
    static var defaultValue: PdfViewerActions { PdfViewerActions() }
}

extension EnvironmentValues {
    var pdfViewerActions: PdfViewerActions {
        get { self[PdfViewerActionsKey.self] }
        set { self[PdfViewerActionsKey.self] = newValue }
    }
}
