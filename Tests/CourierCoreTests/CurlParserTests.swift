import Foundation
import Testing
@testable import CourierCore

@Suite struct CurlParserTests {
    @Test func simpleGet() throws {
        let spec = try CurlParser.parse("curl https://api.example.com/users?page=2&q=hello%20world")
        #expect(spec.method == .get)
        #expect(spec.url == "https://api.example.com/users?page=2&q=hello%20world")
        #expect(spec.params.map(\.key) == ["page", "q"])
        #expect(spec.params.map(\.value) == ["2", "hello world"])
        #expect(spec.bodyKind == .none)
    }

    @Test func multilinePostWithJSONBody() throws {
        let command = """
        curl -X POST 'https://api.example.com/items' \\
          -H 'Content-Type: application/json' \\
          -H "Authorization: Bearer abc123" \\
          --data-raw '{"name":"Widget","tags":["a","b"],"price":9.5}'
        """
        let spec = try CurlParser.parse(command)
        #expect(spec.method == .post)
        #expect(spec.url == "https://api.example.com/items")
        #expect(spec.headers.map(\.key) == ["Content-Type", "Authorization"])
        #expect(spec.headers[1].value == "Bearer abc123")
        #expect(spec.bodyKind == .json)
        // Key order is preserved when pretty-printing.
        let nameIndex = try #require(spec.bodyText.range(of: "\"name\""))
        let priceIndex = try #require(spec.bodyText.range(of: "\"price\""))
        #expect(nameIndex.lowerBound < priceIndex.lowerBound)
        #expect(spec.bodyText.contains("\n"))
    }

    @Test func dataImpliesPostAndFormBody() throws {
        let spec = try CurlParser.parse("curl https://example.com/login -d 'user=jo&pass=s%26cret'")
        #expect(spec.method == .post)
        #expect(spec.bodyKind == .form)
        #expect(spec.formFields.map(\.key) == ["user", "pass"])
        #expect(spec.formFields[1].value == "s&cret")
    }

    @Test func attachedShortOptionValue() throws {
        let spec = try CurlParser.parse("curl -XPUT -HAccept:text/plain example.com")
        #expect(spec.method == .put)
        #expect(spec.headers.first?.key == "Accept")
        #expect(spec.headers.first?.value == "text/plain")
        #expect(spec.url == "example.com")
    }

    @Test func basicAuthBecomesHeader() throws {
        let spec = try CurlParser.parse("curl -u admin:secret https://example.com")
        #expect(spec.headers.first?.key == "Authorization")
        #expect(spec.headers.first?.value == "Basic " + Data("admin:secret".utf8).base64EncodedString())
    }

    @Test func chromeStyleAnsiCQuoting() throws {
        let command = #"""
        curl 'https://example.com/api' \
          -H 'accept: */*' \
          --data-raw $'{"msg":"it\'s\\nfine","e":"é"}' \
          --compressed
        """#
        let spec = try CurlParser.parse(command)
        #expect(spec.method == .post)
        #expect(spec.bodyKind == .json)
        #expect(spec.bodyText.contains(#""it's\nfine""#))
        #expect(spec.bodyText.contains("é"))
    }

    @Test func getFlagMovesDataToQuery() throws {
        let spec = try CurlParser.parse("curl -G https://example.com/search -d q=swift --data-urlencode 'tag=a b'")
        #expect(spec.method == .get)
        #expect(spec.bodyKind == .none)
        #expect(spec.url == "https://example.com/search?q=swift&tag=a%20b")
        #expect(spec.params.map(\.value) == ["swift", "a b"])
    }

    @Test func doubleQuotedEscapes() throws {
        let spec = try CurlParser.parse(#"curl "https://example.com" -H "X-Quote: say \"hi\"""#)
        #expect(spec.headers.first?.value == #"say "hi""#)
    }

    @Test func jsonFlagSetsHeaders() throws {
        let spec = try CurlParser.parse(#"curl --json '{"a":1}' https://example.com"#)
        #expect(spec.method == .post)
        #expect(spec.bodyKind == .json)
        #expect(spec.headers.contains { $0.key == "Content-Type" && $0.value == "application/json" })
        #expect(spec.headers.contains { $0.key == "Accept" })
    }

    @Test func headFlag() throws {
        let spec = try CurlParser.parse("curl -I https://example.com")
        #expect(spec.method == .head)
    }

    @Test func ignoredOptionValuesAreNotTakenAsURL() throws {
        let spec = try CurlParser.parse("curl -o out.json -sSL --max-time 10 https://example.com/data")
        #expect(spec.url == "https://example.com/data")
    }

    @Test func leadingPromptAndCustomMethod() throws {
        let spec = try CurlParser.parse("$ curl -X purge https://cdn.example.com/x")
        #expect(spec.method.rawValue == "PURGE")
    }

    @Test func plainTextBody() throws {
        let spec = try CurlParser.parse("curl -H 'Content-Type: text/plain' -d 'hello there' https://example.com")
        #expect(spec.bodyKind == .text)
        #expect(spec.bodyText == "hello there")
    }

    @Test func errors() {
        #expect(throws: CurlParseError.notACurlCommand) { try CurlParser.parse("wget https://example.com") }
        #expect(throws: CurlParseError.missingURL) { try CurlParser.parse("curl -H 'A: b'") }
        #expect(throws: CurlParseError.unterminatedQuote) { try CurlParser.parse("curl 'https://example.com") }
        #expect(throws: CurlParseError.missingValue("-H")) { try CurlParser.parse("curl https://example.com -H") }
    }

    @Test func looksLikeCurl() {
        #expect(CurlParser.looksLikeCurl("  curl https://x.com"))
        #expect(CurlParser.looksLikeCurl("$ curl https://x.com"))
        #expect(!CurlParser.looksLikeCurl("https://x.com/curl"))
    }
}

@Suite struct CurlExporterTests {
    @Test func roundTrip() throws {
        var spec = RequestSpec(method: .patch, headers: [KeyValue("X-Token", "it's"), KeyValue("Off", "x", isEnabled: false)])
        spec.setURL("https://example.com/items/1?verbose=true")
        spec.bodyKind = .json
        spec.bodyText = #"{"name": "O'Brien"}"#

        let command = CurlExporter.command(for: spec)
        #expect(!command.contains("Off: x"))

        let parsed = try CurlParser.parse(command)
        #expect(parsed.method == .patch)
        #expect(parsed.url == spec.url)
        #expect(parsed.headers.map(\.key) == ["X-Token", "Content-Type"])
        #expect(parsed.headers[0].value == "it's")
        #expect(parsed.bodyKind == .json)
        #expect(parsed.bodyText.contains("O'Brien"))
    }

    @Test func getWithoutBodyHasNoMethodFlag() {
        let command = CurlExporter.command(for: RequestSpec(url: "https://example.com"))
        #expect(command == "curl 'https://example.com'")
    }
}
