import SwiftUI

@main
struct HouseKeepingApp: App {
    @State private var model = AppModel()
    @State private var selection: ContentView.Page? = .rules
    @AppStorage("appearance") private var appearance = "system"
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("House Keeping", id: "main") {
            ContentView(model: model, selection: $selection)
                .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
        }
        .defaultSize(width: 900, height: 650)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    selection = .settings
                    openWindow(id: "main")
                }
                .keyboardShortcut(",")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Rules") { model.save() }
                    .keyboardShortcut("s")
                    .disabled(!model.isDirty || model.isBusy)
                Button("Validate Rules") { model.validate() }
                    .keyboardShortcut("k")
                    .disabled(model.document == nil)
            }
            CommandGroup(replacing: .help) {
                Button("Configuration Reference") {
                    if let url = Bundle.main.url(forResource: "Configuration Reference", withExtension: "md") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}
