import Foundation
import Testing
@testable import CourierCore

@Suite struct ResponseFormatTests {
    @Test(arguments: [
        ("application/json; charset=utf-8", "{}", ResponseFormat.json),
        ("application/problem+json", "{}", .json),
        ("text/html; charset=utf-8", "<p>hi</p>", .html),
        ("application/xml", "<a/>", .xml),
        ("application/atom+xml", "<feed/>", .xml),
        ("text/plain", "hello", .text),
    ])
    func detectsFromContentType(contentType: String, body: String, expected: ResponseFormat) {
        #expect(ResponseFormat.detect(contentType: contentType, text: body) == expected)
    }

    @Test func sniffsWhenContentTypeIsMissingOrGeneric() {
        #expect(ResponseFormat.detect(contentType: nil, text: " [1,2]") == .json)
        #expect(ResponseFormat.detect(contentType: "text/plain", text: #"{"a":1}"#) == .json)
        #expect(ResponseFormat.detect(contentType: nil, text: "<!DOCTYPE html><html></html>") == .html)
        #expect(ResponseFormat.detect(contentType: nil, text: "<?xml version=\"1.0\"?><a/>") == .xml)
        #expect(ResponseFormat.detect(contentType: nil, text: "{not json") == .text)
        #expect(ResponseFormat.detect(contentType: "image/png", text: nil) == .binary)
    }

    @Test func prettyPrintsXML() throws {
        let pretty = try #require(ResponseFormat.xml.prettyPrinted(
            #"<?xml version="1.0"?><root><!-- c --><item id="1">a &amp; b</item><item id="2"/></root>"#
        ))
        #expect(pretty == """
        <?xml version="1.0"?>
        <root>
          <!-- c -->
          <item id="1">a &amp; b</item>
          <item id="2"/>
        </root>
        """)
    }

    @Test func prettyPrintsHTMLWithoutRewritingContent() throws {
        let html = #"<!DOCTYPE html><html><head><meta charset=utf-8><script>if (a < b && c) { x("</p>") }</script></head>"#
            + #"<body><div class="a>b"><p>Hi&nbsp;there</p><br><pre>  keep\n  this</pre></div></body></html>"#
        let pretty = try #require(ResponseFormat.html.prettyPrinted(html))
        #expect(pretty == """
        <!DOCTYPE html>
        <html>
          <head>
            <meta charset=utf-8>
            <script>if (a < b && c) { x("</p>") }</script>
          </head>
          <body>
            <div class="a>b">
              <p>Hi&nbsp;there</p>
              <br>
              <pre>  keep\\n  this</pre>
            </div>
          </body>
        </html>
        """)
    }

    @Test func invalidBodiesHaveNoPrettyView() {
        #expect(ResponseFormat.xml.prettyPrinted("<a><b></a>") == nil)
        #expect(ResponseFormat.json.prettyPrinted("{oops") == nil)
        #expect(ResponseFormat.text.prettyPrinted("hello") == nil)
    }

    @Test func responseUsesDetectedFormat() {
        let response = HTTPResponse(
            statusCode: 200,
            headers: [KeyValue("Content-Type", "application/xml")],
            body: Data("<a><b>1</b></a>".utf8),
            duration: .milliseconds(5),
            finalURL: nil
        )
        #expect(response.format == .xml)
        #expect(response.prettyText?.contains("\n") == true)
    }
}

@Suite struct MarkupHighlighterTests {
    private func kinds(_ text: String) -> [SyntaxKind] {
        MarkupHighlighter.tokens(in: text).map(\.kind)
    }

    @Test func tagsAttributesAndValues() {
        #expect(kinds(#"<a href="x">hi</a>"#) == [.tag, .attribute, .string, .tag, .tag, .tag])
    }

    @Test func selfClosingAndComments() {
        #expect(kinds(#"<!-- note --><br/>"#) == [.comment, .tag, .tag])
    }

    @Test func textWithAngleBracketsInAttributeValue() {
        let tokens = MarkupHighlighter.tokens(in: #"<x a="1>2">"#)
        #expect(tokens.map(\.kind) == [.tag, .attribute, .string, .tag])
        #expect(tokens[2].range == NSRange(location: 5, length: 5))
    }
}
