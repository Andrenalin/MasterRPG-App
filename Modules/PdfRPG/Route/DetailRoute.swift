// @copyright André Trettin

import CoreRPG

import SwiftUI

#Preview(traits: .mockData) {
    ViewerRouteDestinationView(itemId: PdfModel.previewId, entryId: nil)
}

enum DetailRoute: Equatable, Hashable, Codable {
    case viewer(UUID, UUID?)
}

extension DetailRoute: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .viewer(let id, let entryId): "viewer/\(id.uuidString)\(entryId == nil ? "" : "/\(entryId!.uuidString)")"
        }
    }

    public init?(rawValue: String) {
        let values = rawValue.split(separator: "/")
        let count = values.count
        guard count == 2 || count == 3, let token = values.first else { return nil }
        let itemId: UUID? = UUID(uuidString: String(values[1]))
        let entryId: UUID? = count == 3 ? UUID(uuidString: String(values[2])) : nil
        guard let itemId else { return nil }
        switch token {
        case "viewer": self = .viewer(itemId, entryId)
        default: return nil
        }
    }
}

extension DetailRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .viewer(let itemId, let entryId):
            ViewerRouteDestinationView(itemId: itemId, entryId: entryId)
        }
    }
}

struct ViewerRouteDestinationView: View {
    let itemId: UUID
    let entryId: UUID?

    @Environment(PdfRootModel.self) private var root
    @Environment(AppWindowSizeModel.self) private var appSizeModel
    
    var body: some View {
        root.viewController.viewer(root: root, itemId: itemId, entryId: entryId, configuration: ViewerConfiguration(closeButton: appSizeModel.mode == .compact))
            .moduleTint(root.configurable.module)
    }
}
