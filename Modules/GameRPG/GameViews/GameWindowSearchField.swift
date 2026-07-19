// @copyright André Trettin

import CoreRPG
import SwiftUI

#if os(macOS)
extension View {
    func gameWindowSearchable() -> some View {
        modifier(GameWindowSearchModifier())
    }
}

private struct GameWindowSearchModifier: ViewModifier {
    @Environment(GameScreenModel.self) private var gameScreenModel

    func body(content: Content) -> some View {
        @Bindable var searchContext = gameScreenModel.searchContext

        content
            .searchable(
                text: $searchContext.query,
                placement: .toolbar,
                prompt: Text("Search", bundle: .module)
            )
    }
}
#endif

#if os(iOS)
struct IOSGameSearchField: View {
    @Environment(GameScreenModel.self) private var gameScreenModel

    var body: some View {
        @Bindable var searchContext = gameScreenModel.searchContext

        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(
                text: $searchContext.query,
                prompt: Text("Search", bundle: .module)
            ) {
                Text("Search", bundle: .module)
            }
            .textFieldStyle(.plain)
            .submitLabel(.search)

            if !searchContext.query.isEmpty {
                Button("Clear Search", systemImage: "xmark.circle.fill") {
                    searchContext.query.removeAll()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 100, idealWidth: 220, maxWidth: 280, minHeight: 44)
        .contentShape(.capsule)
        .glassEffect(.regular.interactive(), in: .capsule)
        .layoutPriority(1)
    }
}

#Preview {
    IOSGameSearchField()
        .environment(GameScreenModel())
        .padding()
}
#endif
