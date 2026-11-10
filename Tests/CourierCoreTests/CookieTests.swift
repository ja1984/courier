import Foundation
import Testing
@testable import CourierCore

@Suite struct CookiePairTests {
    @Test func parsesCookieHeader() {
        let pairs = CookiePair.parse(" a=1; b = two ;flag; =x; c=x=y ")
        #expect(pairs == [CookiePair(name: "a", value: "1"), CookiePair(name: "b", value: "two"), CookiePair(name: "c", value: "x=y")])
    }

    @Test func laterPairsWinButKeepTheirPlace() {
        let merged = CookiePair.merged([
            CookiePair(name: "a", value: "1"), CookiePair(name: "b", value: "2"), CookiePair(name: "a", value: "3"),
        ])
        #expect(CookiePair.header(merged) == "a=3; b=2")
    }

    @Test func requestCookiesCombineHeaderAndTab() {
        let spec = RequestSpec(
            headers: [KeyValue("cookie", "a=1; b=2"), KeyValue("Cookie", "z=9", isEnabled: false)],
            cookies: [KeyValue("b", "tab"), KeyValue("c", "3"), KeyValue("off", "x", isEnabled: false), KeyValue(" ", "x")]
        )
        #expect(CookiePair.header(spec.requestCookies) == "a=1; b=tab; c=3")
    }
}

@Suite struct StoredCookieTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func cookie(
        domain: String = "example.com", hostOnly: Bool = true, path: String = "/", secure: Bool = false, expires: Date? = nil
    ) -> StoredCookie {
        StoredCookie(name: "sid", value: "1", domain: domain, hostOnly: hostOnly, path: path, expires: expires, secure: secure)
    }

    @Test func hostOnlyCookiesSkipSubdomains() {
        let c = cookie()
        #expect(c.matches(URL(string: "https://example.com/x")!, at: now))
        #expect(c.matches(URL(string: "https://EXAMPLE.com/x")!, at: now))
        #expect(!c.matches(URL(string: "https://api.example.com/x")!, at: now))
        #expect(!c.matches(URL(string: "https://notexample.com/x")!, at: now))
    }

    @Test func domainCookiesIncludeSubdomains() {
        let c = cookie(domain: ".example.com", hostOnly: false)
        #expect(c.domain == "example.com")
        #expect(c.matches(URL(string: "https://api.example.com/")!, at: now))
        #expect(c.matches(URL(string: "https://example.com/")!, at: now))
        #expect(!c.matches(URL(string: "https://badexample.com/")!, at: now))
    }

    @Test(arguments: [
        ("/", "/", true), ("/anything", "/", true), ("", "/", true),
        ("/api", "/api", true), ("/api/users", "/api", true), ("/api/users", "/api/", true),
        ("/apis", "/api", false), ("/", "/api", false), ("/other", "/api", false),
    ])
    func pathMatching(requestPath: String, cookiePath: String, expected: Bool) {
        #expect(StoredCookie.pathMatches(requestPath: requestPath, cookiePath: cookiePath) == expected)
    }

    @Test func secureCookiesNeedHTTPSExceptOnLocalhost() {
        #expect(!cookie(secure: true).matches(URL(string: "http://example.com/")!, at: now))
        #expect(cookie(secure: true).matches(URL(string: "https://example.com/")!, at: now))
        #expect(cookie(domain: "localhost", secure: true).matches(URL(string: "http://localhost:8080/")!, at: now))
    }

    @Test func expiredCookiesAreNotSent() {
        #expect(!cookie(expires: now).matches(URL(string: "https://example.com/")!, at: now))
        #expect(cookie(expires: now.addingTimeInterval(60)).matches(URL(string: "https://example.com/")!, at: now))
    }

    @Test func readsSetCookieHeaders() throws {
        let url = URL(string: "https://api.example.com/v1/login")!
        let cookies = StoredCookie.fromHeaders(
            ["Set-Cookie": "sid=abc; Path=/; Secure; HttpOnly; SameSite=Lax"], for: url
        )
        let sid = try #require(cookies.first)
        #expect(sid.name == "sid" && sid.value == "abc")
        #expect(sid.domain == "api.example.com" && sid.hostOnly)
        #expect(sid.secure && sid.httpOnly && sid.expires == nil)
        #expect(sid.sameSite?.lowercased() == "lax")

        let shared = StoredCookie.fromHeaders(["Set-Cookie": "theme=dark; Domain=example.com; Path=/"], for: url)
        #expect(shared.first?.domain == "example.com")
        #expect(shared.first?.hostOnly == false)
    }

    @Test func acceptsCookiesFromLocalhost() {
        let cookies = StoredCookie.fromHeaders(["Set-Cookie": "sid=abc; Path=/"], for: URL(string: "http://localhost:3000/login")!)
        #expect(cookies.map(\.name) == ["sid"])
        #expect(cookies.first?.matches(URL(string: "http://localhost:3000/me")!) == true)
    }
}

@Suite struct CookieJarTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let url = URL(string: "https://example.com/api/users")!

    @Test func replacesCookiesWithTheSameNameDomainAndPath() {
        var jar = CookieJar()
        jar.store([StoredCookie(name: "sid", value: "1", domain: "example.com")], at: now)
        jar.store([StoredCookie(name: "sid", value: "2", domain: "example.com")], at: now)
        jar.store([StoredCookie(name: "sid", value: "api", domain: "example.com", path: "/api")], at: now)
        #expect(jar.cookies.count == 2)
        // Longest path first.
        #expect(jar.cookies(for: url, at: now).map(\.value) == ["api", "2"])
    }

    @Test func expiredCookieDeletesItsMatch() {
        var jar = CookieJar()
        jar.store([StoredCookie(name: "sid", value: "1", domain: "example.com")], at: now)
        jar.store([StoredCookie(name: "sid", value: "", domain: "example.com", expires: now.addingTimeInterval(-1))], at: now)
        #expect(jar.isEmpty)
    }

    @Test func editsAndRemoves() {
        var jar = CookieJar()
        let a = StoredCookie(name: "a", value: "1", domain: "example.com")
        let b = StoredCookie(name: "b", value: "1", domain: "other.com")
        jar.store([a, b], at: now)
        jar.setValue("edited", for: a.id)
        #expect(jar.cookies.first?.value == "edited")
        jar.removeAll(domain: "OTHER.com")
        #expect(jar.cookies.map(\.name) == ["a"])
        jar.remove(a.id)
        #expect(jar.isEmpty)
    }

    @Test func requestCookiesOverrideJarCookies() {
        let header = CookieJar.cookieHeader(
            jar: [StoredCookie(name: "sid", value: "jar", domain: "example.com"), StoredCookie(name: "theme", value: "dark", domain: "example.com")],
            request: [CookiePair(name: "sid", value: "mine")]
        )
        #expect(header == "sid=mine; theme=dark")
        #expect(CookieJar.cookieHeader(jar: [], request: []) == nil)
    }

    @Test func roundTripsThroughJSON() throws {
        var jar = CookieJar()
        jar.store([StoredCookie(name: "a", value: "1", domain: ".example.com", hostOnly: false, expires: now.addingTimeInterval(3600), secure: true)], at: now)
        let decoded = try JSONDecoder().decode(CookieJar.self, from: JSONEncoder().encode(jar))
        #expect(decoded == jar)
    }
}

@Suite struct CookieSendingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func buildsOneCookieHeaderFromJarHeadersAndTab() throws {
        var jar = CookieJar()
        jar.store([
            StoredCookie(name: "sid", value: "jar", domain: "example.com"),
            StoredCookie(name: "other", value: "x", domain: "other.com"),
        ], at: now)
        let spec = RequestSpec(
            url: "https://example.com/",
            headers: [KeyValue("Cookie", "a=1"), KeyValue("Accept", "*/*")],
            cookies: [KeyValue("sid", "tab")]
        )
        let request = try HTTPClient.makeURLRequest(from: spec, jar: jar, at: now)
        #expect(request.value(forHTTPHeaderField: "Cookie") == "sid=tab; a=1")
        #expect(request.value(forHTTPHeaderField: "Accept") == "*/*")
        #expect(request.httpShouldHandleCookies == false)
    }

    @Test func sendsNoCookieHeaderWithoutCookies() throws {
        let request = try HTTPClient.makeURLRequest(from: RequestSpec(url: "https://example.com/"), jar: CookieJar())
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test func redirectsCarryNewCookiesButOwnCookiesStayOnTheirHost() {
        let redirect = RedirectCookies(jar: nil, requestCookies: [CookiePair(name: "mine", value: "1")], originalHost: "example.com")
        let received = [StoredCookie(name: "sid", value: "new", domain: "example.com")]
        #expect(redirect.header(for: URL(string: "https://example.com/home")!, received: received, at: now) == "sid=new; mine=1")
        #expect(redirect.header(for: URL(string: "https://elsewhere.com/")!, received: received, at: now) == nil)
    }
}

@Suite struct CookieInteropTests {
    @Test func curlCookiesLandInTheCookiesTab() throws {
        let spec = try CurlParser.parse("curl https://example.com -H 'Cookie: a=1; b=2' -b 'b=3; c=4' -H 'Accept: */*'")
        #expect(spec.cookies.map(\.key) == ["a", "b", "c"])
        #expect(spec.cookies.map(\.value) == ["1", "3", "4"])
        #expect(!spec.headers.contains { $0.key.lowercased() == "cookie" })
    }

    @Test func cookieFilePathIsIgnored() throws {
        let spec = try CurlParser.parse("curl -b cookies.txt https://example.com")
        #expect(spec.cookies.isEmpty)
    }

    @Test func exportsCookiesWithDashB() throws {
        let spec = RequestSpec(url: "https://example.com", headers: [KeyValue("Cookie", "a=1")], cookies: [KeyValue("b", "2")])
        let command = CurlExporter.command(for: spec)
        #expect(command.contains("-b 'a=1; b=2'"))
        #expect(!command.contains("-H 'Cookie"))
        let roundTrip = try CurlParser.parse(command)
        #expect(roundTrip.cookies.map(\.key) == ["a", "b"])
    }

    @Test func exportsLeaveCookieValuesOut() {
        let spec = CollectionTransfer.withoutSecrets(RequestSpec(cookies: [KeyValue("theme", "dark"), KeyValue("sid", "secret")]))
        #expect(spec.cookies.map(\.key) == ["theme", "sid"])
        #expect(spec.cookies.allSatisfy { $0.value.isEmpty })
    }

    @Test func decodesRequestsSavedBeforeCookiesExisted() throws {
        let old = #"{"method":"GET","url":"https://example.com","params":[],"headers":[],"bodyKind":"none","bodyText":"","formFields":[]}"#
        let spec = try JSONDecoder().decode(RequestSpec.self, from: Data(old.utf8))
        #expect(spec.cookies.isEmpty)
        #expect(spec.url == "https://example.com")
    }

    @Test func cookieEditsCountAsChanges() {
        let a = RequestSpec(url: "https://example.com")
        var b = a
        b.cookies = [KeyValue("sid", "1")]
        #expect(!a.hasSameContent(as: b))
    }
}
