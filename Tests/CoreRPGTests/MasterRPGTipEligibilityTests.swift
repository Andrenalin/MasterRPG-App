// @copyright André Trettin

import Foundation
import Testing
import TipKit

@testable import CoreRPG

@Suite("MasterRPG tip eligibility")
struct MasterRPGTipEligibilityTests {
    @Test("Core onboarding copy is localized in German")
    func germanLocalization() {
        // Given
        let locale = Locale(identifier: "de")

        // When
        let title = MasterRPGTips.localizedString(
            "Create your first item",
            locale: locale
        )
        let action = MasterRPGTips.localizedString(
            "Import Campaign",
            locale: locale
        )

        // Then
        #expect(title == "Erstelle dein erstes Element")
        #expect(action == "Kampagne importieren")
    }
}

@Suite("MasterRPG TipKit integration", .serialized)
@MainActor
struct MasterRPGTipKitIntegrationTests {
    @Test(
        "A donated completion event makes the first-item tip unavailable",
        .timeLimit(.minutes(1))
    )
    func completedEventHidesTip() async throws {
        // Given
        try Self.configureTipsOnce()
        MasterRPGTipState.forceReplay = false
        MasterRPGTipState.apply(
            MasterRPGTipEligibilitySnapshot(
                databaseReady: true,
                regularItemCount: 0,
                topLevelItemCount: 0,
                entryCount: 0,
                linkCount: 0,
                organizationCount: 0,
                adventureCount: 0,
                characterCount: 0,
                mapCount: 0
            )
        )
        await MasterRPGTips.firstItem.resetEligibility()
        let wasAvailable = await wait(
            for: true,
            in: MasterRPGTips.firstItem.shouldDisplayUpdates
        )

        // When
        await MasterRPGTips.donateItemCreated()
        let becameUnavailable = await wait(
            for: false,
            in: MasterRPGTips.firstItem.shouldDisplayUpdates
        )

        // Then
        #expect(wasAvailable)
        #expect(becameUnavailable)
    }

    /// CODE_AUDIT_19 §9.21: the eligibility conditions exist only in the tips' `#Rule`s, so
    /// the snapshot must reach every rule input unchanged.
    @Test("Applying a snapshot sets every tip rule input")
    func applySetsEveryRuleInput() throws {
        try Self.configureTipsOnce()
        let snapshot = MasterRPGTipEligibilitySnapshot(
            databaseReady: true,
            regularItemCount: 7,
            topLevelItemCount: 5,
            entryCount: 11,
            linkCount: 3,
            organizationCount: 2,
            adventureCount: 1,
            characterCount: 4,
            mapCount: 6
        )

        MasterRPGTipState.apply(snapshot)

        #expect(MasterRPGTipState.databaseReady)
        #expect(MasterRPGTipState.regularItemCount == 7)
        #expect(MasterRPGTipState.topLevelItemCount == 5)
        #expect(MasterRPGTipState.entryCount == 11)
        #expect(MasterRPGTipState.linkCount == 3)
        #expect(MasterRPGTipState.organizationCount == 2)
        #expect(MasterRPGTipState.adventureCount == 1)
        #expect(MasterRPGTipState.characterCount == 4)
        #expect(MasterRPGTipState.mapCount == 6)
    }

    /// `Tips.configure` may run only once per process.
    private static let tipsConfiguration: Result<Void, any Error> = Result {
        let datastoreURL = URL.temporaryDirectory.appending(
            path: "MasterRPGTipKitTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: datastoreURL,
            withIntermediateDirectories: true
        )
        try Tips.configure([
            .datastoreLocation(.url(datastoreURL)),
            .displayFrequency(.immediate)
        ])
    }

    private static func configureTipsOnce() throws {
        try tipsConfiguration.get()
    }

    private func wait(
        for expectedValue: Bool,
        in updates: some AsyncSequence<Bool, Never>
    ) async -> Bool {
        for await value in updates {
            if value == expectedValue {
                return true
            }
        }
        return false
    }
}
