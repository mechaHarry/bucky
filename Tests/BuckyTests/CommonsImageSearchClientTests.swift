import Foundation
import XCTest
@testable import Bucky

final class CommonsImageSearchClientTests: XCTestCase {
    func testThumbnailURLPolicyAllowsOnlyExactHTTPSUploadHost() {
        XCTAssertTrue(CommonsThumbnailURLPolicy.isAllowed(URL(string: "https://upload.wikimedia.org/wikipedia/commons/thumb/a.jpg")!))
        for value in [
            "http://upload.wikimedia.org/a.jpg",
            "https://upload.wikimedia.org.evil.example/a.jpg",
            "https://evil.example/a.jpg",
            "https://user:password@upload.wikimedia.org/a.jpg",
            "https://upload.wikimedia.org:443/a.jpg"
        ] {
            XCTAssertFalse(CommonsThumbnailURLPolicy.isAllowed(URL(string: value)!))
        }
    }

    func testRetryPolicyRetriesOnlyTransientStatusesWithinBounds() {
        XCTAssertEqual(CommonsImageRetryPolicy.delayNanoseconds(for: 503, attempt: 0), 250_000_000)
        XCTAssertEqual(CommonsImageRetryPolicy.delayNanoseconds(for: 429, attempt: 1), 750_000_000)
        XCTAssertNil(CommonsImageRetryPolicy.delayNanoseconds(for: 404, attempt: 0))
        XCTAssertNil(CommonsImageRetryPolicy.delayNanoseconds(for: 503, attempt: 2))
    }

    func testParserExcludesInvalidThumbnailURLsBeforeDedupe() throws {
        let data = #"{"query":{"pages":{"1":{"imageinfo":[{"thumburl":"http://upload.wikimedia.org/a.jpg"}]},"2":{"imageinfo":[{"thumburl":"https://evil.example/a.jpg"}]},"3":{"imageinfo":[{"thumburl":"https://upload.wikimedia.org/a.jpg"}]}}}}"#.data(using: .utf8)!
        XCTAssertEqual(try CommonsImageSearchResponseParser.imageURLs(from: data, limit: 4).map(\.absoluteString), ["https://upload.wikimedia.org/a.jpg"])
    }

    func test503Then200RetriesOnceAndReturnsResult() async throws {
        StubURLProtocol.setResponses([
            (503, Data()),
            (200, Data("{\"query\":{\"pages\":{\"1\":{\"imageinfo\":[{\"thumburl\":\"https://upload.wikimedia.org/a.jpg\"}]}}}}".utf8))
        ])
        let client = makeClient(protocolType: StubURLProtocol.self)
        let result = await client.imageURLs(for: "term")
        XCTAssertEqual(result.map(\.absoluteString), ["https://upload.wikimedia.org/a.jpg"])
        XCTAssertEqual(StubURLProtocol.requestCount, 2)
    }

    func test404DoesNotRetryAndReturnsEmpty() async {
        StubURLProtocol.setResponses([(404, Data())])
        let result = await makeClient(protocolType: StubURLProtocol.self).imageURLs(for: "term")
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
    }

    func testCancellationPreventsFurtherRequest() async {
        StubURLProtocol.setResponses([(503, Data()), (200, Data())])
        let client = makeClient(protocolType: StubURLProtocol.self)
        let task = Task { await client.imageURLs(for: "term") }
        XCTAssertTrue(StubURLProtocol.waitForRequestCount(1))
        task.cancel()
        _ = await task.value
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
    }

    func testNonHTTPResponseAndTransportErrorReturnEmpty() async {
        StubURLProtocol.setResponses([(0, Data())])
        let result = await makeClient(protocolType: StubURLProtocol.self).imageURLs(for: "term")
        XCTAssertTrue(result.isEmpty)
    }

    private func makeClient(protocolType: URLProtocol.Type) -> CommonsImageSearchClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [protocolType]
        let session = URLSession(configuration: configuration)
        return CommonsImageSearchClient(session: session, sleep: { _ in try await Task.sleep(nanoseconds: 250_000_000) })
    }
}

private final class StubURLProtocol: URLProtocol {
    private static let state = StubState()

    static func setResponses(_ responses: [(Int, Data)]) {
        state.setResponses(responses)
    }

    static var requestCount: Int { state.requestCount }

    static func waitForRequestCount(_ count: Int) -> Bool {
        state.waitForRequestCount(count)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let response = Self.state.nextResponse() else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        if response.0 == 0 { client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: response.0, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.1)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    private final class StubState: @unchecked Sendable {
        private let condition = NSCondition()
        private var responses: [(Int, Data)] = []

        func setResponses(_ responses: [(Int, Data)]) {
            condition.lock()
            self.responses = responses
            storedRequestCount = 0
            condition.broadcast()
            condition.unlock()
        }

        func nextResponse() -> (Int, Data)? {
            condition.lock()
            defer { condition.unlock() }
            storedRequestCount += 1
            condition.broadcast()
            guard !responses.isEmpty else { return nil }
            return responses.removeFirst()
        }

        func waitForRequestCount(_ count: Int) -> Bool {
            condition.lock()
            defer { condition.unlock() }
            while storedRequestCount < count {
                if !condition.wait(until: Date().addingTimeInterval(2)) { return false }
            }
            return true
        }

        var requestCount: Int {
            condition.lock()
            defer { condition.unlock() }
            return storedRequestCount
        }

        private var storedRequestCount: Int = 0
    }
}
