// @copyright André Trettin

import Foundation

final class FilePresenter: NSObject, NSFilePresenter {
    let fileURL: URL
    var presentedItemOperationQueue: OperationQueue = .main

    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }

    deinit {
        NSFileCoordinator.removeFilePresenter(self)
    }

    var presentedItemURL: URL? {
        fileURL
    }

    func presentedItemDidChange() {
        //print("file changed")
    }
}
