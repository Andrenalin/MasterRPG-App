// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

extension View {
    nonisolated public func inspectorAll<V>(isPresented: Binding<Bool>, @ViewBuilder content: () -> V) -> some View where V : View {
#if os(tvOS) || os(visionOS)
        self
#else
        inspector(isPresented: isPresented, content: content)
#endif
    }
    
    nonisolated public func listRowSeparatorAll(_ visibility: Visibility, edges: VerticalEdge.Set = .all) -> some View {
#if os(tvOS)
        self
#else
        listRowSeparator(visibility, edges: edges)
#endif
    }
    
    nonisolated public func swipeActionsAll<T>(edge: HorizontalEdge = .trailing, allowsFullSwipe: Bool = true, @ViewBuilder content: () -> T) -> some View where T : View {
#if os(tvOS)
        self
#else
        swipeActions(edge: edge, allowsFullSwipe: allowsFullSwipe, content: content)
#endif
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, *)
    nonisolated public func glassEffectAll() -> some View {
#if os(visionOS)
        self
#else
        glassEffect()
#endif
    }

#if !os(visionOS)
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, *)
    nonisolated public func glassEffectAll(_ style: Glass) -> some View {
        glassEffect(style)
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, *)
    nonisolated public func glassEffectAll<S>(_ style: Glass, in shape: S) -> some View where S : Shape {
        glassEffect(style, in: shape)
    }
#endif

    /// Applies keyboard shortcut on platforms that support it (excludes tvOS)
    nonisolated public func keyboardShortcutAll(_ key: KeyEquivalent, modifiers: EventModifiers = .command) -> some View {
#if os(tvOS)
        self
#else
        keyboardShortcut(key, modifiers: modifiers)
#endif
    }

    /// Applies keyboard shortcut on platforms that support it (excludes tvOS)
#if !os(tvOS)
    nonisolated public func keyboardShortcutAll(_ shortcut: KeyboardShortcut) -> some View {
        keyboardShortcut(shortcut)
    }
#else
    nonisolated public func keyboardShortcutAll(_ shortcut: Never) -> some View {
        self
    }
#endif

    /// Applies context menu on platforms that support it (excludes tvOS)
    @ViewBuilder
    nonisolated public func contextMenuAll<M>(@ViewBuilder menuItems: () -> M) -> some View where M : View {
#if os(tvOS)
        self
#else
        contextMenu(menuItems: menuItems)
#endif
    }

    /// Applies file importer on platforms that support it (excludes tvOS)
    nonisolated public func fileImporterAll(isPresented: Binding<Bool>, allowedContentTypes: [UTType], onCompletion: @escaping (Result<URL, Error>) -> Void) -> some View {
#if os(tvOS)
        self
#else
        fileImporter(isPresented: isPresented, allowedContentTypes: allowedContentTypes, onCompletion: onCompletion)
#endif
    }

    /// Applies file mover on platforms that support it (excludes tvOS)
    nonisolated public func fileMoverAll(isPresented: Binding<Bool>, file: URL?, onCompletion: @escaping (Result<URL, Error>) -> Void) -> some View {
#if os(tvOS)
        self
#else
        fileMover(isPresented: isPresented, file: file, onCompletion: onCompletion)
#endif
    }

    /// Applies file exporter on platforms that support it (excludes tvOS)
#if !os(tvOS)
    nonisolated public func fileExporterAll<C>(isPresented: Binding<Bool>, document: C?, contentType: UTType, defaultFilename: String? = nil, onCompletion: @escaping (Result<URL, Error>) -> Void) -> some View where C : FileDocument {
        fileExporter(isPresented: isPresented, document: document, contentType: contentType, defaultFilename: defaultFilename, onCompletion: onCompletion)
    }
#endif

    /// Applies scroll dismisses keyboard on platforms that support it (excludes visionOS)
#if !os(visionOS)
    nonisolated public func scrollDismissesKeyboardAll(_ mode: ScrollDismissesKeyboardMode) -> some View {
        scrollDismissesKeyboard(mode)
    }
#endif
}
