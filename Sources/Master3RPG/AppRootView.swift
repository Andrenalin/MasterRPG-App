import AndrenalinKit
import SwiftUI


enum RootRoute: Equatable, CaseIterable {
    case adventure
    case character
    case photo
    case pdf
    case audio
    case settings
    
    var title: String {
        switch self {
        case .adventure:
            return "Adventure"
        case .character:
            return "Character"
        case .photo:
            return "Photo"
        case .pdf:
            return "PDF"
        case .audio:
            return "Audio"
        case .settings:
            return "Settings"
        }
    }
    
    var icon: String {
        switch self {
        case .adventure: "wand.and.stars"
        case .character: "person.fill"
        case .photo: "photo"
        case .pdf: "doc.fill"
        case .audio: "music.note"
        case .settings: "gear"
        }
    }
}

extension RootRoute: @MainActor NavigationDestination {
    var body: some View {
        DetailView(rootRoute: self)
    }
}

struct AppRootView: View {
    @State private var selectedTab: RootRoute = .adventure
    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(RootRoute.allCases) { tab in
                Tab("", systemImage: tab.icon, value: tab) {
                    tab
                }
            }
        }

    }
}

struct DetailView: View {
    let rootRoute: RootRoute
    
    var body: some View {
        Text("rootRoute: \(rootRoute)")
    }
}

#Preview {
    AppRootView()
}
