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

extension EnvironmentValues {
    @Entry var pdfViewerActions: PdfViewerActions = PdfViewerActions()
}
