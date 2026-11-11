import Foundation

/// Loads and resolves runtime configuration and secrets from `.env` and process environment variables.
/// Ensures no personal hostnames, usernames, endpoints, or API keys are hardcoded in source files.
public struct EnvConfig: Sendable {
    public static let shared = EnvConfig()

    private let values: [String: String]

    public init(dotenvPath: String? = nil, processEnv: [String: String] = ProcessInfo.processInfo.environment) {
        var merged = Self.loadDotEnv(at: dotenvPath)
        for (k, v) in processEnv {
            merged[k] = v
        }
        self.values = merged
    }

    public func string(_ key: String, default defaultValue: String = "") -> String {
        guard let raw = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return defaultValue
        }
        return raw
    }

    public func int(_ key: String, default defaultValue: Int) -> Int {
        guard let raw = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              let parsed = Int(raw) else {
            return defaultValue
        }
        return parsed
    }

    public func bool(_ key: String, default defaultValue: Bool) -> Bool {
        guard let raw = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else {
            return defaultValue
        }
        return raw == "1" || raw == "true" || raw == "yes" || raw == "on"
    }

    // MARK: - Typed Configuration Properties

    public var prometheusHost: String {
        string("PULSEMATRIX_PROMETHEUS_HOST", default: "127.0.0.1")
    }

    public var prometheusPort: UInt16 {
        let p = int("PULSEMATRIX_PROMETHEUS_PORT", default: 9101)
        return UInt16(clamping: max(1024, min(65535, p)))
    }

    public var metricsAPIKey: String? {
        let key = string("PULSEMATRIX_METRICS_API_KEY")
        return key.isEmpty ? nil : key
    }

    public var alertWebhookURL: String? {
        let url = string("PULSEMATRIX_WEBHOOK_URL")
        return url.isEmpty ? nil : url
    }

    public var anonymizeHostAndUser: Bool {
        bool("PULSEMATRIX_ANONYMIZE_HOST", default: false)
    }

    public var redactedHostLabel: String {
        string("PULSEMATRIX_REDACTED_HOST_LABEL", default: "mac-workstation.local")
    }

    public var redactedUserLabel: String {
        string("PULSEMATRIX_REDACTED_USER_LABEL", default: "developer")
    }

    public func sanitizeHostname(_ rawHostname: String) -> String {
        anonymizeHostAndUser ? redactedHostLabel : rawHostname
    }

    public func sanitizeUsername(_ rawUser: String) -> String {
        guard anonymizeHostAndUser else { return rawUser }
        if rawUser.hasPrefix("_") || rawUser == "root" {
            return rawUser
        }
        return redactedUserLabel
    }

    // MARK: - .env File Parser

    public static func parseDotEnvContents(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let normalized: String
            if trimmed.hasPrefix("export ") {
                normalized = String(trimmed.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
            } else {
                normalized = trimmed
            }

            guard let eqIdx = normalized.firstIndex(of: "=") else { continue }
            let key = String(normalized[..<eqIdx]).trimmingCharacters(in: .whitespaces)
            var value = String(normalized[normalized.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)

            if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                if value.count >= 2 {
                    value = String(value.dropFirst().dropLast())
                }
            }
            if !key.isEmpty {
                result[key] = value
            }
        }
        return result
    }

    private static func loadDotEnv(at explicitPath: String?) -> [String: String] {
        let candidatePaths: [String]
        if let explicitPath {
            candidatePaths = [explicitPath]
        } else {
            let cwd = FileManager.default.currentDirectoryPath
            let execDir = Bundle.main.bundleURL.deletingLastPathComponent().path
            candidatePaths = [
                "\(cwd)/.env",
                "\(execDir)/.env"
            ]
        }

        for path in candidatePaths {
            if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
                return parseDotEnvContents(contents)
            }
        }
        return [:]
    }
}
