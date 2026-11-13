import Domain
import Persistence
import SwiftUI

@MainActor
@Observable
final class ModeloUsuarios {
    var usuarios: [Usuario] = []
    var error: String?

    func cargar(_ estado: EstadoApp) async {
        guard let db = estado.db else { return }
        do {
            usuarios = try await RepositorioUsuarios(db: db).todos(incluirInactivos: true)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func crear(_ estado: EstadoApp, nombre: String, rol: Rol, pin: String) async -> Bool {
        guard let db = estado.db, let yo = estado.usuario else { return false }
        do {
            _ = try await RepositorioUsuarios(db: db).crear(nombre: nombre, rol: rol, pin: pin, por: yo.id)
            await cargar(estado)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// Guarda con control de versión. Si otra persona lo cambió, recarga y avisa.
    func guardar(_ estado: EstadoApp, _ u: Usuario) async -> Bool {
        guard let db = estado.db, let yo = estado.usuario else { return false }
        do {
            let guardado = try await RepositorioUsuarios(db: db).guardar(u, por: yo.id)
            estado.actualizarUsuarioActual(guardado)
            await cargar(estado)
            return true
        } catch ErrorBaseDeDatos.conflictoVersion {
            await cargar(estado)
            let actual = usuarios.first { $0.id == u.id }
            self.error = """
                Otra persona ha cambiado este usuario mientras lo editabas. \
                Ahora tiene: \(actual?.nombre ?? "—"), \(actual?.rol.nombreVisible ?? "—"), \
                \(actual?.activo == true ? "activo" : "inactivo"). Revisa y vuelve a guardar.
                """
            return false
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func cambiarPIN(_ estado: EstadoApp, usuario: Int64, pin: String) async -> Bool {
        guard let db = estado.db, let yo = estado.usuario else { return false }
        do {
            try await RepositorioUsuarios(db: db).establecerPIN(usuario: usuario, pin: pin, por: yo.id)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

struct UsuariosView: View {
    @Environment(EstadoApp.self) private var estado
    @State private var modelo = ModeloUsuarios()
    @State private var editando: Usuario?
    @State private var cambiandoPIN: Usuario?
    @State private var creando = false

    var body: some View {
        VStack(alignment: .leading) {
            Table(modelo.usuarios) {
                TableColumn("Nombre", value: \.nombre)
                TableColumn("Rol") { u in Text(u.rol.nombreVisible) }
                TableColumn("Estado") { u in
                    if !u.activo {
                        Text("Inactivo").foregroundStyle(.secondary)
                    } else if u.estaBloqueado(en: .now) {
                        Text("Bloqueado por PIN").foregroundStyle(.orange)
                    } else {
                        Text("Activo")
                    }
                }
                TableColumn("Último acceso") { u in
                    Text(u.ultimoAcceso?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                }
                TableColumn("") { u in
                    HStack {
                        if estado.esTitular {
                            Button("Editar") { editando = u }
                        }
                        if estado.esTitular || u.id == estado.usuario?.id {
                            Button("Cambiar PIN") { cambiandoPIN = u }
                        }
                    }
                }
            }
            HStack {
                if !estado.esTitular {
                    Text("Solo el titular puede añadir o editar usuarios.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Nuevo usuario…") { creando = true }
                    .disabled(!estado.esTitular)
            }
        }
        .task { await modelo.cargar(estado) }
        .sheet(isPresented: $creando) {
            NuevoUsuarioSheet(modelo: modelo)
        }
        .sheet(item: $editando) { u in
            EditarUsuarioSheet(modelo: modelo, usuario: u)
        }
        .sheet(item: $cambiandoPIN) { u in
            CambiarPINSheet(modelo: modelo, usuario: u)
        }
        .alert("No se pudo guardar", isPresented: Binding(
            get: { modelo.error != nil }, set: { if !$0 { modelo.error = nil } })
        ) {
            Button("Aceptar") { modelo.error = nil }
        } message: {
            Text(modelo.error ?? "")
        }
    }
}

private struct NuevoUsuarioSheet: View {
    @Environment(EstadoApp.self) private var estado
    @Environment(\.dismiss) private var cerrar
    let modelo: ModeloUsuarios
    @State private var nombre = ""
    @State private var rol: Rol = .titular
    @State private var pin = ""
    @State private var repetido = ""

    var body: some View {
        Form {
            TextField("Nombre", text: $nombre)
            Picker("Rol", selection: $rol) {
                ForEach(Rol.allCases, id: \.self) { Text($0.nombreVisible).tag($0) }
            }
            SecureField("PIN (4 a 6 cifras)", text: $pin)
            SecureField("Repite el PIN", text: $repetido)
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { cerrar() }
                Button("Crear") {
                    Task {
                        if await modelo.crear(estado, nombre: nombre.trimmingCharacters(in: .whitespaces),
                                              rol: rol, pin: pin) {
                            cerrar()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(nombre.trimmingCharacters(in: .whitespaces).isEmpty || !PIN.esValido(pin) || pin != repetido)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .padding()
    }
}

private struct EditarUsuarioSheet: View {
    @Environment(EstadoApp.self) private var estado
    @Environment(\.dismiss) private var cerrar
    let modelo: ModeloUsuarios
    @State var usuario: Usuario

    var body: some View {
        Form {
            TextField("Nombre", text: $usuario.nombre)
            Picker("Rol", selection: $usuario.rol) {
                ForEach(Rol.allCases, id: \.self) { Text($0.nombreVisible).tag($0) }
            }
            Toggle("Activo (puede iniciar sesión)", isOn: $usuario.activo)
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { cerrar() }
                Button("Guardar") {
                    Task {
                        if await modelo.guardar(estado, usuario) { cerrar() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(usuario.nombre.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .padding()
    }
}

private struct CambiarPINSheet: View {
    @Environment(EstadoApp.self) private var estado
    @Environment(\.dismiss) private var cerrar
    let modelo: ModeloUsuarios
    let usuario: Usuario
    @State private var pin = ""
    @State private var repetido = ""

    var body: some View {
        Form {
            Text("Nuevo PIN para \(usuario.nombre)").font(.headline)
            SecureField("PIN (4 a 6 cifras)", text: $pin)
            SecureField("Repite el PIN", text: $repetido)
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { cerrar() }
                Button("Cambiar") {
                    Task {
                        if await modelo.cambiarPIN(estado, usuario: usuario.id, pin: pin) { cerrar() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!PIN.esValido(pin) || pin != repetido)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .padding()
    }
}
