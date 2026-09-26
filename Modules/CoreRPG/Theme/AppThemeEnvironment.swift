// @copyright André Trettin

import SwiftUI

private struct AppThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppThemeCatalog.arcane.resolve(
        colorScheme: .dark,
        contrast: .increased
    )
}

public extension EnvironmentValues {
    @Entry var appTheme: ResolvedAppTheme = AppThemeEnvironmentKey.defaultValue
}

public extension View {
    func appTheme(_ theme: ResolvedAppTheme) -> some View {
        environment(\.appTheme, theme)
    }

    func moduleTint(_ module: NetworkModules) -> some View {
        modifier(ModuleTintViewModifier(module: module))
    }

    func moduleForegroundStyle(
        _ module: NetworkModules,
        opacity: Double = 1
    ) -> some View {
        modifier(ModuleForegroundStyleViewModifier(module: module, opacity: opacity))
    }

    func moduleListItemTint(_ module: NetworkModules) -> some View {
        modifier(ModuleListItemTintViewModifier(module: module))
    }

    func themedSurface() -> some View {
        modifier(ThemedSurfaceViewModifier())
    }

    func themedListSurface() -> some View {
        modifier(ThemedListSurfaceViewModifier())
    }
}

private struct ModuleTintViewModifier: ViewModifier {
    let module: NetworkModules

    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content
            .tint(theme.tint(for: module))
            // Kept despite the soft deprecation: `.tint` doesn't change `Color.accentColor`,
            // and ~75 views read `Color.accentColor` for the per-module theme colour; this is
            // the only way to scope it to a subtree. See CODE_AUDIT_18 §4.1.
            .accentColor(theme.tint(for: module))
    }
}

private struct ModuleForegroundStyleViewModifier: ViewModifier {
    let module: NetworkModules
    let opacity: Double

    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content.foregroundStyle(theme.tint(for: module).opacity(opacity))
    }
}

private struct ModuleListItemTintViewModifier: ViewModifier {
    let module: NetworkModules

    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content.listItemTint(theme.tint(for: module))
    }
}

private struct ThemedSurfaceViewModifier: ViewModifier {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    theme.canvas.color
                        .ignoresSafeArea()
                } else {
                    theme.backgroundGradient
                        .ignoresSafeArea()
                }
            }
    }
}

private struct ThemedListSurfaceViewModifier: ViewModifier {
    func body(content: Content) -> some View {
#if os(tvOS)
        content.themedSurface()
#else
        content
            .scrollContentBackground(.hidden)
            .themedSurface()
#endif
    }
}
