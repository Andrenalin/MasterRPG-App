// @copyright André Trettin

import Foundation
import Testing
import TipKit

@testable import CoreRPG

@Suite("MasterRPG tip eligibility")
struct MasterRPGTipEligibilityTests {
    @Test("An empty ready database offers creation and import guidance")
    func emptyDatabase() {
        // Given
        let snapshot = makeSnapshot()

        // When / Then
        #expect(snapshot.shouldShowFirstItem)
        #expect(!snapshot.shouldShowFirstEntry)
        #expect(!snapshot.shouldShowOrganization)
        #expect(!snapshot.shouldShowLinking)
    }

    @Test("Existing or imported content suppresses first-item guidance")
    func existingContent() {
        // Given
        let snapshot = makeSnapshot(
            regularItemCount: 8,
            topLevelItemCount: 6,
            entryCount: 12,
            linkCount: 2,
            organizationCount: 2
        )

        // When / Then
        #expect(!snapshot.shouldShowFirstItem)
        #expect(!snapshot.shouldShowFirstEntry)
        #expect(!snapshot.shouldShowOrganization)
        #expect(!snapshot.shouldShowLinking)
    }

    @Test("The first-entry tip follows the first real item")
    func firstEntry() {
        // Given
        let snapshot = makeSnapshot(
            regularItemCount: 1,
            topLevelItemCount: 1
        )

        // When / Then
        #expect(!snapshot.shouldShowFirstItem)
        #expect(snapshot.shouldShowFirstEntry)
    }

    @Test("Organization guidance waits until the library has useful scale")
    func organizationThreshold() {
        // Given
        let beforeThreshold = makeSnapshot(
            regularItemCount: 3,
            topLevelItemCount: 3,
            entryCount: 1
        )
        let atThreshold = makeSnapshot(
            regularItemCount: 4,
            topLevelItemCount: 4,
            entryCount: 1
        )
        let alreadyOrganized = makeSnapshot(
            regularItemCount: 4,
            topLevelItemCount: 4,
            entryCount: 1,
            organizationCount: 1
        )

        // When / Then
        #expect(!beforeThreshold.shouldShowOrganization)
        #expect(atThreshold.shouldShowOrganization)
        #expect(!alreadyOrganized.shouldShowOrganization)
    }

    @Test("Link guidance requires two resources and an editable entry")
    func linkingPrerequisites() {
        // Given
        let noEntry = makeSnapshot(
            regularItemCount: 2,
            topLevelItemCount: 2
        )
        let readyToLink = makeSnapshot(
            regularItemCount: 2,
            topLevelItemCount: 2,
            entryCount: 1
        )
        let existingLink = makeSnapshot(
            regularItemCount: 2,
            topLevelItemCount: 2,
            entryCount: 1,
            linkCount: 1
        )

        // When / Then
        #expect(!noEntry.shouldShowLinking)
        #expect(readyToLink.shouldShowLinking)
        #expect(!existingLink.shouldShowLinking)
    }

    @Test("Game and map tips are based on available domain content")
    func domainPrerequisites() {
        // Given
        let snapshot = makeSnapshot(
            regularItemCount: 3,
            topLevelItemCount: 3,
            adventureCount: 1,
            characterCount: 1,
            mapCount: 1
        )

        // When / Then
        #expect(snapshot.shouldShowAdventureSelection)
        #expect(snapshot.shouldShowCharacterSelection)
        #expect(snapshot.shouldShowMapEditor)
        #expect(snapshot.shouldShowAnotherWindow)
    }

    @Test("No contextual tip is eligible before the database is ready")
    func databaseNotReady() {
        // Given
        let snapshot = makeSnapshot(
            databaseReady: false,
            regularItemCount: 5,
            topLevelItemCount: 5,
            entryCount: 2,
            adventureCount: 1,
            characterCount: 1,
            mapCount: 1
        )

        // When / Then
        #expect(!snapshot.shouldShowFirstItem)
        #expect(!snapshot.shouldShowFirstEntry)
        #expect(!snapshot.shouldShowOrganization)
        #expect(!snapshot.shouldShowLinking)
        #expect(!snapshot.shouldShowAdventureSelection)
        #expect(!snapshot.shouldShowCharacterSelection)
        #expect(!snapshot.shouldShowMapEditor)
        #expect(!snapshot.shouldShowAnotherWindow)
    }

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

    private func makeSnapshot(
        databaseReady: Bool = true,
        regularItemCount: Int = 0,
        topLevelItemCount: Int = 0,
        entryCount: Int = 0,
        linkCount: Int = 0,
        organizationCount: Int = 0,
        adventureCount: Int = 0,
        characterCount: Int = 0,
        mapCount: Int = 0
    ) -> MasterRPGTipEligibilitySnapshot {
        MasterRPGTipEligibilitySnapshot(
            databaseReady: databaseReady,
            regularItemCount: regularItemCount,
            topLevelItemCount: topLevelItemCount,
            entryCount: entryCount,
            linkCount: linkCount,
            organizationCount: organizationCount,
            adventureCount: adventureCount,
            characterCount: characterCount,
            mapCount: mapCount
        )
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
