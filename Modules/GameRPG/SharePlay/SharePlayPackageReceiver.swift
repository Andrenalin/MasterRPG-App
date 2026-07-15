// @copyright André Trettin

import Foundation
import Combine

@MainActor @Observable
final class SharePlayPackageReceiver {
    private(set) var receivedPacakges: [UUID: PackageMessageList] = [:]

    func reset() {
        receivedPacakges.removeAll()
    }

    func received(package: PackageMessage) -> PackageMessage? {
        let packageList: PackageMessageList
        if let list = receivedPacakges[package.uuid] {
            list.received(package: package)
            packageList = list
        } else {
            packageList = PackageMessageList(initalPackage: package)
            receivedPacakges[package.uuid] = packageList
        }

        return processingPackages(list: packageList)
    }

    func processingPackages(list: PackageMessageList) -> PackageMessage? {
        guard list.isComplete else { return nil }
        receivedPacakges.removeValue(forKey: list.id)
        return list.package
    }
}

@MainActor @Observable
final class PackageMessageList {
    init(initalPackage: PackageMessage) {
        self.id = initalPackage.uuid
        self.total = initalPackage.total
        self.messages = [initalPackage.count: initalPackage]
    }

    let id: UUID
    let total: Int
    private var messages: [Int: PackageMessage]

    var packageCounter: Int {
        messages.count
    }

    var isComplete: Bool {
        packageCounter == total
    }

    func received(package: PackageMessage) {
        guard package.uuid == id, package.total == total, (1...total).contains(package.count) else { return }
        messages[package.count] = package
    }

    var package: PackageMessage {
        let data = (1...total).compactMap { messages[$0]?.data }.reduce(Data(), +)
        return PackageMessage(uuid: id, count: 1, total: 1, data: data)
    }
}
