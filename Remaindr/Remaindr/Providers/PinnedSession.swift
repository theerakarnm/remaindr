import CryptoKit
import Foundation

/// A URLSession whose server trust must match a pinned certificate hash.
///
/// Fail-closed certificate pinning for the three hosts this app sends
/// credentials to. A host with no pins, or whose chain contains neither a
/// pinned leaf nor a pinned issuing CA, cancels the challenge rather than
/// falling back to system trust, so a rogue or intercepted CA cannot harvest
/// a key. Pins are base64 SHA-256 over the whole DER certificate.
///
/// Refreshing the pins: capture the new chains with
///   echo | openssl s_client -connect <host>:443 -servername <host> -showcerts
/// save each PEM block to its own file, then hash it with
///   openssl x509 -outform DER -in cert.pem | openssl dgst -sha256 -binary | base64
/// and replace the leaf entry; keep the CA entry when the CA is unchanged.
enum PinnedSession {
    /// Base64 SHA-256 of each host's leaf and issuing CA certificates,
    /// captured 2026-08-17.
    static let pins: [String: [String]] = [
        "api.anthropic.com": [
            "oKzenjNbvk+BU+TLrWMnzeW09tkHzoj5mUZzgYrlPjg=", // leaf CN=api.anthropic.com
            "HfwWBfutNY2LyET3bRUgP6ycpcGnn9SFf/ryhk++v5Y=", // CA Google Trust Services WE1
        ],
        "api.z.ai": [
            "vCXiRElVzr29slyOBUtRUb0N3KrSPNNjWEEgfEHoUHA=", // leaf CN=*.z.ai
            "jFTDNLZrpOQmdyr0o/kTbBmhrscp/bKMU1wHpaTvIuA=", // CA Sectigo Public Server Authentication CA DV R36
        ],
        "api.deepseek.com": [
            "CxEkdgkFfa14FpGFLwGuLqUsnEfNYykPMvhculJbR10=", // leaf CN=*.deepseek.com
            "Uzjr7I+yrGCZYSbT52qjT9DzMYrHjrt6yPbxNh9ISzM=", // CA Amazon RSA 2048 M01
        ],
    ]

    /// The one session every provider client uses.
    static let shared: URLSession = {
        let configuration = URLSessionConfiguration.default
        return URLSession(configuration: configuration, delegate: Delegate(), delegateQueue: nil)
    }()

    /// Base64 SHA-256 over a certificate's DER encoding.
    static func certificateHash(_ certificate: SecCertificate) -> String {
        let der = SecCertificateCopyData(certificate) as Data
        return Data(SHA256.hash(data: der)).base64EncodedString()
    }

    /// The delegate that enforces the pins. Injectable pins exist so a
    /// harness can prove the fail-closed path without touching production.
    final class Delegate: NSObject, URLSessionDelegate, @unchecked Sendable {
        private let pins: [String: [String]]

        init(pins: [String: [String]] = PinnedSession.pins) {
            self.pins = pins
        }

        func urlSession(_ session: URLSession,
                        didReceive challenge: URLAuthenticationChallenge) async
            -> (URLSession.AuthChallengeDisposition, URLCredential?) {
            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  let trust = challenge.protectionSpace.serverTrust else {
                return (.performDefaultHandling, nil)
            }
            let host = challenge.protectionSpace.host
            guard let hostPins = pins[host], !hostPins.isEmpty,
                  let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else {
                return (.cancelAuthenticationChallenge, nil)
            }
            let hashes = Set(chain.map(PinnedSession.certificateHash))
            guard !Set(hostPins).isDisjoint(with: hashes) else {
                return (.cancelAuthenticationChallenge, nil)
            }
            var error: CFError?
            guard SecTrustEvaluateWithError(trust, &error) else {
                return (.cancelAuthenticationChallenge, nil)
            }
            return (.useCredential, URLCredential(trust: trust))
        }
    }
}
