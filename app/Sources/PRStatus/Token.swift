import Foundation
import PRCore
import Security

/// GitHub token: the Keychain entry set in Settings, else the token of the GitHub CLI.
enum Token {
    private static let service = "PRStatus"
    private static let account = "github-token"
    private static let ghPaths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]

    @MainActor private static var cachedGh: String?

    @MainActor
    static func resolve() async throws -> String {
        if let token = keychain(), !token.isEmpty { return token }
        if let cachedGh { return cachedGh }
        if let token = await fromGhCLI() {
            cachedGh = token
            return token
        }
        throw GitHubError.noToken
    }

    /// Drops the cached gh token after GitHub rejected it, so the next refresh asks gh again.
    @MainActor
    static func forgetCached() {
        cachedGh = nil
    }

    static func keychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static var hasKeychainToken: Bool { keychain()?.isEmpty == false }

    /// Stores the token; an empty token removes it.
    static func save(_ token: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(trimmed.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func fromGhCLI() async -> String? {
        for path in ghPaths where FileManager.default.isExecutableFile(atPath: path) {
            if let token = await run(path, ["auth", "token"]), !token.isEmpty { return token }
        }
        return nil
    }

    private static func run(_ path: String, _ args: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { p in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: p.terminationStatus == 0 ? text : nil)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
                return
            }
            // a gh waiting on the keychain must not hang the refresh
            DispatchQueue.global().asyncAfter(deadline: .now() + 15) {
                if process.isRunning { process.terminate() }
            }
        }
    }
}
