import Foundation

public enum CurlParseError: Error, Equatable, LocalizedError {
    case notACurlCommand
    case unterminatedQuote
    case missingURL
    case missingValue(String)

    public var errorDescription: String? {
        switch self {
        case .notACurlCommand: "The text doesn't start with `curl`."
        case .unterminatedQuote: "The command has an unterminated quote."
        case .missingURL: "No URL was found in the command."
        case .missingValue(let flag): "The option \(flag) is missing its value."
        }
    }
}

public enum CurlParser {
    public static func looksLikeCurl(_ text: String) -> Bool {
        var trimmed = text.trimmed
        if trimmed.hasPrefix("$ ") { trimmed = String(trimmed.dropFirst(2)) }
        return trimmed.lowercased().hasPrefix("curl ")
    }

    // Short flags that take a value and may have it attached, e.g. -XPOST.
    private static let shortWithValue: Set<String> = [
        "-X", "-H", "-d", "-u", "-b", "-A", "-e", "-F", "-o", "-m", "-x", "-E",
        "-w", "-T", "-r", "-c", "-K", "-y", "-Y", "-U", "-z", "-Q", "-P", "-t",
    ]

    // Options whose value we consume but don't use.
    private static let ignoredWithValue: Set<String> = [
        "-o", "--output", "-m", "--max-time", "--connect-timeout", "-x", "--proxy",
        "--cacert", "--capath", "--cert", "-E", "--key", "-w", "--write-out", "--retry",
        "--retry-delay", "--retry-max-time", "-T", "--upload-file", "-r", "--range",
        "--resolve", "-c", "--cookie-jar", "-K", "--config", "--limit-rate", "-y",
        "--speed-time", "-Y", "--speed-limit", "-U", "--proxy-user", "--interface",
        "--dns-servers", "--max-redirs", "--trace", "--trace-ascii", "--stderr",
        "--cert-type", "--key-type", "--pass", "--ciphers", "--local-port", "-z",
        "--time-cond", "-Q", "--quote", "--max-filesize", "--unix-socket",
        "--abstract-unix-socket", "--connect-to", "--noproxy", "--preproxy",
        "--proxy-header", "--request-target", "-P", "--ftp-port", "-t", "--telnet-option",
        "--tls-max", "--variable", "--expect100-timeout", "--keepalive-time",
    ]

    public static func parse(_ command: String) throws -> RequestSpec {
        var tokens = try tokenize(command)
        if tokens.first == "$" { tokens.removeFirst() }
        guard let first = tokens.first, first.lowercased() == "curl" || first.hasSuffix("/curl") else {
            throw CurlParseError.notACurlCommand
        }
        let args = Array(tokens.dropFirst())

        var method: String?
        var url: String?
        var headers: [KeyValue] = []
        var dataParts: [String] = []
        var formParts: [KeyValue] = []
        var urlQueryParts: [String] = []
        var forceGet = false
        var jsonFlag = false

        var index = 0
        func takeValue(_ flag: String, inline: String?) throws -> String {
            if let inline { return inline }
            index += 1
            guard index < args.count else { throw CurlParseError.missingValue(flag) }
            return args[index]
        }

        while index < args.count {
            var flag = args[index]
            var inline: String?
            if flag.hasPrefix("-"), !flag.hasPrefix("--"), flag.count > 2 {
                let short = String(flag.prefix(2))
                if shortWithValue.contains(short) {
                    inline = String(flag.dropFirst(2))
                    flag = short
                }
            }

            switch flag {
            case "-X", "--request":
                method = try takeValue(flag, inline: inline)
            case "-H", "--header":
                if let header = parseHeader(try takeValue(flag, inline: inline)) {
                    headers.append(header)
                }
            case "-d", "--data", "--data-raw", "--data-binary", "--data-ascii":
                dataParts.append(try takeValue(flag, inline: inline))
            case "--data-urlencode":
                dataParts.append(urlencodeData(try takeValue(flag, inline: inline)))
            case "--json":
                jsonFlag = true
                dataParts.append(try takeValue(flag, inline: inline))
            case "-F", "--form", "--form-string":
                let value = try takeValue(flag, inline: inline)
                if let eq = value.firstIndex(of: "=") {
                    formParts.append(KeyValue(String(value[..<eq]), String(value[value.index(after: eq)...])))
                }
            case "-u", "--user":
                let credentials = try takeValue(flag, inline: inline)
                headers.append(KeyValue("Authorization", "Basic " + Data(credentials.utf8).base64EncodedString()))
            case "--oauth2-bearer":
                headers.append(KeyValue("Authorization", "Bearer " + (try takeValue(flag, inline: inline))))
            case "-b", "--cookie":
                let cookie = try takeValue(flag, inline: inline)
                // Without `=` the value is a cookie file path, which we can't use.
                if cookie.contains("=") { headers.append(KeyValue("Cookie", cookie)) }
            case "-A", "--user-agent":
                headers.append(KeyValue("User-Agent", try takeValue(flag, inline: inline)))
            case "-e", "--referer":
                headers.append(KeyValue("Referer", try takeValue(flag, inline: inline)))
            case "--url":
                url = try takeValue(flag, inline: inline)
            case "--url-query":
                urlQueryParts.append(urlencodeData(try takeValue(flag, inline: inline)))
            case "-G", "--get":
                forceGet = true
            case "-I", "--head":
                method = "HEAD"
            default:
                if flag.hasPrefix("-"), flag.count > 1 {
                    if ignoredWithValue.contains(flag) { _ = try takeValue(flag, inline: inline) }
                    // Any other flag (--compressed, -k, -L, -s, -v, ...) is a no-op for us.
                } else if url == nil {
                    url = flag
                }
            }
            index += 1
        }

        guard var rawURL = url?.trimmed, !rawURL.isEmpty else { throw CurlParseError.missingURL }

        if forceGet, !dataParts.isEmpty {
            urlQueryParts.append(contentsOf: dataParts)
            dataParts = []
        }
        if !urlQueryParts.isEmpty {
            let (base, query, fragment) = URLQuery.split(rawURL)
            let combined = ([query].compactMap { $0 }.filter { !$0.isEmpty } + urlQueryParts).joined(separator: "&")
            rawURL = base + "?" + combined + (fragment.map { "#" + $0 } ?? "")
        }

        if jsonFlag {
            if !headers.contains(where: { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }) {
                headers.append(KeyValue("Content-Type", "application/json"))
            }
            if !headers.contains(where: { $0.key.caseInsensitiveCompare("Accept") == .orderedSame }) {
                headers.append(KeyValue("Accept", "application/json"))
            }
        }

        let hasBody = !dataParts.isEmpty || !formParts.isEmpty
        var spec = RequestSpec(
            method: HTTPMethod(rawValue: method ?? (forceGet || !hasBody ? "GET" : "POST")),
            headers: headers
        )
        spec.setURL(rawURL)

        if !formParts.isEmpty {
            // Multipart (-F) is approximated as url-encoded form fields.
            spec.bodyKind = .form
            spec.formFields = formParts
        } else if !dataParts.isEmpty {
            let data = dataParts.joined(separator: jsonFlag ? "" : "&")
            let contentType = headers
                .first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }?
                .value.lowercased()
            if let pretty = JSONFormatter.prettyPrinted(data), contentType.map({ $0.contains("json") }) ?? true {
                spec.bodyKind = .json
                spec.bodyText = pretty
            } else if contentType.map({ $0.contains("x-www-form-urlencoded") }) ?? true,
                      let fields = URLQuery.formFields(fromEncoded: data) {
                spec.bodyKind = .form
                spec.formFields = fields
            } else if contentType?.contains("json") == true {
                spec.bodyKind = .json
                spec.bodyText = data
            } else {
                spec.bodyKind = .text
                spec.bodyText = data
            }
        }
        return spec
    }

    private static func parseHeader(_ raw: String) -> KeyValue? {
        if let colon = raw.firstIndex(of: ":") {
            let key = raw[..<colon].trimmed
            guard !key.isEmpty else { return nil }
            return KeyValue(key, raw[raw.index(after: colon)...].trimmed)
        }
        // `-H "X-Empty;"` sends a header with an empty value.
        if raw.hasSuffix(";") {
            let key = String(raw.dropLast()).trimmed
            return key.isEmpty ? nil : KeyValue(key, "")
        }
        return nil
    }

    private static func urlencodeData(_ raw: String) -> String {
        guard let eq = raw.firstIndex(of: "=") else { return URLQuery.encode(raw) }
        let name = String(raw[..<eq])
        let content = URLQuery.encode(String(raw[raw.index(after: eq)...]))
        return name.isEmpty ? content : name + "=" + content
    }

    // MARK: - Shell tokenizer

    static func tokenize(_ input: String) throws -> [String] {
        let chars = Array(input)
        var tokens: [String] = []
        var current = ""
        var inToken = false
        var i = 0

        func finishToken() {
            if inToken { tokens.append(current) }
            current = ""
            inToken = false
        }

        func readHex(maxDigits: Int) -> Character? {
            var hex = ""
            while hex.count < maxDigits, i < chars.count, chars[i].isHexDigit {
                hex.append(chars[i])
                i += 1
            }
            guard let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) else { return nil }
            return Character(scalar)
        }

        while i < chars.count {
            let c = chars[i]
            if c == "'" {
                inToken = true
                i += 1
                while i < chars.count, chars[i] != "'" {
                    current.append(chars[i])
                    i += 1
                }
                guard i < chars.count else { throw CurlParseError.unterminatedQuote }
                i += 1
            } else if c == "\"" {
                inToken = true
                i += 1
                var closed = false
                while i < chars.count {
                    let d = chars[i]
                    if d == "\"" {
                        closed = true
                        i += 1
                        break
                    }
                    if d == "\\", i + 1 < chars.count {
                        let next = chars[i + 1]
                        if "\"\\$`".contains(next) {
                            current.append(next)
                            i += 2
                            continue
                        }
                        if next.isNewline {
                            i += 2
                            continue
                        }
                    }
                    current.append(d)
                    i += 1
                }
                guard closed else { throw CurlParseError.unterminatedQuote }
            } else if c == "$", i + 1 < chars.count, chars[i + 1] == "'" {
                // ANSI-C quoting: $'...' (used by Chrome's "Copy as cURL").
                inToken = true
                i += 2
                var closed = false
                while i < chars.count {
                    let d = chars[i]
                    if d == "'" {
                        closed = true
                        i += 1
                        break
                    }
                    guard d == "\\", i + 1 < chars.count else {
                        current.append(d)
                        i += 1
                        continue
                    }
                    let next = chars[i + 1]
                    i += 2
                    switch next {
                    case "n": current.append("\n")
                    case "t": current.append("\t")
                    case "r": current.append("\r")
                    case "e", "E": current.append("\u{1B}")
                    case "\\", "'", "\"", "?": current.append(next)
                    case "x": current.append(readHex(maxDigits: 2) ?? "x")
                    case "u": current.append(readHex(maxDigits: 4) ?? "u")
                    case "U": current.append(readHex(maxDigits: 8) ?? "U")
                    default:
                        current.append("\\")
                        current.append(next)
                    }
                }
                guard closed else { throw CurlParseError.unterminatedQuote }
            } else if c == "\\" {
                if i + 1 < chars.count {
                    let next = chars[i + 1]
                    if next.isWhitespace {
                        // Line continuation. Also covers pastes where the newline became a space.
                        finishToken()
                    } else {
                        current.append(next)
                        inToken = true
                    }
                    i += 2
                } else {
                    i += 1
                }
            } else if c.isWhitespace {
                finishToken()
                i += 1
            } else {
                current.append(c)
                inToken = true
                i += 1
            }
        }
        finishToken()
        return tokens
    }
}
