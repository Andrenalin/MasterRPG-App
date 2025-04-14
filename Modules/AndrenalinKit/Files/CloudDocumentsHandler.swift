// @copyright André Trettin

import Foundation

actor CloudDocumentsHandler {
    let coordinator = NSFileCoordinator()
    var filePresenters: [URL: FilePresenter] = [:]

    func write(targetURL: URL, data: Data) throws {
        var coordinationError: NSError?
        var writeError: Error?

        coordinator.coordinate(writingItemAt: targetURL, options: [.forDeleting], error: &coordinationError) { url in
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                writeError = error
            }
        }

        if let error = writeError {
            throw error
        }

        if let coordinationError = coordinationError {
            throw coordinationError
        }
    }

    func read(url: URL) throws -> Data {
        var coordinationError: NSError?
        var readData: Data?
        var readError: Error?

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
            do {
                readData = try Data(contentsOf: url)
            } catch {
                readError = error
            }
        }

        if let error = readError {
            throw error
        }

        if let coordinationError = coordinationError {
            throw coordinationError
        }

        guard let data = readData else {
            throw NSError(domain: "CloudDocumentsHandlerError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data was read from the file."])
        }

        return data
    }

    func startMonitoringFile(at url: URL) {
        let presenter = FilePresenter(fileURL: url)
        filePresenters[url] = presenter
    }

    func stopMonitoringFile(at url: URL) {
        if let presenter = filePresenters[url] {
            NSFileCoordinator.removeFilePresenter(presenter)
        }
        filePresenters[url] = nil
    }
}

extension CloudDocumentsHandler {
    func download(url: URL) throws {
        var coordinationError: NSError?
        var downloadError: Error?

        coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) { newURL in
            do {
                try FileManager.default.startDownloadingUbiquitousItem(at: newURL)
            } catch {
                downloadError = error
            }
        }

        if let error = downloadError {
            throw error
        }

        if let coordinationError = coordinationError {
            throw coordinationError
        }
    }

    func evict(url: URL) throws {
        do {
            try FileManager.default.evictUbiquitousItem(at: url)
        } catch {
            throw error
        }
    }

    func moveFile(at sourceURL: URL, to destinationURL: URL) throws {
        var coordinationError: NSError?
        var moveError: Error?

        coordinator.coordinate(writingItemAt: sourceURL, options: .forMoving, writingItemAt: destinationURL, options: .forReplacing, error: &coordinationError) { newSourceURL, newDestinationURL in
            do {
                try FileManager.default.moveItem(at: newSourceURL, to: newDestinationURL)
            } catch {
                moveError = error
            }
        }

        if let error = moveError {
            throw error
        }

        if let coordinationError = coordinationError {
            throw coordinationError
        }
    }
}
