// @copyright André Trettin

import RolePlayGameKit
import SwiftUI
import UniformTypeIdentifiers

/// The attachments of every input item: a share of several files arrives as several extension
/// items, and reading only the first dropped the rest.
private func shareAttachments(of context: NSExtensionContext?) -> [NSItemProvider] {
    (context?.inputItems ?? [])
        .compactMap { $0 as? NSExtensionItem }
        .flatMap { $0.attachments ?? [] }
}

#if os(iOS) || os(visionOS)

import UIKit

final class ShareViewController: UIViewController {
    // REMOVED: let appModel = AppModel()
    // The AppModel initialization is too heavy for a share extension
    // Instead, we now use the lightweight ShareExtensionDatabaseService
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        isModalInPresentation = true
        
        let itemProviders = shareAttachments(of: extensionContext)
        guard !itemProviders.isEmpty else {
            completeRequest(returningItems: [])
            return
        }
        
        // Use refactored SharingView with lightweight architecture
        let contentView = UIHostingController(
            rootView: SharingView(
                itemProviders: itemProviders,
                extensionContext: extensionContext
            )
        )
        
        addChild(contentView)
        view.addSubview(contentView.view)
        
        // Set up constraints
        contentView.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.view.topAnchor.constraint(equalTo: view.topAnchor),
            contentView.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentView.view.leftAnchor.constraint(equalTo: view.leftAnchor),
            contentView.view.rightAnchor.constraint(equalTo: view.rightAnchor)
        ])
        
        contentView.didMove(toParent: self)
    }
    
    private func completeRequest(returningItems items: [Any]?) {
        extensionContext?.completeRequest(returningItems: items)
    }
}

#else

import AppKit

class ShareViewController: NSViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let itemProviders = shareAttachments(of: extensionContext)
        guard !itemProviders.isEmpty else {
            // Nothing to share: finish the request, like the iOS controller does. Returning
            // without it left an empty share sheet with no way out. See CODE_AUDIT_21 §5.27.
            extensionContext?.completeRequest(returningItems: [])
            return
        }

        // Use refactored SharingView with lightweight architecture
        let contentView = NSHostingController(
            rootView: SharingView(
                itemProviders: itemProviders,
                extensionContext: extensionContext
            )
        )

        addChild(contentView)
        view.addSubview(contentView.view)

        // Set up constraints
        contentView.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.view.topAnchor.constraint(equalTo: view.topAnchor),
            contentView.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentView.view.leftAnchor.constraint(equalTo: view.leftAnchor),
            contentView.view.rightAnchor.constraint(equalTo: view.rightAnchor)
        ])
    }
}
#endif
