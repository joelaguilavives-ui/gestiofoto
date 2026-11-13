import SwiftUI

@main
struct GestioFotoApp: App {
    @State private var estado = EstadoApp()

    var body: some Scene {
        WindowGroup("GestioFoto") {
            RaizView()
                .environment(estado)
                .frame(minWidth: 960, minHeight: 620)
                .task { await estado.arrancar() }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Sesión") {
                Button("Bloquear") { estado.bloquear() }
                    .keyboardShortcut("l", modifiers: [.command, .control])
                    .disabled(estado.usuario == nil)
            }
        }
    }
}
