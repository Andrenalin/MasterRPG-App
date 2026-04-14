// @copyright André Trettin

import RolePlayGameKit
import SwiftUI
import UniformTypeIdentifiers


#if os(iOS) || os(visionOS)

import UIKit

final class ShareViewController: UIViewController {
    // REMOVED: let appModel = AppModel()
    // The AppModel initialization is too heavy for a share extension
    // Instead, we now use the lightweight ShareExtensionDatabaseService
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        isModalInPresentation = true
        
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProviders = extensionItem.attachments else {
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

        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProviders = extensionItem.attachments else {
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
