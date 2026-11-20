// @copyright André Trettin

import Foundation
import SwiftUI

/// What can be made from a photo in a photo list.
public enum PhotoGenerationKind: Hashable, Sendable, CaseIterable {
    /// A map with the photo as background.
    case map
    /// A new Character with the photo as portrait.
    case character
    /// A copy of a Character the user chooses, with the photo as its new portrait.
    case characterClone
}

/// Makes an item from a photo. Like `ItemGenerationAction`, one action serves every photo list
/// and the host that provides it decides what it offers and does:
/// - a running game provides `.map` to the game master, who gets a temporary map in game memory
///   that is shown to the players and gone with the game (`GameRoot.generateFromPhotoAction`);
/// - the editor provides everything through `generateFromPhotoPresentation(root:)`: the items are
///   saved in the library and an alert offers to go to them.
/// Everywhere else it stays disabled and the photo list offers no such action.
public struct GenerateFromPhotoAction: Sendable, Equatable {
    /// `id` should be stable across the writer's re-renders so SwiftUI's environment diffing can
    /// skip invalidating readers when the same writer re-supplies the same closure. `kinds` is
    /// compared separately since it is state readers need to observe.
    public init(
        id: EnvironmentActionIdentity = .fresh(),
        kinds: Set<PhotoGenerationKind> = Set(PhotoGenerationKind.allCases),
        generate: @MainActor @escaping @Sendable (PhotoGenerationKind, UUID) -> Void
    ) {
        self.id = id
        self.kinds = kinds
        self.generate = generate
    }

    let id: EnvironmentActionIdentity
    public let kinds: Set<PhotoGenerationKind>
    private let generate: @MainActor @Sendable (PhotoGenerationKind, UUID) -> Void

    public var isEnabled: Bool { !kinds.isEmpty }

    public func supports(_ kind: PhotoGenerationKind) -> Bool {
        kinds.contains(kind)
    }

    /// - Parameter photoId: The photo that becomes the map's background or the Character's portrait.
    @MainActor
    public func callAsFunction(_ kind: PhotoGenerationKind, photoId: UUID) {
        guard supports(kind) else { return }
        generate(kind, photoId)
    }

    public static let disabled = GenerateFromPhotoAction(id: .unconfigured, kinds: []) { _, _ in }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.kinds == rhs.kinds
    }
}

public extension EnvironmentValues {
    @Entry var generateFromPhotoAction: GenerateFromPhotoAction = .disabled
}
