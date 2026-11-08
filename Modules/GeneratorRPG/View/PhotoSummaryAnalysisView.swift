// @copyright André Trettin

#if !os(tvOS)

import CoreGraphics
import CoreRPG
import SwiftUI

/// Analyzes one photo with Apple Intelligence and hands the title, description and tags to
/// `onAnalysisCompleted`. When the on-device model cannot analyze the photo, Private Cloud
/// Compute takes over, after the person allowed it once.
@available(anyAppleOS 27.0, *)
public struct PhotoSummaryAnalysisView: View {

    let image: CGImage
    let onAnalysisCompleted: (PhotoSummaryAnalysis) -> Void

    @State private var model = PhotoSummaryAnalysisModel()
    @State private var selectedLanguage = OutputLanguage.forCurrentLocale()
    @State private var consent = PhotoCloudConsent.stored()
    /// Owned so dismissing the sheet cancels the model work instead of leaving it running.
    @State private var analysisTask: Task<Void, Never>?

    public init(image: CGImage, onAnalysisCompleted: @escaping (PhotoSummaryAnalysis) -> Void) {
        self.image = image
        self.onAnalysisCompleted = onAnalysisCompleted
    }

    public var body: some View {
        VStack {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .clipShape(.rect(cornerRadius: 12))
                .frame(maxHeight: 280)

            if model.isAnalyzing {
                ProgressView {
                    Text("Analyzing photo with Apple Intelligence...", bundle: .module)
                        .font(.headline)
                }
                .padding()
            } else {
                OutputLanguagePickerView(selectedLanguage: $selectedLanguage)

                Button(action: analyze) {
                    Label {
                        Text("Analyze Photo", bundle: .module)
                    } icon: {
                        Image(systemName: NetworkModules.generator.icon)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                if PhotoSummaryAnalyzer.isPrivateCloudComputeEnabled {
                    CloudToggle(consent: $consent)
                }
            }

            if let error = model.lastError {
                ErrorBanner(message: error) { model.clearError() }
            }
        }
        .padding()
        .confirmationDialog(
            Text("Use Private Cloud Compute?", bundle: .module),
            isPresented: consentQuestionBinding,
            titleVisibility: .visible
        ) {
            Button {
                decide(.allowed)
            } label: {
                Text("Allow and Analyze", bundle: .module)
            }
            Button(role: .cancel) {
                decide(.denied)
            } label: {
                Text("Don't Allow", bundle: .module)
            }
        } message: {
            if let reason = model.pendingConsentReason {
                Text("\(reason.explanation) Apple's Private Cloud Compute can analyze the photo instead. The photo is sent to Apple, which designs it not to keep the photo. This needs a network connection and counts toward a daily limit.", bundle: .module)
            }
        }
        .onDisappear { analysisTask?.cancel() }
    }

    // MARK: - Actions

    private var consentQuestionBinding: Binding<Bool> {
        Binding(
            get: { model.pendingConsentReason != nil },
            set: { if !$0 { model.pendingConsentReason = nil } }
        )
    }

    private func decide(_ decision: PhotoCloudConsent) {
        consent = decision
        decision.store()
        model.pendingConsentReason = nil
        if decision == .allowed {
            analyze()
        }
    }

    private func analyze() {
        guard !model.isAnalyzing else { return }
        analysisTask = Task {
            let output = await model.analyze(
                image: image,
                outputLanguage: selectedLanguage.englishName,
                consent: consent
            )
            guard !Task.isCancelled, let output else { return }
            onAnalysisCompleted(output.analysis)
        }
    }
}

// MARK: - Subviews

private struct CloudToggle: View {
    @Binding var consent: PhotoCloudConsent

    var body: some View {
        Toggle(isOn: Binding(
            get: { consent == .allowed },
            set: { isOn in
                consent = isOn ? .allowed : .denied
                consent.store()
            }
        )) {
            VStack(alignment: .leading) {
                Text("Use Private Cloud Compute when needed", bundle: .module)
                Text("Only used when the on-device model cannot analyze the photo. The photo is then sent to Apple.", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)

            Text(verbatim: message)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: dismiss) {
                Text("Dismiss", bundle: .module)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(.red.opacity(0.1), in: .rect(cornerRadius: 8))
    }
}

#endif
