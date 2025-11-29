// @copyright André Trettin

import Foundation

extension Bundle {
    static let module: Bundle = Bundle(for: BundleModule.self)
}

private final class BundleModule {}
