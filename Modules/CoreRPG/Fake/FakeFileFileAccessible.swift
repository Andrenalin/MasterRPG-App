// @copyright André Trettin

import Observation

struct FakeFileFileAccessible: FileUrlAccessible {
    func saveFileUrl(fileUrl: FileUrl) async {}
}
