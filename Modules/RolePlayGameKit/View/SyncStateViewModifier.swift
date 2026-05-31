// @copyright André Trettin

import CoreRPG
import SwiftUI

public extension View {
    /// Synchronizes two state properties bidirectionally.
    ///
    /// Use this modifier when you need to keep two sources of truth in sync,
    /// such as @SceneStorage and an @Observable model property.
    ///
    /// - Parameters:
    ///   - source: Binding to the source value (typically @SceneStorage)
    ///   - destination: Binding to the destination value (typically model property)
    ///   - onSync: Optional closure called after successful sync
    ///
    /// Example:
    /// ```
    /// .syncState(
    ///     source: $storedTab,
    ///     destination: $appModel.selectedModule
    /// )
    /// ```
    func syncState<T: Equatable>(
        source: Binding<T>,
        destination: Binding<T>,
        onSync: ((T) -> Void)? = nil
    ) -> some View {
        modifier(SyncStateViewModifier(
            source: source,
            destination: destination,
            onSync: onSync
        ))
    }

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

/// Synchronizes two non-optional state properties using the <=> operator
struct SyncStateViewModifier<T: Equatable>: ViewModifier {
    let source: Binding<T>
    let destination: Binding<T>
    let onSync: ((T) -> Void)?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard source.wrappedValue != destination.wrappedValue else { return }
                destination.wrappedValue <=> source.wrappedValue
                onSync?(source.wrappedValue)
            }
            .onChange(of: source.wrappedValue) {
                guard source.wrappedValue != destination.wrappedValue else { return }
                destination.wrappedValue <=> source.wrappedValue
                onSync?(source.wrappedValue)
            }
            .onChange(of: destination.wrappedValue) {
                guard source.wrappedValue != destination.wrappedValue else { return }
                source.wrappedValue <=> destination.wrappedValue
                onSync?(destination.wrappedValue)
            }
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
