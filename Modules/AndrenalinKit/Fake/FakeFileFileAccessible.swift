// @copyright André Trettin

import Observation

struct FakeFileFileAccessible: FileUrlAccessible {
    func fileUrl(item: any Observable) async -> FileUrl? { nil }
    func setFileUrl(_ fileUrl: FileUrl?, item: any Observable) async {}
    func fetchFileUrl() async -> [FileUrl] { [] }
    func saveFileUrl(fileUrl: FileUrl) async {}
    func moveFiles() async throws {}
}
