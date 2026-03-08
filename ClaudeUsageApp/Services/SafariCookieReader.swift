import Foundation

/// Reads cookies from Safari's binary cookie store (non-sandboxed apps only)
enum SafariCookieReader {

    static func findSessionKey() -> String? {
        let cookiePath = NSHomeDirectory() + "/Library/Cookies/Cookies.binarycookies"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: cookiePath)) else {
            print("[CookieReader] Could not read Cookies.binarycookies")
            return nil
        }
        print("[CookieReader] Read \(data.count) bytes from cookie store")

        let cookies = parseBinaryCookies(data)
        print("[CookieReader] Parsed \(cookies.count) cookies total")

        // Find sessionKey for claude.ai
        let match = cookies.first { cookie in
            cookie.name == "sessionKey"
                && cookie.domain.contains("claude.ai")
                && cookie.value.hasPrefix("sk-ant-sid")
        }

        if let match {
            print("[CookieReader] Found sessionKey cookie, length: \(match.value.count)")
        } else {
            // Log claude.ai cookies for debugging
            let claudeCookies = cookies.filter { $0.domain.contains("claude") }
            print("[CookieReader] No sessionKey found. Claude cookies: \(claudeCookies.map { "\($0.name)@\($0.domain)" })")
        }

        return match?.value
    }

    // MARK: - Binary Cookies Parser

    private struct ParsedCookie {
        let name: String
        let value: String
        let domain: String
        let path: String
    }

    private static func parseBinaryCookies(_ data: Data) -> [ParsedCookie] {
        var cookies: [ParsedCookie] = []
        guard data.count > 8 else { return cookies }

        // Magic: "cook"
        let magic = String(data: data[0..<4], encoding: .ascii)
        guard magic == "cook" else {
            print("[CookieReader] Invalid magic: \(magic ?? "nil")")
            return cookies
        }

        // Number of pages (big-endian)
        let numPages = data.readUInt32BE(at: 4)

        // Page sizes
        var pageSizes: [Int] = []
        for i in 0..<Int(numPages) {
            let size = data.readUInt32BE(at: 8 + i * 4)
            pageSizes.append(Int(size))
        }

        // Parse each page
        var pageOffset = 8 + Int(numPages) * 4
        for pageSize in pageSizes {
            let pageEnd = pageOffset + pageSize
            guard pageEnd <= data.count else { break }
            let pageData = data[pageOffset..<pageEnd]
            cookies.append(contentsOf: parsePage(Data(pageData)))
            pageOffset = pageEnd
        }

        return cookies
    }

    private static func parsePage(_ page: Data) -> [ParsedCookie] {
        var cookies: [ParsedCookie] = []
        guard page.count > 8 else { return cookies }

        // Page header (should be 0x00000100)
        // Number of cookies (little-endian, offset 4)
        let numCookies = page.readUInt32LE(at: 4)

        // Cookie offsets
        var cookieOffsets: [Int] = []
        for i in 0..<Int(numCookies) {
            let offset = page.readUInt32LE(at: 8 + i * 4)
            cookieOffsets.append(Int(offset))
        }

        for offset in cookieOffsets {
            if let cookie = parseCookie(page, at: offset) {
                cookies.append(cookie)
            }
        }

        return cookies
    }

    private static func parseCookie(_ page: Data, at offset: Int) -> ParsedCookie? {
        guard offset + 44 <= page.count else { return nil }

        // Cookie structure (all little-endian):
        // 0: size (4)
        // 4: flags (4)
        // 8: unknown (4)
        // 12: urlOffset (4)
        // 16: nameOffset (4)
        // 20: pathOffset (4)
        // 24: valueOffset (4)
        // 28: comment (8)
        // 36: expiry (8) - Mac absolute time (double)
        // 44: creation (8) - Mac absolute time (double)

        let urlOffset = Int(page.readUInt32LE(at: offset + 16))
        let nameOffset = Int(page.readUInt32LE(at: offset + 20))
        let pathOffset = Int(page.readUInt32LE(at: offset + 24))
        let valueOffset = Int(page.readUInt32LE(at: offset + 28))

        let domain = page.readNullTerminatedString(at: offset + urlOffset)
        let name = page.readNullTerminatedString(at: offset + nameOffset)
        let path = page.readNullTerminatedString(at: offset + pathOffset)
        let value = page.readNullTerminatedString(at: offset + valueOffset)

        return ParsedCookie(name: name, value: value, domain: domain, path: path)
    }
}

// MARK: - Data helpers

private extension Data {
    func readUInt32BE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return withUnsafeBytes { buf in
            let p = buf.baseAddress!.advanced(by: offset).assumingMemoryBound(to: UInt32.self)
            return UInt32(bigEndian: p.pointee)
        }
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return withUnsafeBytes { buf in
            let p = buf.baseAddress!.advanced(by: offset).assumingMemoryBound(to: UInt32.self)
            return UInt32(littleEndian: p.pointee)
        }
    }

    func readNullTerminatedString(at offset: Int) -> String {
        guard offset < count else { return "" }
        var end = offset
        return withUnsafeBytes { buf in
            let bytes = buf.bindMemory(to: UInt8.self)
            while end < count && bytes[end] != 0 { end += 1 }
            guard let str = String(bytes: bytes[offset..<end], encoding: .utf8) else { return "" }
            return str
        }
    }
}
