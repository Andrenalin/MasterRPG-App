// @copyright André Trettin

import Foundation

public final class Resources {
    public static let bundle = Bundle.module
}

extension Bundle {
    static let module: Bundle = Bundle(for: BundleModule.self)
}

private final class BundleModule {}
