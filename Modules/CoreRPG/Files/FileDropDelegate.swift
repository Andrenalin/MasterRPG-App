// @copyright André Trettin

#if !os(tvOS)
import SwiftUI
import UniformTypeIdentifiers

public struct FileDropDelegate: DropDelegate {
    public init(for types: [UTType], updateFile: @escaping (URL) -> Void) {
        self.types = types
        self.updateFile = updateFile
    }

    let types: [UTType]
    let updateFile: (URL) -> Void

    public func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: types)
    }

    public func dropEntered(info _: DropInfo) {
#if os(macOS)
        NSSound(named: "Morse")?.play()
#endif
    }

    public func performDrop(info: DropInfo) -> Bool {
        receiveDrop(itemProviders: info.itemProviders(for: [.fileURL]))
    }

    func receiveDrop(itemProviders: [NSItemProvider]) -> Bool {
        for provider in itemProviders {
            guard provider.canLoadObject(ofClass: URL.self) else { continue }
            let _ = provider.loadObject(ofClass: URL.self) { object, error in
                if let url = object {
                    Task { @MainActor in
                        updateFile(url)
                    }
                }
            }
        }
        return true
    }

    public func dropUpdated(info _: DropInfo) -> DropProposal? {
        nil
    }

    public func dropExited(info _: DropInfo) {}
}

#endif
