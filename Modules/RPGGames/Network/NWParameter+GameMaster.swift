// @copyright André Trettin

import CryptoKit
import Foundation
import Network

protocol ConnectionAbstraction: AnyObject {
    var debugDescription: String { get }
    var stateUpdateHandler: (@Sendable (_ state: NWConnection.State) -> Void)? { get set }

    func cancel()
    func send(content: Data?, contentContext: NWConnection.ContentContext, isComplete: Bool, completion: NWConnection.SendCompletion)
    func start(queue: DispatchQueue)
    func receiveMessage(completion: @escaping @Sendable (_ completeContent: Data?, _ contentContext: NWConnection.ContentContext?, _ isComplete: Bool, _ error: NWError?) -> Void)
}

extension NWConnection: ConnectionAbstraction {}

extension NWConnection {
    static func connection(endpoint: NWEndpoint) -> NWConnection {
        NWConnection(to: endpoint, using: NWParameters(passcode: "GameMasterCode"))
    }
}

extension NWParameters {
    // Create parameters for use in PeerConnection and PeerListener.
    convenience init(passcode: String) {
        // Customize TCP options to enable keepalives.
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 2

        // Create parameters with custom TLS and TCP options.
        self.init(tls: NWParameters.tlsOptions(passcode: passcode), tcp: tcpOptions)

        // Enable using a peer-to-peer link.
        includePeerToPeer = true

        // Add your custom game protocol to support game messages.
        let gameOptions = NWProtocolFramer.Options(definition: GameProtocol.definition)
        defaultProtocolStack.applicationProtocols.insert(gameOptions, at: 0)
    }

    // Create TLS options using a passcode to derive a pre-shared key.
    private static func tlsOptions(passcode: String) -> NWProtocolTLS.Options {
        let tlsOptions = NWProtocolTLS.Options()

        let authenticationKey = SymmetricKey(data: passcode.data(using: .utf8)!)
        var authenticationCode = HMAC<SHA256>.authenticationCode(for: "GameMaster".data(using: .utf8)!, using: authenticationKey)

        let authenticationDispatchData = withUnsafeBytes(of: &authenticationCode) { (ptr: UnsafeRawBufferPointer) in
            DispatchData(bytes: ptr)
        }

        sec_protocol_options_add_pre_shared_key(tlsOptions.securityProtocolOptions,
                                                authenticationDispatchData as __DispatchData,
                                                stringToDispatchData("GameMaster")! as __DispatchData)
        sec_protocol_options_append_tls_ciphersuite(tlsOptions.securityProtocolOptions,
                                                    tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
        return tlsOptions
    }

    // Create a utility function to encode strings as pre-shared key data.
    private static func stringToDispatchData(_ string: String) -> DispatchData? {
        guard let stringData = string.data(using: .unicode) else {
            return nil
        }
        let dispatchData = withUnsafeBytes(of: stringData) { (ptr: UnsafeRawBufferPointer) in
            DispatchData(bytes: UnsafeRawBufferPointer(start: ptr.baseAddress, count: stringData.count))
        }
        return dispatchData
    }
}
