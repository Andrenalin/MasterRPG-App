// @copyright André Trettin

import SwiftUI

public enum WideMode: Hashable, Sendable {
    case small
    case wide
    case large
}

public extension EnvironmentValues {
    var wideMode: WideMode {
        get { self[WideModeKey.self] }
        set { self[WideModeKey.self] = newValue }
    }
    
    var safeAreaInsets: EdgeInsets {
        get { self[SafeAreaInsetsKey.self] }
        set { self[SafeAreaInsetsKey.self] = newValue }
    }
}

public struct SmallWideView<Small: View, Wide: View, Large: View>: View {
    public let small: () -> Small
    public let wide: () -> Wide
    public let large: () -> Large
    
    public init(@ViewBuilder small: @escaping () -> Small, @ViewBuilder wide: @escaping () -> Wide, @ViewBuilder large: @escaping () -> Large) {
        self.small = small
        self.wide = wide
        self.large = large
    }
    
#if os(iOS) || os(visionOS)
    @State private var screenSize: CGSize = .init(width: 300, height: 300)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var hasSmallWidth: Bool {
        horizontalSizeClass == .compact || screenSize.width < 1000
    }
    
    var hasLargeWidth: Bool {
        screenSize.width > 1250
    }
#endif
    
    public var body: some View {
#if os(iOS) || os(visionOS)
        ZStack(alignment: .top) {
            Color.clear
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: {
                    screenSize = $0
                }
            
            if hasSmallWidth {
                small()
                    .environment(\.wideMode, .small)
            } else if hasLargeWidth {
                large()
                    .environment(\.wideMode, .large)
            } else {
                wide()
                    .environment(\.wideMode, .wide)
            }
        }
#else
        large()
            .environment(\.wideMode, .large)
#endif
    }
}

public extension SmallWideView where Wide == Small {
    init(@ViewBuilder tab: @escaping () -> Small, @ViewBuilder side: @escaping () -> Large) {
        small = tab
        wide = tab
        large = side
    }
}

public extension View {
    func setWideMode() -> some View {
        modifier(SmallWideLargeViewModifier())
    }
}

struct SmallWideLargeViewModifier: ViewModifier {
#if os(iOS) || os(visionOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
#endif
    
    func body(content: Content) -> some View {
#if os(iOS) || os(visionOS)
        content
            .environment(\.wideMode, size)
            .environment(\.safeAreaInsets, UIApplication.keyWindow?.safeAreaInsets.swiftUiInsets ?? .init())
#else
        content
#endif
    }
    
#if os(iOS) || os(visionOS)
    var size: WideMode {
        if horizontalSizeClass == .regular && verticalSizeClass == .regular {
            return .wide
        }
        return .small
    }
#endif
}

struct WideModeKey: EnvironmentKey {
#if os(macOS)
    static let defaultValue: WideMode = .large
#elseif os(tvOS)
    static let defaultValue: WideMode = .small
#elseif os(visionOS)
    static let defaultValue: WideMode = .wide
#else
    static let defaultValue: WideMode = .small
#endif
}

private struct SafeAreaInsetsKey: EnvironmentKey {
    static let defaultValue: EdgeInsets = .init()
}

#if os(iOS) || os(visionOS)
extension UIApplication {
    @MainActor
    static var keyWindow: UIWindow? {
        UIApplication.shared
            .connectedScenes.lazy
            .compactMap { $0.activationState == .foregroundActive ? ($0 as? UIWindowScene) : nil }
            .first(where: { $0.keyWindow != nil })?
            .keyWindow
    }
}

private extension UIEdgeInsets {
    var swiftUiInsets: EdgeInsets {
        EdgeInsets(top: top, leading: left, bottom: bottom, trailing: right)
    }
}
#endif

#Preview {
    SmallWideView {
        TabView {
            Tab {
                NavigationStack {
                    Text("TabBar")
                }
                .foregroundStyle(.blue)
            } label: {
                Text("Hello")
            }
        }
    } wide: {
        Text("SideBar")
            .font(.largeTitle)
            .foregroundStyle(.blue)
    } large: {
        Text("Large").font(.largeTitle)
    }
}
