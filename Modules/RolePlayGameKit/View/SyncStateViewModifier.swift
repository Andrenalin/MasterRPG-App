// @copyright André Trettin

import CoreRPG
import SwiftUI

public extension View {
    /// Synchronizes optional state properties bidirectionally.
    func syncOptionalState<T: Equatable>(
        source: Binding<T>,
        destination: Binding<T?>,
        onSync: ((T) -> Void)? = nil
    ) -> some View {
        modifier(SyncOptionalStateViewModifier(
            source: source,
            destination: destination,
            onSync: onSync
        ))
    }
}

/// Synchronizes optional and non-optional state properties
struct SyncOptionalStateViewModifier<T: Equatable>: ViewModifier {
    let source: Binding<T>
    let destination: Binding<T?>
    let onSync: ((T) -> Void)?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard destination.wrappedValue != source.wrappedValue else { return }
                destination.wrappedValue = source.wrappedValue
                onSync?(source.wrappedValue)
            }
            .onChange(of: source.wrappedValue) {
                guard destination.wrappedValue != source.wrappedValue else { return }
                destination.wrappedValue = source.wrappedValue
                onSync?(source.wrappedValue)
            }
            .onChange(of: destination.wrappedValue) {
                guard let newValue = destination.wrappedValue else { return }
                guard source.wrappedValue != newValue else { return }
                source.wrappedValue = newValue
                onSync?(newValue)
            }
    }
}
