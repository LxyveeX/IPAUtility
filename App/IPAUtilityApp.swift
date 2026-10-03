import SwiftUI

@main
struct IPAUtilityApp: App {
    @StateObject private var model = LibraryModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            LibraryView().environmentObject(model)
                .tint(Color(red: 0.04, green: 0.58, blue: 0.88))
                .onOpenURL { model.receive($0) }
                .task { if model.folder != nil { model.refresh() } }
                .onChange(of: scenePhase) { phase in
                    if phase == .active, model.folder != nil, !model.loading, !model.busy, model.selected == nil { model.refresh() }
                }
        }
    }
}
