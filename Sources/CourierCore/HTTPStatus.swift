import Foundation

/// Standard reason phrases from the IANA HTTP Status Code Registry.
/// HTTP/2+ responses carry no reason phrase, and URLSession doesn't expose HTTP/1.1's,
/// so the code is the only thing we can go on.
public enum HTTPStatus {
    public static func reasonPhrase(for code: Int) -> String {
        if let phrase = phrases[code] { return phrase }
        switch code {
        case 100..<200: return "Informational"
        case 200..<300: return "Success"
        case 300..<400: return "Redirection"
        case 400..<500: return "Client Error"
        case 500..<600: return "Server Error"
        default: return "Unknown"
        }
    }

    /// A short explanation of what the status means.
    public static func explanation(for code: Int) -> String {
        if let text = explanations[code] { return text }
        switch code {
        case 100..<200: return "An interim response. The server has received the request and the client should continue."
        case 200..<300: return "The request was received, understood and accepted."
        case 300..<400: return "Further action, usually following another URL, is needed to complete the request."
        case 400..<500: return "The request contains an error or can't be fulfilled as sent."
        case 500..<600: return "The server failed to fulfil a request that appears valid."
        default: return "A non-standard status code."
        }
    }

    private static let explanations: [Int: String] = [
        100: "The server received the request headers; the client should send the body.",
        101: "The server is switching to the protocol the client asked for, such as WebSocket.",
        103: "Preliminary headers so the client can start preloading resources.",
        200: "Standard response for successful HTTP requests. For GET it contains the requested resource; for POST it describes the result of the action.",
        201: "The request succeeded and a new resource was created, usually identified by the Location header.",
        202: "The request was accepted for processing, but processing hasn't finished.",
        203: "Success, but the returned metadata came from a transforming proxy rather than the origin server.",
        204: "The request succeeded and there is no content to return.",
        205: "Success; the client should reset the document view, such as clearing a form.",
        206: "The server is returning only part of the resource, as requested with a Range header.",
        207: "Multiple independent results for a WebDAV request, each with its own status.",
        301: "The resource has permanently moved to the URL in the Location header. Update links and bookmarks.",
        302: "The resource is temporarily at the URL in the Location header.",
        303: "The result can be found at another URL, which should be retrieved with GET.",
        304: "The cached copy is still valid; the resource hasn't changed since the version the client has.",
        307: "Temporary redirect; repeat the same request (same method and body) at the new URL.",
        308: "Permanent redirect; repeat the same request (same method and body) at the new URL.",
        400: "The server couldn't process the request because it was malformed, such as invalid syntax or parameters.",
        401: "Authentication is required and has failed or hasn't been provided.",
        402: "Reserved for future use; some APIs use it to signal that payment is required.",
        403: "The server understood the request but refuses to authorize it. Re-authenticating won't help.",
        404: "The server can't find the requested resource.",
        405: "The resource doesn't support this HTTP method.",
        406: "The server can't produce a response matching the request's Accept headers.",
        407: "The client must first authenticate with the proxy.",
        408: "The server timed out waiting for the request.",
        409: "The request conflicts with the current state of the resource, such as an edit conflict.",
        410: "The resource is permanently gone and won't come back.",
        411: "The server requires a Content-Length header.",
        412: "A precondition in the request headers, such as If-Match, wasn't met.",
        413: "The request body is larger than the server is willing to process.",
        414: "The URL is longer than the server is willing to interpret.",
        415: "The server doesn't support the request body's media type.",
        416: "The requested Range can't be satisfied.",
        417: "The server can't meet the Expect request header.",
        418: "The server refuses to brew coffee because it is a teapot (an April Fools' joke from RFC 2324).",
        421: "The request was sent to a server that can't produce a response for this URL.",
        422: "The request was well-formed but contains semantic errors, such as failed validation.",
        423: "The resource is locked.",
        425: "The server won't process a request that might be replayed.",
        426: "The client should switch to a different protocol.",
        428: "The server requires the request to be conditional, such as using If-Match.",
        429: "Too many requests in a given time. Check Retry-After before trying again.",
        431: "The request's headers are too large.",
        451: "The resource is unavailable for legal reasons.",
        500: "A generic error: the server hit an unexpected condition.",
        501: "The server doesn't support the functionality needed to fulfil the request.",
        502: "The server, acting as a gateway or proxy, got an invalid response from the upstream server.",
        503: "The server is temporarily unable to handle the request, often due to overload or maintenance.",
        504: "The server, acting as a gateway or proxy, didn't get a timely response from the upstream server.",
        505: "The server doesn't support the HTTP version used in the request.",
        507: "The server can't store what's needed to complete the request.",
        508: "The server detected an infinite loop while processing the request.",
        511: "The client must authenticate to gain network access, as with a captive portal.",
    ]

    private static let phrases: [Int: String] = [
        100: "Continue",
        101: "Switching Protocols",
        102: "Processing",
        103: "Early Hints",
        200: "OK",
        201: "Created",
        202: "Accepted",
        203: "Non-Authoritative Information",
        204: "No Content",
        205: "Reset Content",
        206: "Partial Content",
        207: "Multi-Status",
        208: "Already Reported",
        226: "IM Used",
        300: "Multiple Choices",
        301: "Moved Permanently",
        302: "Found",
        303: "See Other",
        304: "Not Modified",
        305: "Use Proxy",
        307: "Temporary Redirect",
        308: "Permanent Redirect",
        400: "Bad Request",
        401: "Unauthorized",
        402: "Payment Required",
        403: "Forbidden",
        404: "Not Found",
        405: "Method Not Allowed",
        406: "Not Acceptable",
        407: "Proxy Authentication Required",
        408: "Request Timeout",
        409: "Conflict",
        410: "Gone",
        411: "Length Required",
        412: "Precondition Failed",
        413: "Content Too Large",
        414: "URI Too Long",
        415: "Unsupported Media Type",
        416: "Range Not Satisfiable",
        417: "Expectation Failed",
        418: "I'm a Teapot",
        421: "Misdirected Request",
        422: "Unprocessable Content",
        423: "Locked",
        424: "Failed Dependency",
        425: "Too Early",
        426: "Upgrade Required",
        428: "Precondition Required",
        429: "Too Many Requests",
        431: "Request Header Fields Too Large",
        451: "Unavailable For Legal Reasons",
        500: "Internal Server Error",
        501: "Not Implemented",
        502: "Bad Gateway",
        503: "Service Unavailable",
        504: "Gateway Timeout",
        505: "HTTP Version Not Supported",
        506: "Variant Also Negotiates",
        507: "Insufficient Storage",
        508: "Loop Detected",
        510: "Not Extended",
        511: "Network Authentication Required",
    ]
}
