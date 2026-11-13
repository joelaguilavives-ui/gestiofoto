import Domain
import Persistence
import SwiftUI

// MARK: - Inicio de sesión

@MainActor
@Observable
final class ModeloLogin {
    var usuarios: [Usuario] = []
    var seleccionado: Int64?
    var pin = ""
    var mensaje: String?
    var trabajando = false

    func cargar(_ estado: EstadoApp) async {
        guard let db = estado.db else { return }
        do {
            usuarios = try await RepositorioUsuarios(db: db).todos()
            seleccionado = estado.usuarioBloqueado ?? seleccionado ?? usuarios.first?.id
        } catch {
            mensaje = error.localizedDescription
        }
    }

    func entrar(_ estado: EstadoApp) async {
        guard let db = estado.db, let id = seleccionado else { return }
        guard PIN.esValido(pin) else {
            mensaje = "El PIN tiene entre 4 y 6 cifras."
            return
        }
        trabajando = true
        defer { trabajando = false }
        let repositorio = RepositorioUsuarios(db: db)
        do {
            if try await repositorio.verificarPIN(usuario: id, pin: pin) {
                estado.entrar(try await repositorio.usuario(id: id))
                pin = ""
                mensaje = nil
            } else {
                pin = ""
                let u = try? await repositorio.usuario(id: id)
                if let hasta = u?.bloqueadoHasta, u?.estaBloqueado(en: .now) == true {
                    mensaje = "Demasiados intentos. Vuelve a probar a las \(hasta.formatted(date: .omitted, time: .shortened))."
                } else {
                    mensaje = "PIN incorrecto."
                }
            }
        } catch {
            mensaje = error.localizedDescription
        }
    }
}

struct LoginView: View {
    @Environment(EstadoApp.self) private var estado
    @State private var modelo = ModeloLogin()
    @FocusState private var pinConFoco: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.aperture")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text(estado.usuarioBloqueado == nil ? "GestioFoto" : "Sesión bloqueada")
                .font(.largeTitle.bold())

            Form {
                Picker("Usuario", selection: $modelo.seleccionado) {
                    ForEach(modelo.usuarios) { u in
                        Text(u.nombre).tag(Optional(u.id))
                    }
                }
                SecureField("PIN", text: $modelo.pin)
                    .focused($pinConFoco)
                    .onSubmit { Task { await modelo.entrar(estado) } }
            }
            .formStyle(.grouped)
            .frame(width: 360)

            if let mensaje = modelo.mensaje {
                Text(mensaje).foregroundStyle(.red)
            }

            Button("Entrar") { Task { await modelo.entrar(estado) } }
                .keyboardShortcut(.defaultAction)
                .disabled(modelo.trabajando || modelo.seleccionado == nil)

            Button("Cambiar la conexión con el Mac principal…") { estado.cambiarConexion() }
                .buttonStyle(.link)
                .font(.footnote)
        }
        .padding(40)
        .task {
            await modelo.cargar(estado)
            pinConFoco = true
        }
    }
}

// MARK: - Primer titular

struct PrimerTitularView: View {
    @Environment(EstadoApp.self) private var estado
    @State private var nombre = ""
    @State private var pin = ""
    @State private var repetido = ""
    @State private var error: String?
    @State private var trabajando = false

    private var valido: Bool {
        !nombre.trimmingCharacters(in: .whitespaces).isEmpty && PIN.esValido(pin) && pin == repetido
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Primer usuario")
                .font(.largeTitle.bold())
            Text("La base de datos está lista. Crea el usuario del titular; después podrás añadir más en Ajustes → Usuarios.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            Form {
                TextField("Nombre", text: $nombre)
                SecureField("PIN (4 a 6 cifras)", text: $pin)
                SecureField("Repite el PIN", text: $repetido)
            }
            .formStyle(.grouped)
            .frame(width: 380)
            if !repetido.isEmpty && pin != repetido {
                Text("Los PIN no coinciden.").foregroundStyle(.red)
            }
            if let error {
                Text(error).foregroundStyle(.red)
            }
            Button("Crear y entrar") {
                trabajando = true
                Task {
                    do {
                        try await estado.crearPrimerTitular(
                            nombre: nombre.trimmingCharacters(in: .whitespaces), pin: pin)
                    } catch {
                        self.error = error.localizedDescription
                    }
                    trabajando = false
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!valido || trabajando)
        }
        .padding(40)
    }
}
