// @copyright André Trettin

import RoleGameKit
import SwiftUI
import UniformTypeIdentifiers


#if os(iOS) || os(visionOS)

import UIKit

final class ShareViewController: UIViewController {
    let appModel = AppModel()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        isModalInPresentation = true
        if let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem, let itemProviders = extensionItem.attachments {
            
            let contentView = UIHostingController(rootView: SharingView(itemProviders: itemProviders, extensionContext: extensionContext))
            self.addChild(contentView)
            self.view.addSubview(contentView.view)

            // set up constraints
            contentView.view.translatesAutoresizingMaskIntoConstraints = false
            contentView.view.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
            contentView.view.bottomAnchor.constraint (equalTo: self.view.bottomAnchor).isActive = true
            contentView.view.leftAnchor.constraint(equalTo: self.view.leftAnchor).isActive = true
            contentView.view.rightAnchor.constraint (equalTo: self.view.rightAnchor).isActive = true
        }
    }
//        // Ensure access to extensionItem and itemProvider
//        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem, let itemProvider = extensionItem.attachments?.first else {
//            close()
//            return
//        }
//        
//        // Check type identifier
//        let textDataType = UTType.plainText.identifier
//        if itemProvider.hasItemConformingToTypeIdentifier(textDataType) {
//            // Load the item from itemProvider
//            itemProvider.loadItem(forTypeIdentifier: textDataType , options: nil) { (providedText, error) in
//                if let error {
//                    Task { @MainActor in
//                        self.close()
//                    }
//                    return
//                }
//                
//                if let text = providedText as? String {
//                    Task { @MainActor in
//                        // host the SwiftU view
//                        let contentView = UIHostingController(rootView: SharingView(text: text))
//                        self.addChild(contentView)
//                        self.view.addSubview(contentView.view)
//                        
//                        // set up constraints
//                        contentView.view.translatesAutoresizingMaskIntoConstraints = false
//                        contentView.view.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
//                        contentView.view.bottomAnchor.constraint (equalTo: self.view.bottomAnchor).isActive = true
//                        contentView.view.leftAnchor.constraint(equalTo: self.view.leftAnchor).isActive = true
//                        contentView.view.rightAnchor.constraint (equalTo: self.view.rightAnchor).isActive = true
//                    }
//                } else {
//                    Task { @MainActor in
//                        self.close()
//                    }
//                    return
//                }
//            }
//        } else {
//            close()
//            return
//        }
//        
//        NotificationCenter.default.addObserver(forName: NSNotification.Name("close"), object: nil, queue: nil) { _ in
//            Task { @MainActor in
//                self.close()
//            }
//        }
//    }
//    
//    func close() {
//        self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
//    }
}

#else

import AppKit

class ShareViewController: NSViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        if let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem, let itemProviders = extensionItem.attachments {
            
            let contentView = NSHostingController(rootView: SharingView(itemProviders: itemProviders, extensionContext: extensionContext))
            self.addChild(contentView)
            self.view.addSubview(contentView.view)

            // set up constraints
            contentView.view.translatesAutoresizingMaskIntoConstraints = false
            contentView.view.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
            contentView.view.bottomAnchor.constraint (equalTo: self.view.bottomAnchor).isActive = true
            contentView.view.leftAnchor.constraint(equalTo: self.view.leftAnchor).isActive = true
            contentView.view.rightAnchor.constraint (equalTo: self.view.rightAnchor).isActive = true
        }

    }
}
//
//        // Ensure access to extensionItem and itemProvider
//        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem, let itemProvider = extensionItem.attachments?.first else {
//            close()
//            return
//        }
//        
//        // Check type identifier
//        let textDataType = UTType.plainText.identifier
//        if itemProvider.hasItemConformingToTypeIdentifier(textDataType) {
//            // Load the item from itemProvider
//            itemProvider.loadItem(forTypeIdentifier: textDataType , options: nil) { (providedText, error) in
//                if let error {
//                    Task { @MainActor in
//                        self.close()
//                    }
//                    return
//                }
//                
//                if let text = providedText as? String {
//                    Task { @MainActor in
//                        // host the SwiftU view
//                        let contentView = NSHostingController(rootView: SharingView(text: text))
//                        self.addChild(contentView)
//                        self.view.addSubview(contentView.view)
//                        
//                        // set up constraints
//                        contentView.view.translatesAutoresizingMaskIntoConstraints = false
//                        contentView.view.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
//                        contentView.view.bottomAnchor.constraint (equalTo: self.view.bottomAnchor).isActive = true
//                        contentView.view.leftAnchor.constraint(equalTo: self.view.leftAnchor).isActive = true
//                        contentView.view.rightAnchor.constraint (equalTo: self.view.rightAnchor).isActive = true
//                    }
//                } else {
//                    Task { @MainActor in
//                        self.close()
//                    }
//                    return
//                }
//            }
//        } else {
//            close()
//            return
//        }
//        
//        NotificationCenter.default.addObserver(forName: NSNotification.Name("close"), object: nil, queue: nil) { _ in
//            Task { @MainActor in
//                self.close()
//            }
//        }
//    }
    
//    func close() {
//        self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
//    }
#endif
