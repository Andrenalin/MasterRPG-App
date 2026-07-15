// @copyright André Trettin

import Foundation

enum GameStatisticsFormat {
    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds)).formatted(
            .units(
                allowed: [.hours, .minutes, .seconds],
                width: .abbreviated,
                maximumUnitCount: 2
            )
        )
    }

    static func bytes(_ byteCount: Int64) -> String {
        byteCount.formatted(.byteCount(style: .file))
    }
}
