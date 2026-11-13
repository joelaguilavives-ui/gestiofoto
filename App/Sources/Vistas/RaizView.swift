import SwiftUI

/// Elige la pantalla según la fase de la app y tapa todo si se pierde la conexión.
struct RaizView: View {
    @Environment(EstadoApp.self) private var estado

    var body: some View {
        Group {
            switch estado.fase {
            case .iniciando:
                ProgressView()
            case .configurarConexion:
                ConexionView()
            case .preparando(let texto):
                VStack(spacing: 12) {
                    ProgressView()
                    Text(texto).foregroundStyle(.secondary)
                }
            case .error(let mensaje):
                ErrorConexionView(mensaje: mensaje)
            case .primerTitular:
                PrimerTitularView()
            case .esperandoTitular:
                EsperandoTitularView()
            case .login:
                LoginView()
            case .trabajando:
                PrincipalView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if estado.sinConexion {
                SinConexionView()
            }
        }
        .animation(.default, value: estado.sinConexion)
    }
}

/// Tapa la ventana: no se puede trabajar a medias sin el Mac principal.
struct SinConexionView: View {
    @Environment(EstadoApp.self) private var estado

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            VStack(spacing: 14) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)
                Text("Sin conexión con el Mac principal")
                    .font(.title2.bold())
                Text("Comprueba que \(estado.conexion?.servidor ?? "el Mac principal") está encendido, con Postgres.app abierto y en la misma red. La app vuelve sola en cuanto haya conexión; lo que no se había guardado no se ha guardado.")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                    .foregroundStyle(.secondary)
                ProgressView().controlSize(.small)
            }
            .padding(32)
        }
        .ignoresSafeArea()
    }
}

struct ErrorConexionView: View {
    @Environment(EstadoApp.self) private var estado
    let mensaje: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text(mensaje)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
                .textSelection(.enabled)
            HStack {
                Button("Cambiar conexión") { estado.cambiarConexion() }
                Button("Reintentar") { Task { await estado.reintentar() } }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
    }
}

struct EsperandoTitularView: View {
    @Environment(EstadoApp.self) private var estado

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 40))
            Text("Todavía no hay usuarios")
                .font(.title2.bold())
            Text("Abre GestioFoto en el Mac principal y crea allí el primer usuario titular. Después pulsa «Reintentar».")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .foregroundStyle(.secondary)
            Button("Reintentar") { Task { await estado.reintentar() } }
                .keyboardShortcut(.defaultAction)
        }
        .padding(32)
    }
}
