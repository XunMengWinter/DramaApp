import Foundation

private enum RemoteAssetURL {
    static let baseURL = URL(string: "https://zzz-pet.oss-cn-hangzhou.aliyuncs.com/")!

    static func resolve(_ rawValue: String) -> URL? {
        if let absoluteURL = URL(string: rawValue), absoluteURL.scheme != nil {
            return absoluteURL
        }
        return URL(string: rawValue, relativeTo: baseURL)?.absoluteURL
    }
}

struct DramaPayload: Codable {
    let dramas: [Drama]
}

struct TheaterPayload: Codable {
    let categories: [TheaterCategory]
    let sections: [TheaterSection]
}

struct Drama: Codable, Identifiable, Hashable {
    let dramaId: String
    let title: String
    let poster: String
    let tags: [String]
    let description: String
    let totalEpisodes: Int
    let episodes: [Episode]

    var id: String { dramaId }

    var posterURL: URL? {
        RemoteAssetURL.resolve(poster)
    }

    var sortedEpisodes: [Episode] {
        episodes.sorted { $0.episodeNumber < $1.episodeNumber }
    }

    init(dramaId: String,
         title: String,
         poster: String,
         tags: [String],
         description: String,
         totalEpisodes: Int,
         episodes: [Episode]) {
        self.dramaId = dramaId
        self.title = title
        self.poster = poster
        self.tags = tags
        self.description = description
        self.totalEpisodes = totalEpisodes
        self.episodes = episodes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dramaId = try container.decode(String.self, forKey: .dramaId)
        title = try container.decode(String.self, forKey: .title)
        poster = try container.decodeIfPresent(String.self, forKey: .poster) ?? ""
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        totalEpisodes = try container.decodeIfPresent(Int.self, forKey: .totalEpisodes) ?? 0
        episodes = try container.decodeIfPresent([Episode].self, forKey: .episodes) ?? []
    }
}

struct Episode: Codable, Identifiable, Hashable {
    let episodeNumber: Int
    let title: String
    let videoUrl: String
    let duration: Int
    let aspectRatio: Double

    var id: Int { episodeNumber }

    var videoURL: URL? {
        RemoteAssetURL.resolve(videoUrl)
    }

    init(episodeNumber: Int,
         title: String,
         videoUrl: String,
         duration: Int,
         aspectRatio: Double) {
        self.episodeNumber = episodeNumber
        self.title = title
        self.videoUrl = videoUrl
        self.duration = duration
        self.aspectRatio = aspectRatio
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        episodeNumber = try container.decode(Int.self, forKey: .episodeNumber)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "第\(episodeNumber)集"
        videoUrl = try container.decodeIfPresent(String.self, forKey: .videoUrl) ?? ""
        duration = try container.decodeIfPresent(Int.self, forKey: .duration) ?? 0
        aspectRatio = try container.decodeIfPresent(Double.self, forKey: .aspectRatio) ?? 9.0 / 16.0
    }
}

struct TheaterCategory: Codable, Identifiable, Hashable {
    let categoryId: String
    let title: String
    let titleZh: String

    var id: String { categoryId }
}

struct TheaterSection: Codable, Hashable {
    let categoryId: String
    let dramas: [Drama]
}
