// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

public enum PdfRoute: Equatable, Hashable, Codable {
    case detail(UUID)
    case viewer(UUID)
    
}

extension PdfRoute: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .detail(let id): "detail/\(id.uuidString)"
        case .viewer(let id): "viewer/\(id.uuidString)"
        }
    }

    public init?(rawValue: String) {
        let values = rawValue.split(separator: "/")
        guard let token = values.first, let idString = values.last, let uuid = UUID(uuidString: String(idString)) else { return nil }
        switch token {
        case "detail": self = .detail(uuid)
        case "viewer": self = .viewer(uuid)
        default: return nil
        }
    }
}

extension PdfRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .detail(let itemId):
            DetailRouteDestinationView(itemId: itemId)
        case .viewer(let itemId):
            ViewerRouteDestinationView(itemId: itemId)
        }
    }
}

struct DetailRouteDestinationView: View {
    init(itemId: UUID) {
        self.itemId = itemId
        self._items = Query(filter: #Predicate<PdfDataModel>{ $0.id == itemId })
    }
    
    let itemId: UUID

    @Query private var items: [PdfDataModel]
    
    var body: some View {
        if let item = items.first {
            DetailView(model: item)
        }
    }
}

struct ViewerRouteDestinationView: View {
    init(itemId: UUID) {
        self.itemId = itemId
    }
    
    let itemId: UUID

    @Environment(PdfRootModel.self) private var root: PdfRootModel
    
    var body: some View {
        root.viewController.viewPdfInline(with: itemId, withoutBookmark: false)
    }
}
