// @copyright André Trettin

import Foundation
import Network
import SwiftUI
import os.log
import CoreRPG

struct BrowserController: Sendable {
    private let serviceType: GameServiceType
    private let browser: NWBrowser

    let model: BrowserModel
    private let dataModel: BrowserDataModel

    @MainActor
    init(isMaster: Bool = false, proxy: Bool = false) {
        let serviceType = BrowserController.serviceType(for: isMaster, isProxy: proxy)
        self.serviceType = serviceType
        self.model = BrowserModel()
        self.dataModel = BrowserDataModel()
        
        // Create parameters, and allow browsing over peer-to-peer link.
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        self.browser = NWBrowser(for: .bonjour(type: serviceType.serviceName, domain: nil), using: parameters)
        
        browser.stateUpdateHandler = { [self] newState in
            self.handle(newState: newState)
        }

        // When the list of discovered endpoints changes, refresh the delegate.
        browser.browseResultsChangedHandler = { [self] results, changes in
            self.refreshResults(results: results, changes: changes)
        }
        Logger.browserController.debug("Browser: Init for type: \(serviceType.serviceName)")
    }
    
    private static func serviceType(for isMaster: Bool, isProxy: Bool) -> GameServiceType {
        isMaster ? (isProxy ? .proxyClient : .master) : (isProxy ? .proxyServer : .player)
    }
}

// MARK: - Control

extension BrowserController {
    @MainActor
    func toggleBrowsing() {
        if isBrowsing {
            stop()
        } else {
            start()
        }
    }

    @MainActor
    func start() {
        guard isBrowsing == false else { return }
        let name = serviceType.serviceName
        Logger.browserController.debug("Browser: Start browsing \(name)")
        model.statusMessage = "Start browsing"
        startBrowsing()
    }

    @MainActor
    func stop() {
        let name = serviceType.serviceName
        Logger.browserController.debug("Browser: Stop browsing \(name)")

        Task { @concurrent in
            await stopBrowsing()
        }
        model.statusMessage = "Stop browsing"
    }
    
    var isBrowsing: Bool {
        browser.state == .ready
    }
    
    func allResults() async -> [NWBrowser.Result] {
        var results: [NWBrowser.Result] = []
        
        for browserModel in await model.browsers {
            guard let result = await browserResults(for: browserModel.id) else { continue }
            results.append(result)
        }
        return results
    }
}

extension BrowserController {
    func playerConection(for viewModel: BrowserDeviceModel) async -> PlayerBrowserModel? {
        guard let browserData = await browserResults(for: viewModel.id) else { return nil }
        return PlayerBrowserModel(name: viewModel.deviceName, endpoint: browserData.endpoint, interface: browserData.interfaces.first)
    }
}

private extension BrowserController {
    func startBrowsing() {
        let name = serviceType.serviceName
        Logger.browserController.debug("Browser: Start \(name, privacy: .public)")

        // Start browsing and ask for updates on the main queue.
        browser.start(queue: .main)
    }

    func stopBrowsing() async {
        let name = serviceType.serviceName
        Logger.browserController.debug("Browser: Stop \(name, privacy: .public)")
        browser.cancel()
        await resetState()
    }

    func handle(newState: NWBrowser.State) {
        let state = "\(newState)"
        let name = serviceType.serviceName
        Logger.browserController.debug("Browser: Newstate \(name, privacy: .public) state \(state, privacy: .public)")
        Task { @concurrent in
            switch newState {
            case let .failed(error):
                Logger.browserController.error("Browser: Failed \(name, privacy: .public) with \(error.localizedDescription, privacy: .public)")
                // Restart the browser if it loses its connection
                if error == NWError.dns(DNSServiceErrorType(kDNSServiceErr_DefunctConnection)) {
                    browser.cancel()
                    startBrowsing()
                } else {
                    browser.cancel()
                    await displayBrowseError(error)
                }
            case .ready:
                refreshResults(results: browser.browseResults, changes: nil)
            case .cancelled:
                refreshResults(results: Set(), changes: nil)
            default:
                break
            }
        }
    }
    
    func refreshResults(results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>?) {
        let name = serviceType.serviceName
        Logger.browserController.debug("Browser: Results \(name, privacy: .public) with \(results.debugDescription, privacy: .public)")
        Task { @concurrent in
            if let changes {
                for change in changes {
                    switch change {
                    case let .added(result):
                        await addResult(result)
                    case let .changed(old, new, _):
                        await replace(old, with: new)
                    case let .removed(result):
                        await removeResult(result)
                    case .identical:
                        break
                    @unknown default:
                        break
                    }
                }
            } else {
                await resetState()
                for result in results {
                    await addResult(result)
                }
            }
        }
    }

    func displayBrowseError(_ error: NWError) async {
        Logger.browserController.error("Browser: Error \(error.localizedDescription, privacy: .public)")
        await stopBrowsing()
        await MainActor.run { model.statusMessage = "Error: \(error.localizedDescription)" }
    }
}

private extension BrowserController {
    func addResult(_ result: NWBrowser.Result) async {
        let browserModel = BrowserDataModel.BrowserResultModel(id: UUID(), result: result)
        guard await dataModel.resetResult(id: browserModel.id, model: browserModel) == false else { return }
        Task { @MainActor in
            model.append(model: createViewModel(from: browserModel))
        }
    }

    func createViewModel(from model: BrowserDataModel.BrowserResultModel) -> BrowserDeviceModel {
        BrowserDeviceModel(id: model.id, deviceName: String(model.result.endpoint.debugDescription.prefix(while: { $0 != "." })), connectionMode: serviceType.connectionMode)
    }

    func replace(_ old: NWBrowser.Result, with new: NWBrowser.Result) async {
        guard let found = await dataModel.browserResults.first(where: { $0.value.result == old }) else {
            await addResult(new)
            return
        }
        await dataModel.resetResult(id: found.key, model: BrowserDataModel.BrowserResultModel(id: found.key, result: new))
    }

    func removeResult(_ old: NWBrowser.Result) async {
        guard let found = await dataModel.browserResults.first(where: { $0.value.result == old }) else {
            return
        }
        await dataModel.resetResult(id: found.key)
        Task { @MainActor in
            model.remove(id: found.key, result: found.value.result)
        }
    }

    func resetState() async {
        await dataModel.resetResults()
        Task { @MainActor in
            model.setBrowsers([])
        }
    }
    
    func browserResults(for id: UUID) async -> NWBrowser.Result? {
        await dataModel.browserResults[id]?.result
    }
}

fileprivate actor BrowserDataModel {
    struct BrowserResultModel: Sendable {
        let id: UUID
        let result: NWBrowser.Result
    }

    var browserResults: [UUID: BrowserResultModel] = [:]
    
    func resetResults() {
        browserResults = [:]
    }
    
    @discardableResult
    func resetResult(id: BrowserDeviceModel.ID, model: BrowserResultModel? = nil) -> Bool {
        if let model, let existing = browserResults.first(where: { $0.value.result.endpoint == model.result.endpoint })?.value {
            browserResults[existing.id] = model
            return true
        }
        
        browserResults[id] = model
        return false
    }
}

extension Logger {
    static let browserController = Logger(subsystem: subsystem, category: "BrowserController")
}
