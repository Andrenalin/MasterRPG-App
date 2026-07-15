// @copyright André Trettin

import Combine
import Foundation

@MainActor final class SharePlaySingleQueuePackageSender {
    init(
        packageSize: Int = SharePlaySingleQueuePackageSender.packageSize,
        retryDelays: [Duration] = SharePlaySingleQueuePackageSender.defaultRetryDelays,
        sendPackage: @escaping (PackageMessage) async throws -> Void
    ) {
        self.packageSize = packageSize
        self.retryDelays = retryDelays
        self.sendPackage = sendPackage
    }

    private let packageSize: Int
    private let retryDelays: [Duration]
    private let sendPackage: (PackageMessage) async throws -> Void

    // Apple's guidance for GroupSessionMessenger.send(_:to:) is that "small
    // messages can include up to 256 kilobytes of data". `Data` expands when
    // Codable encodes it as Base64, and JSON escaping can double slash-heavy
    // Base64 output: a worst-case 128 KB chunk encodes to about 341 KB. 64 KB
    // keeps that same worst case near 171 KB and leaves transport headroom.
    static let packageSize = 64_000
    static let encodedMessageSizeLimit = 256_000
    static let defaultRetryDelays: [Duration] = [.milliseconds(100), .milliseconds(300)]
    static let lowPackageCount = 60
    static let throttleInMilliSeconds = 200

    func send(data: Data) async throws {
        var counter = 0
        for package in makePackages(from: data) {
            try Task.checkCancellation()
            try await sendWithRetry(package)
            counter += 1
            if counter % Self.lowPackageCount == 0 {
                try await Task.sleep(for: .milliseconds(Self.throttleInMilliSeconds))
            }
        }
    }

    private func sendWithRetry(_ package: PackageMessage) async throws {
        var retryIndex = 0
        while true {
            do {
                try await sendPackage(package)
                return
            } catch let error as CancellationError {
                throw error
            } catch {
                guard retryIndex < retryDelays.count else { throw error }
                let delay = retryDelays[retryIndex]
                retryIndex += 1
                try await Task.sleep(for: delay)
            }
        }
    }

    nonisolated func packageCount(for data: Data) -> Int {
        guard !data.isEmpty else { return 1 }
        return (data.count + packageSize - 1) / packageSize
    }

    // nonisolated: pure computation on immutable let properties, safe to call from any context
    nonisolated private func makePackages(from data: Data) -> [PackageMessage] {
        let uuid = UUID()
        let size = packageSize
        guard !data.isEmpty else {
            return [PackageMessage(uuid: uuid, count: 1, total: 1, data: Data())]
        }
        let total = packageCount(for: data)
        return stride(from: 0, to: data.count, by: size).map { offset in
            let end = min(offset + size, data.count)
            return PackageMessage(uuid: uuid, count: (offset / size) + 1, total: total, data: data[offset..<end])
        }
    }
}
