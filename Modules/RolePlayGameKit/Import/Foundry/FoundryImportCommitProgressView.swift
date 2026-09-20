// @copyright André Trettin

import CoreRPG
import SwiftUI

struct FoundryImportCommitProgressView: View {
    let session: ExternalImportReviewSession?
    var isSavingSourceArchive = false

    var body: some View {
        VStack {
            switch presentation {
            case .preparing:
                ProgressView {
                    Text("Preparing import", bundle: .module)
                }
            case .importing(let completed, let total):
                FoundryImportedItemProgressView(completed: completed, total: total)
            case .finalizing(let completed, let total, let step):
                if total > 0 {
                    FoundryImportedItemProgressView(completed: completed, total: total)
                }
                FoundryImportFinalizationProgressView(step: step)
            case .rollingBack:
                ProgressView {
                    Text("Undoing import changes", bundle: .module)
                }
            case .stopped:
                EmptyView()
            }
        }
        .padding()
    }

    private var presentation: FoundryImportProgressPresentation {
        FoundryImportProgressPresentation(
            phase: session?.phase,
            completed: session?.completedItemCount ?? 0,
            total: session?.selectedItemCount ?? 0,
            isSavingSourceArchive: isSavingSourceArchive
        )
    }
}

enum FoundryImportProgressPresentation: Equatable, Sendable {
    case preparing
    case importing(completed: Int, total: Int)
    case finalizing(
        completed: Int,
        total: Int,
        step: FoundryImportFinalizationStep
    )
    case rollingBack
    case stopped

    init(
        phase: ExternalImportPhase?,
        completed: Int,
        total: Int,
        isSavingSourceArchive: Bool = false
    ) {
        if isSavingSourceArchive {
            self = .finalizing(
                completed: completed,
                total: total,
                step: .sourceArchive
            )
            return
        }

        self = switch phase {
        case .reviewing, nil:
            .preparing
        case .committing:
            total > 0
                ? .importing(completed: completed, total: total)
                : .preparing
        case .repairing:
            .finalizing(completed: completed, total: total, step: .repairing)
        case .saving:
            .finalizing(completed: completed, total: total, step: .saving)
        case .completed:
            .finalizing(completed: completed, total: total, step: .sourceArchive)
        case .rollingBack:
            .rollingBack
        case .failed, .cancelled:
            .stopped
        }
    }
}

enum FoundryImportFinalizationStep: Equatable, Sendable {
    case repairing
    case saving
    case sourceArchive

    var detail: LocalizedStringResource {
        switch self {
        case .repairing:
            LocalizedStringResource(
                "Repairing folders and links",
                bundle: .module
            )
        case .saving:
            LocalizedStringResource(
                "Saving imported data",
                bundle: .module
            )
        case .sourceArchive:
            LocalizedStringResource(
                "Saving source archive",
                bundle: .module
            )
        }
    }
}

private struct FoundryImportedItemProgressView: View {
    let completed: Int
    let total: Int

    var body: some View {
        ProgressView(
            value: Double(completed),
            total: Double(total)
        ) {
            Text("Importing items and assets", bundle: .module)
        } currentValueLabel: {
            Text(
                "\(completed.formatted()) of \(total.formatted())",
                bundle: .module
            )
        }
    }
}

private struct FoundryImportFinalizationProgressView: View {
    let step: FoundryImportFinalizationStep

    var body: some View {
        VStack {
            ProgressView {
                Text("Finalizing import", bundle: .module)
            }
            Text(step.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
