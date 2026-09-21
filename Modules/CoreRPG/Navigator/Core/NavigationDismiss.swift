//
//  NavigationDismiss.swift
//  Navigator
//
//  Created by Michael Long on 11/27/24.
//

import SwiftUI

extension Navigator {

    /// Dismisses the currently presented ManagedNavigationStack.
    /// ```swift
    /// Button("Dismiss") {
    ///     navigator.dismiss()
    /// }
    /// ```
    /// Note that unlike Apple's dismiss environment variable, Navigator's dismiss function doesn't "pop" the current view on the navigation path.
    ///
    /// It exists solely to dismiss the currently presented view from within the
    /// currently presented view.
    @MainActor
    @discardableResult
    public func dismiss() -> Bool {
        guard let action = dismissAction else {
            return false
        }
        dismissAction = nil
        action()
        log(.navigation(.dismissed))
        parent?.removeChild(self)
        return true
    }

    /// Dismisses presented sheet or fullScreenCover views presented by this Navigator.
    /// ```swift
    /// Button("Dismiss") {
    ///     navigator.dismissPresentedViews()
    /// }
    /// ```
    /// This is used in the parent view to dismiss its children, effectively the opposite of `dismiss()`.
    @MainActor
    public func dismissPresentedViews() {
        sheet = nil
        cover = nil
    }

    /// Dismisses *any* `ManagedNavigationStack` or `ManagedPresentationView` presented by this Navigator
    /// or by any child of this Navigator in the current navigation tree.
    /// ```swift
    /// Button("Dismiss") {
    ///     navigator.dismissAny()
    /// }
    /// ```
    /// This is used in the parent view to dismiss its children, effectively the opposite of `dismiss()`.
    @MainActor
    @discardableResult
    public func dismissAnyChildren() -> Bool {
        for child in _children.values {
            if let childNavigator = child.object {
                if childNavigator.dismiss() || childNavigator.dismissAnyChildren() {
                    return true
                }
            }
        }
        return false
    }

    /// Returns to the root Navigator and dismisses *any* presented `ManagedNavigationStack` or `ManagedPresentationView`.
    /// ```swift
    /// Button("Dismiss") {
    ///     navigator.dismissAny()
    /// }
    /// ```
    /// This functionality is used extensively in deep linking and cross-module linking in
    /// order to clear any presented views prior to taking the user elsewhere in the application.
    @MainActor
    @discardableResult
    public func dismissAny() throws -> Bool {
        guard !isNavigationLocked else {
            log(.warning("Navigator \(id) error navigation locked"))
            throw NavigationError.navigationLocked
        }
        return root.dismissAnyChildren()
    }

}
