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

    // Apple's guidance for GroupSessionMessenger.send(_:to:) is that "small
    // messages can include up to 256 kilobytes of data" (Synchronizing data
    // during a SharePlay activity). 16 KB chunks meant a multi-MB repair
    // transfer needed 10x more round trips than necessary; 200 KB stays under
    // that ceiling with headroom for the PackageMessage/GameNetworkModel
    // envelope overhead, cutting both message count and the throttle below.
    static let packageSize = 200_000
    static let lowPackageCount = 60
    static let throttleInMilliSeconds = 200

    func send(data: Data) async {
        var counter = 0
        for package in makePackages(from: data) {
            await sendPackage(package)
            counter += 1
            if counter % Self.lowPackageCount == 0 {
                do {
                    try await Task.sleep(for: .milliseconds(Self.throttleInMilliSeconds))
                } catch is CancellationError {
                    return
                } catch {
                    // Task.sleep only throws CancellationError
                }
            }
        }
    }

    // nonisolated: pure computation on immutable let properties, safe to call from any context
    nonisolated private func makePackages(from data: Data) -> [PackageMessage] {
        let uuid = UUID()
        let size = packageSize
        guard !data.isEmpty else {
            return [PackageMessage(uuid: uuid, count: 1, total: 1, data: Data())]
        }
        let total = (data.count + size - 1) / size
        return stride(from: 0, to: data.count, by: size).map { offset in
            let end = min(offset + size, data.count)
            return PackageMessage(uuid: uuid, count: (offset / size) + 1, total: total, data: data[offset..<end])
        }
    }
}
