// @copyright André Trettin

import CoreRPG
import Testing
@testable import RolePlayGameKit

@Suite("Foundry import progress presentation")
struct FoundryImportProgressPresentationTests {
    @Test("Item commit is determinate")
    func itemCommitIsDeterminate() {
        #expect(
            FoundryImportProgressPresentation(
                phase: .committing,
                completed: 2,
                total: 4
            ) == .importing(completed: 2, total: 4)
        )
    }

    @Test("Repair, save, and archive work are indeterminate finalization")
    func finalizationStagesAreIndeterminate() {
        #expect(
            FoundryImportProgressPresentation(
                phase: .repairing,
                completed: 4,
                total: 4
            ) == .finalizing(completed: 4, total: 4, step: .repairing)
        )
        #expect(
            FoundryImportProgressPresentation(
                phase: .saving,
                completed: 4,
                total: 4
            ) == .finalizing(completed: 4, total: 4, step: .saving)
        )
        #expect(
            FoundryImportProgressPresentation(
                phase: .completed,
                completed: 4,
                total: 4
            ) == .finalizing(completed: 4, total: 4, step: .sourceArchive)
        )
        #expect(
            FoundryImportProgressPresentation(
                phase: .committing,
                completed: 4,
                total: 4,
                isSavingSourceArchive: true
            ) == .finalizing(completed: 4, total: 4, step: .sourceArchive)
        )
    }

    @Test("Unknown totals and rollback use indeterminate progress")
    func otherIndeterminateStages() {
        #expect(
            FoundryImportProgressPresentation(
                phase: .committing,
                completed: 0,
                total: 0
            ) == .preparing
        )
        #expect(
            FoundryImportProgressPresentation(
                phase: .rollingBack,
                completed: 2,
                total: 4
            ) == .rollingBack
        )
    }
}
