import Combine
import Foundation

@MainActor
final class DramaAppViewModel: ObservableObject {
    @Published private(set) var homeDramas: [Drama] = []
    @Published private(set) var theaterCategories: [TheaterCategory] = []
    @Published private(set) var theaterSections: [TheaterSection] = []
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String?

    private let apiClient: DramaAPIProviding
    private var hasLoaded = false

    init(apiClient: DramaAPIProviding? = nil) {
        self.apiClient = apiClient ?? DramaAPIClient()
    }

    var allDramasById: [String: Drama] {
        var all: [String: Drama] = [:]
        for drama in homeDramas {
            all[drama.id] = drama
        }
        for section in theaterSections {
            for drama in section.dramas {
                if all[drama.id] == nil {
                    all[drama.id] = drama
                }
            }
        }
        return all
    }

    var displayHomeDramas: [Drama] {
        if !homeDramas.isEmpty {
            return homeDramas
        }
        return deduplicated(theaterSections.flatMap(\.dramas))
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil
        do {
            async let homeTask = apiClient.fetchHomePayload()
            async let theaterTask = apiClient.fetchTheaterPayload()
            let (homePayload, theaterPayload) = try await (homeTask, theaterTask)
            homeDramas = deduplicated(homePayload.dramas)
            theaterCategories = theaterPayload.categories
            theaterSections = theaterPayload.sections.map {
                TheaterSection(categoryId: $0.categoryId, dramas: deduplicated($0.dramas))
            }
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func drama(with dramaId: String) -> Drama? {
        allDramasById[dramaId]
    }

    func dramas(in categoryId: String) -> [Drama] {
        guard let section = theaterSections.first(where: { $0.categoryId == categoryId }) else {
            return []
        }
        return section.dramas
    }

    private func deduplicated(_ dramas: [Drama]) -> [Drama] {
        var visited = Set<String>()
        var result: [Drama] = []
        for drama in dramas where !visited.contains(drama.id) {
            visited.insert(drama.id)
            result.append(drama)
        }
        return result
    }
}
