// @copyright André Trettin

import CryptoKit
import Foundation
import Network

/// The LAN game transport: the `GameProtocol` framer over TLS-PSK over TCP, on the structured
/// Network API. See CODE_AUDIT_19 §4.2.
typealias GameConnection = NetworkConnection<Framer<GameProtocol>>
typealias GameListener = NetworkListener<Framer<GameProtocol>>

enum GameNetworkParameters {
    /// The declarative `TLS` builder has no pre-shared-key option, so TLS-PSK comes from the
    /// initial `NWParameters(passcode:)` and the builder only adds the framer over TCP. Declaring
    /// `TLS` in the builder as well stacks a second TLS layer and every handshake fails.
    static func builder(passcode: String) -> NWParametersBuilder<Framer<GameProtocol>> {
        .parameters(initialParameters: NWParameters(passcode: passcode)) {
            Framer(using: GameProtocol.self) {
                TCP().keepalive(idleTimeInSeconds: keepaliveIdle, count: keepaliveCount, intervalInSeconds: keepaliveInterval)
            }
        }
    }

    // A probe every 2 s of idleness kept the radio busy on every idle session; probe after
    // 15 s and give up after 3 unanswered probes 5 s apart (~30 s to notice a dead peer,
    // instead of the OS default retry schedule). See CODE_AUDIT_Join §7.1.
    static let keepaliveIdle: UInt32 = 15
    static let keepaliveInterval: UInt32 = 5
    static let keepaliveCount: UInt32 = 3
}

extension GameConnection {
    static func game(to endpoint: NWEndpoint, passcode: String) -> GameConnection {
        GameConnection(to: endpoint, using: GameNetworkParameters.builder(passcode: passcode))
    }
}

extension NWParameters {
    /// A one-hex-digit check value of `passcode` plus its length, for debug logs: two devices whose
    /// values differ certainly use different codes, while the value (4 bits) does not reveal the
    /// code. Used to tell a code mismatch from a transport problem when a handshake fails with
    /// `bad MAC`.
    static func passcodeCheck(_ passcode: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data("check".utf8), using: SymmetricKey(data: Data(passcode.utf8)))
        let nibble = Array(mac).first.map { $0 & 0x0F } ?? 0
        return "len \(passcode.count) check \(String(nibble, radix: 16))"
    }

    // The TLS-PSK and TCP base of `GameNetworkParameters.builder(passcode:)`, which adds the
    // `GameProtocol` framer on top.
    convenience init(passcode: String) {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = Int(GameNetworkParameters.keepaliveIdle)
        tcpOptions.keepaliveInterval = Int(GameNetworkParameters.keepaliveInterval)
        tcpOptions.keepaliveCount = Int(GameNetworkParameters.keepaliveCount)

        // Create parameters with custom TLS and TCP options.
        self.init(tls: NWParameters.tlsOptions(passcode: passcode), tcp: tcpOptions)

        // Enable using a peer-to-peer link.
        includePeerToPeer = true
    }

    // Create TLS options using a passcode to derive a pre-shared key.
    //
    // ACCEPTED RISK — CODE_AUDIT_17 §6.6, decided won't fix: the constant PSK identity and the
    // 4-digit code are knowingly kept. Only app users can complete this handshake and send valid
    // game messages, and a stranger on a public Wi-Fi gets a single attempt at most (online
    // guessing is throttled by `ConnectionAttemptThrottle`), so offline brute force is not a
    // realistic threat for a local-network tabletop game. Do not raise as a finding again.
    private static func tlsOptions(passcode: String) -> NWProtocolTLS.Options {
        let tlsOptions = NWProtocolTLS.Options()

        // `Data(someString.utf8)` builds directly from the always-present UTF-8
        // view instead of the optional-returning, force-unwrapped
        // `.data(using: .utf8)!` — a Swift `String`'s UTF-8 encoding can't
        // actually fail, so this is the same bytes with no force-unwrap.
        let authenticationKey = SymmetricKey(data: Data(passcode.utf8))
        var authenticationCode = HMAC<SHA256>.authenticationCode(for: Data("GameMaster".utf8), using: authenticationKey)

        let authenticationDispatchData = withUnsafeBytes(of: &authenticationCode) { (ptr: UnsafeRawBufferPointer) in
            DispatchData(bytes: ptr)
        }

        // Both values below are derived from hardcoded constants, not
        // attacker-controlled input, so neither guard is expected to ever
        // fail in practice — but this connection-establishing security path
        // shouldn't force-unwrap even a constant, matching the discipline
        // already applied to `passcode` above. A guard failure here leaves
        // the PSK identity/ciphersuite unset, which fails the handshake
        // cleanly and visibly instead of crashing the app or silently
        // downgrading security. See CODE_AUDIT §5.3.
        guard let pskIdentity = stringToDispatchData("GameMaster") else {
            assertionFailure("stringToDispatchData(\"GameMaster\") unexpectedly failed to encode a constant string")
            return tlsOptions
        }
        guard let cipherSuite = tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256)) else {
            assertionFailure("TLS_PSK_WITH_AES_128_GCM_SHA256 unexpectedly failed to convert to tls_ciphersuite_t")
            return tlsOptions
        }

        sec_protocol_options_add_pre_shared_key(tlsOptions.securityProtocolOptions,
                                                authenticationDispatchData as __DispatchData,
                                                pskIdentity as __DispatchData)
        sec_protocol_options_append_tls_ciphersuite(tlsOptions.securityProtocolOptions,
                                                    cipherSuite)
        return tlsOptions
    }

    // Create a utility function to encode strings as pre-shared key data.
    //
    // UTF-8, not UTF-16 (`.unicode`): UTF-16 encodes ASCII with NUL bytes and a BOM, and the TLS
    // stack compares a received PSK identity as a C string, so "GameMaster" as UTF-16 was cut at
    // its first NUL and never matched the configured identity — every handshake, even with the
    // right code, failed with "unknown PSK identity" (-9864). Also the bytes of the string's data,
    // not of the `Data` value itself (CODE_AUDIT_15 §6.2). See CODE_AUDIT_Join.
    private static func stringToDispatchData(_ string: String) -> DispatchData? {
        Data(string.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
    }
}
