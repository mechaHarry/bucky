import Foundation

enum CommonsImageSearchResponseParser {
    static func imageURLs(from data: Data, limit: Int) throws -> [URL] {
        guard limit > 0 else { return [] }

        let response = try JSONDecoder().decode(CommonsImageSearchResponse.self, from: data)
        let pages = response.query?.pages?.sorted { left, right in
            (left.value.index ?? Int(left.key) ?? 0) < (right.value.index ?? Int(right.key) ?? 0)
        }.map(\.value) ?? []

        var urls: [URL] = []
        var seen = Set<URL>()
        for page in pages {
            guard let thumbURLString = page.imageinfo?.first?.thumburl,
                  let url = URL(string: thumbURLString),
                  seen.insert(url).inserted else {
                continue
            }

            urls.append(url)
            if urls.count == limit { break }
        }

        return urls
    }
}

private struct CommonsImageSearchResponse: Decodable {
    let query: Query?

    struct Query: Decodable {
        let pages: [String: Page]?
    }

    struct Page: Decodable {
        let index: Int?
        let imageinfo: [ImageInfo]?
    }

    struct ImageInfo: Decodable {
        let thumburl: String?
    }
}

final class CommonsImageSearchClient {
    static let shared = CommonsImageSearchClient()

    private let session: URLSession
    private let limit: Int
    private let thumbnailWidth: Int

    init(
        session: URLSession = {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 4
            configuration.timeoutIntervalForResource = 8
            configuration.requestCachePolicy = .returnCacheDataElseLoad
            return URLSession(configuration: configuration)
        }(),
        limit: Int = 12,
        thumbnailWidth: Int = 320
    ) {
        self.session = session
        self.limit = limit
        self.thumbnailWidth = thumbnailWidth
    }

    static func searchURL(for term: String, limit: Int, thumbnailWidth: Int) -> URL? {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTerm.isEmpty,
              var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php") else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: trimmedTerm),
            URLQueryItem(name: "gsrnamespace", value: "6"),
            URLQueryItem(name: "gsrlimit", value: String(limit)),
            URLQueryItem(name: "prop", value: "imageinfo"),
            URLQueryItem(name: "iiprop", value: "url"),
            URLQueryItem(name: "iiurlwidth", value: String(thumbnailWidth))
        ]
        return components.url
    }

    func imageURLs(for term: String) async -> [URL] {
        guard let url = Self.searchURL(for: term, limit: limit, thumbnailWidth: thumbnailWidth) else {
            return []
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("Bucky macOS dictionary preview (local launcher)", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await session.data(for: request)
            return try CommonsImageSearchResponseParser.imageURLs(from: data, limit: limit)
        } catch {
            return []
        }
    }
}
