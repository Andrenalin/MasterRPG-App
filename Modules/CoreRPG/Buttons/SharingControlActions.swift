// @copyright André Trettin

import SwiftUI

public struct SharingControlActions: Equatable, Sendable {
    /// `id` should be stable across the writer's re-renders (e.g. the owning
    /// root model's `ObjectIdentifier`) so SwiftUI's environment diffing can
    /// skip invalidating readers when the same root writes the same
    /// functional closures again.
    public init(id: EnvironmentActionIdentity = .fresh(), control: (@MainActor @Sendable () -> [SharingControlModel])?, update: (@MainActor @Sendable ([SharingControlModel]) -> Void)?) {
        self.id = id
        self.control = control
        self.update = update
    }

    let id: EnvironmentActionIdentity
    public let control: (@MainActor @Sendable () -> [SharingControlModel])?
    public let update: (@MainActor @Sendable ([SharingControlModel]) -> Void)?

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

public extension EnvironmentValues {
    var sharingControlActions: SharingControlActions {
        get { self[SharingControlActionsKey.self] }
        set { self[SharingControlActionsKey.self] = newValue }
    }
}

public struct SharingControlModel: Identifiable, Equatable, Codable, Sendable {
    public init(id: UUID, name: String, show: Bool) {
        self.id = id
        self.name = name
        self.show = show
    }

    public let id: UUID
    public let name: String
    public var show: Bool
}

public extension [SharingControlModel] {
    /// The subset of players a share/send control should list — visible, name-sorted.
    /// Was hand-duplicated verbatim across `GameShareView`, `TableGenerationOccurrenceHeaderView`,
    /// and `TableGenerationSaveSendButton`. See CODE_AUDIT §8.3.
    var visibleSortedByName: [SharingControlModel] {
        filter(\.show)
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
}

struct SharingControlActionsKey: EnvironmentKey {
    static let defaultValue = SharingControlActions(control: nil, update: nil)
}
