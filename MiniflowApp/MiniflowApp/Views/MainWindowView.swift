import SwiftUI

struct MainWindowView: View {
    @ObservedObject var vm: AgentViewModel
    @State var selectedTab = "home"

    var body: some View {
        HStack(spacing: 0) {

            // Left sidebar
            SidebarView(vm: vm, selectedTab: $selectedTab)

            // Main content area
            ZStack(alignment: .topLeading) {
                Color.white

                Group {
                    switch selectedTab {
                    case "dictionary":
                        DictionaryTab()
                    case "shortcuts":
                        ShortcutsTab()
                    case "settings":
                        SettingsTab()
                    default:
                        HomeTab(vm: vm)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(12)
        }
        .onChange(of: selectedTab) { tab in
            if tab == "home" { Task { await vm.loadUserName() } }
        }
        .frame(width: 880, height: 600)
        .background(Color.bgWarm)
        .preferredColorScheme(.light)
    }
}
