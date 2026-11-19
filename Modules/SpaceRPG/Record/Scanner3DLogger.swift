// @copyright André Trettin

import CoreRPG
import os

extension Logger {
    /// The capture pipeline's log. Not behind the device-only gate of the capture views, so the
    /// parts of the pipeline that need no camera (`OnboardingStateMachine`, `CaptureFolderManager`)
    /// build, and are tested, on the simulator. See CODE_AUDIT_TestGaps §5.10.
    static let scanner3D = Logger(subsystem: subsystem, category: "Scanner3D")
}
