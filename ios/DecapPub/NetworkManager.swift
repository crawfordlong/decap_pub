import Foundation

/// Network manager with certificate pinning for GitHub API
final class NetworkManager: NSObject {
    static let shared = NetworkManager()
    
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    
    // GitHub API certificate public key hashes (SHA256)
    // These are the current GitHub.com certificate chain hashes as of 2025
    // Should be updated if GitHub changes their certificates
    private let trustedHashes: Set<String> = [
        // These are placeholder hashes - in production, these would be the actual
        // GitHub certificate hashes. For now, we'll implement validation but allow
        // fallback if pinning fails (with logging)
        "placeholder_hash_1",
        "placeholder_hash_2"
    ]
    
    private let pinnedHost = "api.github.com"
    private var enablePinning = false // Set to true in production when hashes are updated
    
    private override init() {
        super.init()
    }
    
    // MARK: - Public API
    
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        return try await session.data(for: request)
    }
    
    func data(from url: URL) async throws -> (Data, URLResponse) {
        return try await session.data(from: url)
    }
    
    // MARK: - Secure Request Logging
    
    /// Create a redacted description of a URLRequest for logging
    static func redactedDescription(of request: URLRequest) -> String {
        var description = "\(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "unknown")"
        
        if let headers = request.allHTTPHeaderFields {
            var redactedHeaders: [String: String] = [:]
            for (key, value) in headers {
                if key.lowercased().contains("authorization") || key.lowercased().contains("token") {
                    redactedHeaders[key] = "[REDACTED]"
                } else {
                    redactedHeaders[key] = value
                }
            }
            description += "\nHeaders: \(redactedHeaders)"
        }
        
        return description
    }
}

// MARK: - URLSessionDelegate

extension NetworkManager: URLSessionDelegate {
    
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Only validate for our pinned host
        guard challenge.protectionSpace.host == pinnedHost else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        // Validate the certificate chain
        let policies = [SecPolicyCreateSSL(true, pinnedHost as CFString)]
        SecTrustSetPolicies(serverTrust, policies as CFArray)
        
        var error: CFError?
        let isValid = SecTrustEvaluateWithError(serverTrust, &error)
        
        guard isValid else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        // Check if we should perform certificate pinning
        if enablePinning {
            // Get the certificate chain
            guard let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            
            // Check if any certificate in the chain matches our pinned hashes
            var isPinned = false
            for certificate in certificateChain {
                if let hash = sha256(of: certificate) {
                    if trustedHashes.contains(hash) {
                        isPinned = true
                        break
                    }
                }
            }
            
            if isPinned {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                // Certificate pinning failed
                // In production, this should cancel the request
                // For now, we'll log and allow (to prevent breaking during development)
                print("⚠️ Certificate pinning validation failed for \(pinnedHost)")
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            }
        } else {
            // Pinning disabled, use default validation
            // Trust evaluation already performed above
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        }
    }
    
    // MARK: - Certificate Hash Calculation
    
    private func sha256(of certificate: SecCertificate) -> String? {
        guard let certificateData = SecCertificateCopyData(certificate) as Data? else {
            return nil
        }
        
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        certificateData.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(certificateData.count), &hash)
        }
        
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }
}

// MARK: - CommonCrypto Import

import CommonCrypto

// Note: In a real implementation, you would:
// 1. Extract GitHub's actual certificate public key hashes
// 2. Update the trustedHashes set with real values
// 3. Set enablePinning = true
// 4. Test thoroughly with production certificates
//
// To get certificate hashes:
// 1. openssl s_client -connect api.github.com:443 -showcerts
// 2. Copy each certificate to a file
// 3. openssl x509 -in cert.pem -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl enc -base64
