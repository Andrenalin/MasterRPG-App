// @copyright André Trettin

import Combine
import Foundation

@MainActor final class SharePlaySingleQueuePackageSender {
    init(packageSize: Int = SharePlaySingleQueuePackageSender.packageSize, sendPackage: @escaping (PackageMessage) async -> Void) {
        self.packageSize = packageSize
        self.sendPackage = sendPackage
    }

    private let packageSize: Int
    private let sendPackage: (PackageMessage) async -> Void

    static let packageSize = 16_000
    static let lowPackageCount = 60
    static let throttleInMilliSeconds = 200

    func send(data: Data) async {
        var counter = 0
        for package in packages(from: data) {
            await sendPackage(package)
            counter += 1
            if counter % Self.lowPackageCount == 0 {
                do {
                    try await Task.sleep(for: .milliseconds(Self.throttleInMilliSeconds))
                } catch {
                    // do nothing on cancel
                }
            }
        }
    }

    private func packages(from data: Data) -> [PackageMessage] {
        let uuid = UUID()
        let byteCount = data.count
        let total = (byteCount / packageSize) + 1

        var messages: [PackageMessage] = []
        var offset = 0
        var index = 1
        while offset < byteCount {
            let end = min(offset + packageSize, byteCount)
            let package = PackageMessage(uuid: uuid, count: index, total: total, data: data[offset ..< end])
            messages.append(package)
            offset = end
            index += 1
        }
        return messages
    }
}
