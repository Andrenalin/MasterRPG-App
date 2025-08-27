// @copyright André Trettin

import Foundation

extension Bundle {
    static let module: Bundle = Bundle(for: BundleModule.self)
}

private final class BundleModule {}

extension Bundle {
  func localizedString(forKey key: String) -> String {
    self.localizedString(forKey: key, value: nil, table: nil)
  }
}

extension String {
    var localizedString: String {
        Bundle.module.localizedString(forKey: self)
    }
}
