// @copyright André Trettin

import CoreRPG
import os.log
import SwiftUI
import UniformTypeIdentifiers

struct ImageItem: Identifiable, Hashable {
    let id = UUID()
    var imageData: Data
}

@MainActor
final class ItemProviderImporter {
    enum Error: Swift.Error {
        case noItems
        case failedToLoad
    }
    
    func loadImages(from items: [NSItemProvider]) async throws -> [ImageItem] {
        try await withCheckedThrowingContinuation { continuation in
            loadImages(from: items) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    func loadTexts(from items: [NSItemProvider]) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            loadTexts(from: items) { result in
                continuation.resume(with: result)
            }
        }
    }
}

@MainActor
fileprivate let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ItemProviderImporter")

private extension ItemProviderImporter {
    func loadImages(from items: [NSItemProvider], completion: @MainActor @Sendable @escaping (Result<[ImageItem], Error>) -> Void) {
        let permissibleTypes: [UTType] = [.image, .url]

        let providersAndTypes = items
            .compactMap {
                for type in permissibleTypes {
                    if $0.hasItemConformingToTypeIdentifier(type.identifier) {
                        return ($0, type)
                    }
                }
                return nil
            }

        let group = DispatchGroup()
        var images: [ImageItem] = []

        for (provider, type) in providersAndTypes {
            group.enter()
            loadImage(provider: provider, type: type) { result in
                defer { group.leave() }

                switch result {
                case .success(let image): images.append(image)
                case .failure(let error): logger.error("\(#function): \(error)")
                }
            }
        }

        group.notify(queue: .main) {
            guard !images.isEmpty else {
                let error = Error.noItems
                logger.warning("\(#function): \(error)")
                completion(.failure(error))
                return
            }

            completion(.success(images))
        }
    }

    func loadImage(provider: NSItemProvider, type: UTType, completion: @MainActor @Sendable @escaping (Result<ImageItem, Swift.Error>) -> Void) {
        provider.loadItem(forTypeIdentifier: type.identifier) { url, error in
            guard error == nil, let url = url as? URL else {
                DispatchQueue.main.async {
                    completion(.failure(error ?? Error.noItems))
                }
                return
            }

            URLSession.shared.dataTask(with: url) { data, _, error in
                guard error == nil, let data else {
                    DispatchQueue.main.async {
                        completion(.failure(error ?? Error.failedToLoad))
                    }
                    return
                }

                DispatchQueue.main.async {
                    completion(.success(ImageItem(imageData: data)))
                }
            }.resume()
        }
    }
    
    func loadTexts(from items: [NSItemProvider], completion: @MainActor @Sendable @escaping (Result<[String], Error>) -> Void) {
        let permissibleTypes: [UTType] = [.text, .plainText]

        let providersAndTypes = items
            .compactMap {
                for type in permissibleTypes {
                    if $0.hasItemConformingToTypeIdentifier(type.identifier) {
                        return ($0, type)
                    }
                }
                return nil
            }

        let group = DispatchGroup()
        var texts: [String] = []

        for (provider, type) in providersAndTypes {
            group.enter()
            loadText(provider: provider, type: type) { result in
                defer { group.leave() }

                switch result {
                case .success(let text): texts.append(text)
                case .failure(let error): logger.error("\(#function): \(error)")
                }
            }
        }

        group.notify(queue: .main) {
            guard !texts.isEmpty else {
                let error = Error.noItems
                logger.warning("\(#function): \(error)")
                completion(.failure(error))
                return
            }

            completion(.success(texts))
        }
    }

    func loadText(provider: NSItemProvider, type: UTType, completion: @MainActor @Sendable @escaping (Result<String, Swift.Error>) -> Void) {
        provider.loadItem(forTypeIdentifier: type.identifier) { text, error in
            guard error == nil, let text = text as? String else {
                DispatchQueue.main.async {
                    completion(.failure(error ?? Error.noItems))
                }
                return
            }
            DispatchQueue.main.async {
                completion(.success(text))
            }
        }
    }
}
