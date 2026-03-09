import Foundation

enum DramaAPIError: LocalizedError {
    case invalidResponse
    case badStatusCode(Int)
    case emptyData

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "服务返回了无效响应。"
        case .badStatusCode(let code):
            return "服务请求失败（HTTP \(code)）。"
        case .emptyData:
            return "服务返回了空数据。"
        }
    }
}

protocol DramaAPIProviding {
    func fetchHomePayload() async throws -> DramaPayload
    func fetchTheaterPayload() async throws -> TheaterPayload
}

struct DramaAPIClient: DramaAPIProviding {
    static let homeURL = URL(string: "https://zzz-pet.oss-cn-hangzhou.aliyuncs.com/api/drama.json")!
    static let theaterURL = URL(string: "https://zzz-pet.oss-cn-hangzhou.aliyuncs.com/api/theater.json")!

    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = URLSession(configuration: .default)) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    func fetchHomePayload() async throws -> DramaPayload {
        try await request(url: Self.homeURL)
    }

    func fetchTheaterPayload() async throws -> TheaterPayload {
        try await request(url: Self.theaterURL)
    }

    private func request<T: Decodable>(url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DramaAPIError.invalidResponse
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw DramaAPIError.badStatusCode(httpResponse.statusCode)
        }
        guard !data.isEmpty else {
            throw DramaAPIError.emptyData
        }
        return try decoder.decode(T.self, from: data)
    }
}
