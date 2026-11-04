import Testing
@testable import CourierCore

@Suite struct SensitiveHeadersTests {
    @Test(arguments: [
        "Authorization", "authorization", "Proxy-Authorization", "Cookie", "Set-Cookie",
        "X-API-Key", "x-api-key", "api_key", "Api-Key", "X-Auth-Token", "Auth-Token", "token",
        "X-Access-Token", "X-CSRF-Token", "X-XSRF-TOKEN", "X-Client-Secret", "Ocp-Apim-Subscription-Key",
        "X-Functions-Key", "X-Session-Id", "X-Amz-Security-Token", "X-Hub-Signature-256", "X-Password",
    ])
    func flagsSecrets(_ name: String) {
        #expect(SensitiveHeaders.isSensitive(name))
    }

    @Test(arguments: [
        "Content-Type", "Accept", "User-Agent", "Keep-Alive", "Cache-Control", "X-Request-Id",
        "WWW-Authenticate", "Proxy-Authenticate", "Host", "", "-",
    ])
    func leavesOrdinaryHeadersAlone(_ name: String) {
        #expect(!SensitiveHeaders.isSensitive(name))
    }
}
