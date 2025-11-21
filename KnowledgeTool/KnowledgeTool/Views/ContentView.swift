import SwiftUI

enum NavigationItem: String, CaseIterable, Identifiable {
    case video = "Video"
    case article = "Article"
    case textSnippet = "Text Snippet"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .video: return "video.fill"
        case .article: return "doc.text.fill"
        case .textSnippet: return "text.quote"
        }
    }
}

struct ContentView: View {
    @Environment(APIKeyManager.self) private var apiKeyManager
    @State private var selectedItem: NavigationItem = .video
    @State private var showingSettings = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedItem: $selectedItem)
        } detail: {
            DetailView(selectedItem: selectedItem, apiKeyManager: apiKeyManager)
        }
        .navigationSplitViewStyle(.balanced)
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            showingSettings = true
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environment(apiKeyManager)
        }
    }
}

// MARK: - Sidebar View
struct SidebarView: View {
    @Binding var selectedItem: NavigationItem

    var body: some View {
        List(NavigationItem.allCases, selection: $selectedItem) { item in
            NavigationLink(value: item) {
                Label {
                    Text(item.rawValue)
                        .font(.body)
                } icon: {
                    Image(systemName: item.icon)
                }
            }
        }
        .navigationTitle("Knowledge Tool")
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 250)
    }
}

// MARK: - Detail View
struct DetailView: View {
    let selectedItem: NavigationItem
    let apiKeyManager: APIKeyManager

    var body: some View {
        Group {
            switch selectedItem {
            case .video:
                VideoView(viewModel: VideoViewModel(apiKeyManager: apiKeyManager))
            case .article:
                ArticleView(viewModel: ArticleViewModel(apiKeyManager: apiKeyManager))
            case .textSnippet:
                TextSnippetView(viewModel: TextSnippetViewModel(apiKeyManager: apiKeyManager))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
        .environment(APIKeyManager())
        .frame(width: 1000, height: 700)
}
