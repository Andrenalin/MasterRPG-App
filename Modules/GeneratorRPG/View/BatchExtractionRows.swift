// @copyright André Trettin

#if !os(tvOS)

import SwiftUI

/// The state of one item in a batch "Extract Information" run
/// (`BatchTextSummaryExtractionView`, `BatchPdfSummaryExtractionView`).
enum BatchItemStatus: Sendable {
    case pending
    case analyzing
    case completed
    /// The item has nothing to analyze; nothing was changed.
    case skipped
    case failed(String)
}

/// The run loop both batch views share: one item after the other, each with its status, a
/// cancellation ending the run (never shown as "failed"). See CODE_AUDIT_29 §9.1, §5.18.
@MainActor
enum BatchItemRunner {
    enum Outcome {
        case completed
        /// The item has nothing to analyze.
        case skipped
    }

    static func run(
        ids: [UUID],
        setStatus: (UUID, BatchItemStatus) -> Void,
        step: (UUID) async throws -> Outcome
    ) async {
        for id in ids {
            guard !Task.isCancelled else { return }
            setStatus(id, .analyzing)
            do {
                let outcome = try await step(id)
                guard !Task.isCancelled else { return setStatus(id, .pending) }
                setStatus(id, outcome == .completed ? .completed : .skipped)
            } catch is CancellationError {
                // The item was not analyzed: it is pending again, not "failed" or still spinning.
                return setStatus(id, .pending)
            } catch {
                guard !Task.isCancelled else { return setStatus(id, .pending) }
                setStatus(id, .failed(error.localizedDescription))
            }
        }
    }

    /// The name a row shows: an item without a name is "Untitled", never its id.
    /// See CODE_AUDIT_29 §8.4.
    static func displayName(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return String(localized: "Untitled", bundle: .module) }
        return name
    }
}

/// One item row of a batch extraction: status icon, name and status text.
struct BatchItemStatusRow: View {
    let name: String
    let status: BatchItemStatus
    /// What a skipped item says, because the reason differs per module.
    let skippedText: LocalizedStringResource

    var body: some View {
        HStack(spacing: 12) {
            BatchItemStatusIcon(status: status)
            Text(verbatim: name)
            Spacer()
            BatchItemStatusLabel(status: status, skippedText: skippedText)
        }
    }
}

private struct BatchItemStatusIcon: View {
    let status: BatchItemStatus

    var body: some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .contentTransition(.symbolEffect(.automatic))
        case .analyzing:
            ProgressView()
                .scaleEffect(0.8)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .contentTransition(.symbolEffect(.automatic))
        case .skipped:
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .contentTransition(.symbolEffect(.automatic))
        }
    }
}

private struct BatchItemStatusLabel: View {
    let status: BatchItemStatus
    let skippedText: LocalizedStringResource

    var body: some View {
        switch status {
        case .pending, .analyzing:
            EmptyView()
        case .completed:
            Text("Done", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
        case .skipped:
            Text(skippedText)
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let error):
            Text(verbatim: error)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// One line of the "Analyzing..." section: a check mark once that part is generated.
struct BatchProgressRow: View {
    let ready: Bool
    let label: LocalizedStringResource

    var body: some View {
        HStack {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ready ? .green : .secondary)
                .contentTransition(.symbolEffect(.automatic))
            Text(label)
                .font(.subheadline)
        }
    }
}

#endif
