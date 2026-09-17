import Foundation
import Security

/// Host HTTP 的唯一 `URLSession` 入口。
///
/// Release 走系统信任；Debug 在系统信任失败时，仅对 `*.eduskit.com` 上
/// mkcert 签发的本地开发证书放行。Vendor SDK（OpenIM / DrawsKit）仍需把
/// mkcert CA 装进模拟器钥匙串，见 `scripts/trust-mkcert-ios-simulator.sh`。
enum HostHttpSession {
    private enum Tokens {
        static let mkcertIssuerMarker = "mkcert"
        static let localDevApexHost = "eduskit.com"
        static let localDevHostSuffix = ".eduskit.com"
        static let printableAsciiMin: UInt8 = 32
        static let printableAsciiMax: UInt8 = 126
    }

    static let shared: URLSession = {
        #if DEBUG
        return URLSession(
            configuration: .default,
            delegate: LocalDevServerTrustDelegate.shared,
            delegateQueue: nil
        )
        #else
        return .shared
        #endif
    }()

    static func isLocalDevHost(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == Tokens.localDevApexHost
            || normalized.hasSuffix(Tokens.localDevHostSuffix)
    }

    static func issuerContainsMkcert(_ issuerText: String) -> Bool {
        issuerText.range(of: Tokens.mkcertIssuerMarker, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    static func allowsLocalDevFallback(host: String, issuerText: String) -> Bool {
        isLocalDevHost(host) && issuerContainsMkcert(issuerText)
    }

    /// iOS 没有 macOS 的 `SecCertificateCopyValues`，从 issuer DER / 整证 DER 抽可打印文本。
    static func issuerText(from certificate: SecCertificate) -> String {
        var chunks: [String] = []
        if let issuer = SecCertificateCopyNormalizedIssuerSequence(certificate) {
            chunks.append(printableAscii(from: issuer as Data))
        }
        chunks.append(printableAscii(from: SecCertificateCopyData(certificate) as Data))
        return chunks.joined(separator: " ")
    }

    static func printableAscii(from data: Data) -> String {
        let bytes = data.filter { $0 >= Tokens.printableAsciiMin && $0 <= Tokens.printableAsciiMax }
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }

    static func trustIdentityText(_ trust: SecTrust) -> String {
        certificates(in: trust).map { certificate in
            let subject = (SecCertificateCopySubjectSummary(certificate) as String?) ?? ""
            return subject + " " + issuerText(from: certificate)
        }.joined(separator: " ")
    }

    static func certificates(in trust: SecTrust) -> [SecCertificate] {
        if #available(iOS 15.0, macOS 12.0, *) {
            return (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
        }
        let count = SecTrustGetCertificateCount(trust)
        return (0..<count).compactMap { SecTrustGetCertificateAtIndex(trust, $0) }
    }
}

#if DEBUG
private final class LocalDevServerTrustDelegate: NSObject, URLSessionDelegate {
    static let shared = LocalDevServerTrustDelegate()

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        if SecTrustEvaluateWithError(trust, nil) {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        let host = challenge.protectionSpace.host
        let issuerText = HostHttpSession.trustIdentityText(trust)
        if HostHttpSession.allowsLocalDevFallback(host: host, issuerText: issuerText) {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }
}
#endif
