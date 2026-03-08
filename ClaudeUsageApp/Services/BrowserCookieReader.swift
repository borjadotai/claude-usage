import Foundation
import Security
import CommonCrypto
import SQLite3

/// Reads cookies from Chrome (priority) then Safari as fallback
enum BrowserCookieReader {

    static func findSessionKey() -> String? {
        // Try Chrome first
        if let key = readFromChrome() {
            print("[CookieReader] Found sessionKey in Chrome")
            return key
        }

        // Fallback to Safari
        if let key = readFromSafari() {
            print("[CookieReader] Found sessionKey in Safari")
            return key
        }

        print("[CookieReader] No sessionKey found in any browser")
        return nil
    }

    // MARK: - Chrome

    private static func readFromChrome() -> String? {
        let dbPath = NSHomeDirectory() + "/Library/Application Support/Google/Chrome/Default/Cookies"
        guard FileManager.default.fileExists(atPath: dbPath) else {
            print("[CookieReader] Chrome cookie DB not found")
            return nil
        }

        // Chrome encrypts cookie values with a key from Keychain
        guard let decryptionKey = chromeDecryptionKey() else {
            print("[CookieReader] Could not get Chrome decryption key")
            return nil
        }

        // Copy DB to temp (Chrome may have it locked)
        let tmpPath = NSTemporaryDirectory() + "claude_cookies_\(ProcessInfo.processInfo.processIdentifier).db"
        try? FileManager.default.removeItem(atPath: tmpPath)
        do {
            try FileManager.default.copyItem(atPath: dbPath, toPath: tmpPath)
        } catch {
            print("[CookieReader] Could not copy Chrome DB: \(error)")
            return nil
        }
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        // Use SQLite C API directly (more reliable than shelling out to sqlite3)
        var db: OpaquePointer?
        guard sqlite3_open_v2(tmpPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            print("[CookieReader] Could not open Chrome DB: \(String(cString: sqlite3_errmsg(db!)))")
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }

        let query = "SELECT encrypted_value FROM cookies WHERE host_key LIKE '%claude.ai%' AND name = 'sessionKey' ORDER BY last_access_utc DESC LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            print("[CookieReader] SQL prepare failed: \(String(cString: sqlite3_errmsg(db!)))")
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            print("[CookieReader] No sessionKey row in Chrome DB")
            return nil
        }

        // Read encrypted_value as blob
        guard let blobPtr = sqlite3_column_blob(stmt, 0) else {
            print("[CookieReader] Chrome: encrypted_value is NULL")
            return nil
        }
        let blobSize = sqlite3_column_bytes(stmt, 0)
        let encryptedData = Data(bytes: blobPtr, count: Int(blobSize))
        print("[CookieReader] Chrome: got encrypted value, \(blobSize) bytes")

        // Chrome on macOS uses v10/v11 encryption: prefix + AES-128-CBC
        guard encryptedData.count > 3 else {
            print("[CookieReader] Chrome: encrypted data too short (\(encryptedData.count) bytes)")
            return nil
        }
        let prefix = String(data: encryptedData[0..<3], encoding: .ascii)
        print("[CookieReader] Chrome: encryption prefix=\(prefix ?? "nil")")

        if prefix == "v10" || prefix == "v11" {
            let encrypted = encryptedData[3...]
            let result = decryptChromeCookie(Data(encrypted), key: decryptionKey)
            if let result {
                print("[CookieReader] Chrome: decryption succeeded, value length=\(result.count)")
            } else {
                print("[CookieReader] Chrome: decryption returned nil")
            }
            return result
        }

        // Unencrypted fallback
        return String(data: encryptedData, encoding: .utf8)
    }

    private static func chromeDecryptionKey() -> Data? {
        // Use the `security` CLI to read Chrome's encryption key from Keychain.
        // This handles Keychain ACLs better than SecItemCopyMatching from a non-Chrome app.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Chrome Safe Storage", "-a", "Chrome", "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            print("[CookieReader] Could not run security command: \(error)")
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            print("[CookieReader] security command failed with status \(process.terminationStatus)")
            return nil
        }
        let password = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !password.isEmpty else {
            print("[CookieReader] Empty password from Keychain")
            return nil
        }
        print("[CookieReader] Chrome keychain password length: \(password.count)")
        return deriveKey(password: password)
    }

    private static func deriveKey(password: String) -> Data? {
        let salt = "saltysalt".data(using: .utf8)!
        let iterations: UInt32 = 1003
        let keyLength = 16
        var derivedKey = Data(count: keyLength)

        let result = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            password.data(using: .utf8)!.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress!.assumingMemoryBound(to: Int8.self),
                        password.utf8.count,
                        saltBytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        iterations,
                        derivedKeyBytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }
        return result == kCCSuccess ? derivedKey : nil
    }

    private static func decryptChromeCookie(_ encrypted: Data, key: Data) -> String? {
        // AES-128-CBC with 16-byte IV of spaces (0x20)
        let iv = Data(repeating: 0x20, count: 16)
        let bufferSize = encrypted.count + kCCBlockSizeAES128
        var decryptedData = Data(count: bufferSize)
        var numBytesDecrypted: size_t = 0

        let status = decryptedData.withUnsafeMutableBytes { decryptedBytes in
            encrypted.withUnsafeBytes { encryptedBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES128),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, key.count,
                            ivBytes.baseAddress,
                            encryptedBytes.baseAddress, encrypted.count,
                            decryptedBytes.baseAddress, bufferSize,
                            &numBytesDecrypted
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            print("[CookieReader] AES decrypt failed with status: \(status)")
            return nil
        }

        let decrypted = decryptedData.prefix(numBytesDecrypted)
        print("[CookieReader] AES decrypt OK, \(numBytesDecrypted) bytes decrypted")

        // Chrome's AES-CBC produces garbage bytes before the actual cookie value
        // (first block corruption). Scan raw bytes for the "sk-ant-sid" pattern
        // since the garbage bytes are > 127 and break ASCII/UTF-8 encoding.
        let marker = Array("sk-ant-sid".utf8)
        let bytes = Array(decrypted)
        for i in 0...(bytes.count - marker.count) {
            if bytes[i..<(i + marker.count)].elementsEqual(marker) {
                let valueBytes = Array(bytes[i...])
                // Trim trailing padding/control chars
                let trimmed = valueBytes.prefix(while: { $0 >= 0x20 && $0 < 0x7F })
                if let value = String(bytes: trimmed, encoding: .utf8) {
                    return value
                }
            }
        }

        // Fallback: try full string decode
        if let str = String(data: decrypted, encoding: .utf8) {
            return str
        }
        print("[CookieReader] Could not find sk-ant-sid in decrypted data")
        return nil
    }

    // MARK: - Safari

    private static func readFromSafari() -> String? {
        return SafariCookieReader.findSessionKey()
    }
}

// MARK: - Helpers

private extension Data {
    init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}
