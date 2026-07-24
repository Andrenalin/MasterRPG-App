// @copyright André Trettin

import SwiftUI

struct InlineSheetSearchControl: View {
    let module: NetworkModules
    @Binding var searchText: String

    @State private var isExpanded = false
    @FocusState private var isSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.appTheme) private var theme

    var body: some View {
        GlassEffectContainerAll {
            HStack(spacing: 4) {
                if isExpanded {
                    searchField
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                Button(
                    isExpanded ? "Close Search" : "Search",
                    systemImage: isExpanded ? "xmark" : "magnifyingglass",
                    action: toggleSearch
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
            }
            .padding(.leading, isExpanded ? 12 : 0)
#if os(visionOS)
            .background(.regularMaterial, in: .capsule)
#else
            .glassEffectAll(
                .regular
                    .tint(theme.tint(for: module).opacity(0.25))
                    .interactive(),
                in: .capsule
            )
#endif
        }
        .animation(accessibilityReduceMotion ? nil : .smooth, value: isExpanded)
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                Task {
                    await Task.yield()
                    guard !Task.isCancelled, isExpanded else { return }
                    isSearchFocused = true
                }
            } else {
                isSearchFocused = false
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            TextField(
                text: $searchText,
                prompt: Text("Search", bundle: .module)
            ) {
                Text("Search", bundle: .module)
            }
            .textFieldStyle(.plain)
            .focused($isSearchFocused)
#if os(iOS)
            .submitLabel(.search)
#endif

            if !searchText.isEmpty {
                Button("Clear Search", systemImage: "xmark.circle.fill") {
                    searchText.removeAll()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 160, idealWidth: 220, maxWidth: 280)
    }

    private func toggleSearch() {
        withAnimation(accessibilityReduceMotion ? nil : .smooth) {
            isExpanded.toggle()
            if !isExpanded {
                searchText.removeAll()
            }
        }
    }
}

#Preview {
    @Previewable @State var searchText = ""

    ZStack(alignment: .topTrailing) {
        LinearGradient(
            colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        InlineSheetSearchControl(module: .adventure, searchText: $searchText)
            .padding()
    }
}
