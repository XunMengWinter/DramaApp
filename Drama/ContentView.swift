import Combine
import SwiftUI

enum RootTab: Hashable {
    case home
    case theater
    case profile
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var viewModel = DramaAppViewModel()
    @StateObject private var playbackManager = PlaybackManager()
    @State private var selectedTab: RootTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeTabView()
                .tag(RootTab.home)
                .tabItem {
                    Label("首页", systemImage: "house")
                }

            TheaterTabView()
                .tag(RootTab.theater)
                .tabItem {
                    Label("剧场", systemImage: "square.grid.2x2")
                }

            ProfileTabView()
                .tag(RootTab.profile)
                .tabItem {
                    Label("我的", systemImage: "person")
                }
        }
        .environmentObject(viewModel)
        .environmentObject(playbackManager)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                playbackManager.pause()
            }
        }
        .onChange(of: selectedTab) { oldTab, newTab in
            if oldTab != newTab {
                playbackManager.pause()
            }
        }
        .onReceive(viewModel.$homeDramas.combineLatest(viewModel.$theaterSections)) { _ in
            playbackManager.updateCatalog(viewModel.allDramasById)
        }
    }
}
