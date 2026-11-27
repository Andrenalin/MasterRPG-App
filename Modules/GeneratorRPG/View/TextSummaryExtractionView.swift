// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import SwiftUI
#if DEBUG
#if os(macOS)
import AppKit
#else
import UIKit
#endif
#endif

// MARK: - Property Selection

public struct TextSummaryPropertySelection: Sendable {
    public var applyTitle: Bool
    public var applyDescription: Bool
    public var applyTags: Bool

    public init(applyTitle: Bool = true, applyDescription: Bool = true, applyTags: Bool = true) {
        self.applyTitle = applyTitle
        self.applyDescription = applyDescription
        self.applyTags = applyTags
    }

    public var hasAnySelected: Bool {
        applyTitle || applyDescription || applyTags
    }
}

// MARK: - Extraction Flow

/// Generic AI-extraction flow: AI analysis → property-selection form → apply callback.
/// Pass `module` to customize tint, navigation title, and description label.
/// Pass pre-formatted `entriesText`; `onApply` is called with result + selection.
public struct TextSummaryExtractionView: View {

    public let module: NetworkModules
    public let entriesText: String
    /// The item's current name, empty when it has none. A character keeps it.
    public let itemName: String
    /// A hint shown above the analysis, `nil` for none.
    public let notice: LocalizedStringResource?
    public let onApply: (TableSummaryAnalysis, TextSummaryPropertySelection) -> Void

    @Environment(\.navigator) private var navigator
    @State private var propertySelection = TextSummaryPropertySelection()
    @State private var viewState: ViewState = .extracting

    public init(
        module: NetworkModules,
        entriesText: String,
        itemName: String = "",
        notice: LocalizedStringResource? = nil,
        onApply: @escaping (TableSummaryAnalysis, TextSummaryPropertySelection) -> Void
    ) {
        self.module = module
        self.entriesText = entriesText
        self.itemName = itemName
        self.notice = notice
        self.onApply = onApply
    }

    public var body: some View {
        ContentView(module: module, entriesText: entriesText, itemName: itemName, notice: notice, viewState: $viewState, propertySelection: $propertySelection)
            #if DEBUG && os(macOS)
            // A macOS sheet's toolbar shows only the cancel and confirm actions.
            .safeAreaInset(edge: .bottom) {
                CopyAnalysisInputButton(entriesText: entriesText)
                    .padding(.bottom)
            }
            #endif
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        navigator.back()
                    } label: {
                        Label {
                            Text("Cancel", bundle: .module)
                        } icon: {
                            Image(systemName: "xmark")
                        }
                    }
                    .accessibilityLabel(Text("Cancel extraction", bundle: .module))
                }

                #if DEBUG && !os(macOS)
                ToolbarItem(placement: .secondaryAction) {
                    CopyAnalysisInputButton(entriesText: entriesText)
                }
                #endif

                if case .extracted = viewState {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: .confirm) {
                            applyAndClose()
                        } label: {
                            Label {
                                Text("Apply", bundle: .module)
                            } icon: {
                                Image(systemName: "checkmark")
                            }
                        }
                        .disabled(!propertySelection.hasAnySelected)
                        .accessibilityLabel(Text("Apply selected properties", bundle: .module))
                    }
                }
            }
            .moduleTint(module)
    }

    // MARK: - Content

    private var navigationTitle: String {
        String(
            localized: "\(String(localized: module.localizedTitle)) Analysis",
            bundle: .module
        )
    }

    private func applyAndClose() {
        guard case .extracted(let content) = viewState, propertySelection.hasAnySelected else {
            navigator.back()
            return
        }
        onApply(content, propertySelection)
        navigator.back()
    }

    // MARK: - States

    fileprivate enum ViewState {
        case extracting
        case extracted(TableSummaryAnalysis)
    }
}

#if DEBUG
/// Debug builds only: copies the exact text the analysis reads (values or entries with links
/// reduced to labels, plus photo description and tags) so a real item can become an evaluation
/// fixture (`Tests/GeneratorRPGTests`). Not localized on purpose: it never ships.
private struct CopyAnalysisInputButton: View {
    let entriesText: String

    var body: some View {
        Button {
            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entriesText, forType: .string)
            #else
            UIPasteboard.general.string = entriesText
            #endif
        } label: {
            Label {
                Text(verbatim: "Copy Analysis Input")
            } icon: {
                Image(systemName: "doc.on.clipboard")
            }
        }
    }
}
#endif

private struct ContentView: View {
    let module: NetworkModules
    let entriesText: String
    let itemName: String
    let notice: LocalizedStringResource?
    @Binding var viewState: TextSummaryExtractionView.ViewState
    @Binding var propertySelection: TextSummaryPropertySelection

    var body: some View {
        switch viewState {
        case .extracting:
            TableSummaryAnalysisView(entriesText: entriesText, module: module, itemName: itemName, notice: notice) { content in
                viewState = .extracted(content)
            }
        case .extracted(let content):
            TextSummaryUpdateView(content: content, module: module, selectedProperties: $propertySelection)
        }
    }
}

#Preview {
    NavigationStack {
        TextSummaryExtractionView(
            module: .table,
            entriesText: "A moss-covered altar stands in the center of the chamber."
        ) { _, _ in }
    }
}

#endif
