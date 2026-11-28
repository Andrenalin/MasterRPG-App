// @copyright André Trettin

#if !os(tvOS)

import CoreGraphics
import CoreRPG
import GeneratorRPG
import SwiftUI

/// Analyzes a photo with Apple Intelligence and lets the person pick which of the title,
/// description and tags to apply.
struct PhotoSummaryExtractionView: View {
    let itemId: UUID

    @Environment(PhotoRootModel.self) private var root
    @Environment(\.navigator) private var navigator

    @State private var propertySelection = PhotoPropertySelection()
    @State private var viewState: ViewState = .loading

    var body: some View {
        Content(viewState: $viewState, propertySelection: $propertySelection)
            .navigationTitle(Text("Photo Analysis", bundle: .module))
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
                }

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
                    }
                }
            }
            .task {
                await loadPhoto()
            }
            .moduleTint(root.config.module)
    }

    private func loadPhoto() async {
        guard let image = await root.fetchPhotoAnalysisImage(for: itemId) else {
            viewState = .unavailable
            return
        }
        viewState = .extracting(image)
    }

    private func applyAndClose() {
        if case .extracted(let analysis) = viewState, propertySelection.hasAnySelected {
            root.editController.applyAnalysis(analysis, to: itemId, selection: propertySelection, forceSave: true)
        }
        navigator.back()
    }

    fileprivate enum ViewState {
        case loading
        case extracting(CGImage)
        case extracted(PhotoSummaryAnalysis)
        case unavailable
    }

    private struct Content: View {
        @Binding var viewState: ViewState
        @Binding var propertySelection: PhotoPropertySelection

        var body: some View {
            switch viewState {
            case .loading:
                ProgressView {
                    Text("Loading photo...", bundle: .module)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .extracting(let image):
                if #available(anyAppleOS 27.0, *) {
                    PhotoSummaryAnalysisView(image: image) { analysis in
                        viewState = .extracted(analysis)
                    }
                } else {
                    ContentUnavailableView {
                        Label {
                            Text("Photo Analysis Not Available", bundle: .module)
                        } icon: {
                            Image(systemName: "sparkles")
                        }
                    }
                }
            case .extracted(let analysis):
                PhotoAnalysisUpdateView(analysis: analysis, selectedProperties: $propertySelection)
            case .unavailable:
                ContentUnavailableView {
                    Label {
                        Text("Photo Not Available", bundle: .module)
                    } icon: {
                        Image(systemName: "photo.badge.exclamationmark")
                    }
                } description: {
                    Text("The photo file could not be loaded.", bundle: .module)
                }
            }
        }
    }
}

/// The analyzed values, each with a toggle to apply it.
private struct PhotoAnalysisUpdateView: View {
    let analysis: PhotoSummaryAnalysis
    @Binding var selectedProperties: PhotoPropertySelection

    var body: some View {
        Form {
            Section {
                Text("Select which extracted values you would like to apply on the photo item.", bundle: .module)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $selectedProperties.applyTitle) {
                    Text(verbatim: analysis.title)
                }
            } header: {
                Text("Title", bundle: .module)
            }

            Section {
                Toggle(isOn: $selectedProperties.applyDescription) {
                    Text(verbatim: analysis.summary)
                        .lineLimit(3)
                }
            } header: {
                Text("Description", bundle: .module)
            }

            if !analysis.tags.isEmpty {
                Section {
                    Toggle(isOn: $selectedProperties.applyTags) {
                        FlowLayout(spacing: 8) {
                            ForEach(analysis.tags.occurrenceKeyed()) { keyed in
                                Text(verbatim: keyed.element)
                                    .font(.caption)
                                    .padding(.horizontal)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.2))
                                    .clipShape(.capsule)
                            }
                        }
                    }
                } header: {
                    Text("Tags", bundle: .module)
                }
            }
        }
#if os(macOS)
        .formStyle(.grouped)
#endif
    }
}

#endif
