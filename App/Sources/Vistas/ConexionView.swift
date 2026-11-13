import AppKit
import Domain
import SwiftUI

/// Primera pantalla en cada Mac: dónde está la base de datos y con qué
/// contraseñas (que se guardan en el Llavero).
struct ConexionView: View {
    @Environment(EstadoApp.self) private var estado

    @State private var servidor = ""
    @State private var puerto = 5432
    @State private var esMacPrincipal = false
    @State private var verificarCertificado = true
    @State private var rutaCertificado: String?
    @State private var contrasenaApp = ""
    @State private var contrasenaPropietario = ""
    @State private var probando = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Text("Conexión con el Mac principal")
                    .font(.title2.bold())
                Text("Los datos de la tienda viven en el Mac principal. Este Mac se conecta a él por la red local. Las contraseñas te las dio el script de instalación y se guardan en el Llavero de este Mac.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Este es el Mac principal (el que tiene la base de datos)", isOn: $esMacPrincipal)
                TextField("Nombre de red del Mac principal", text: $servidor, prompt: Text("mac-tienda.local"))
                TextField("Puerto", value: $puerto, format: .number.grouping(.never))
            }

            Section("Cifrado") {
                Toggle("Comprobar el certificado del Mac principal (recomendado)", isOn: $verificarCertificado)
                if verificarCertificado {
                    HStack {
                        Text(rutaCertificado.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Ningún certificado elegido")
                            .foregroundStyle(rutaCertificado == nil ? .secondary : .primary)
                        Spacer()
                        Button("Elegir server.crt…", action: elegirCertificado)
                    }
                } else {
                    Text("La conexión va cifrada igualmente, pero sin comprobar que el servidor es el de la tienda.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Contraseñas") {
                SecureField("Contraseña de gestiofoto_app", text: $contrasenaApp)
                if esMacPrincipal {
                    SecureField("Contraseña de gestiofoto_owner", text: $contrasenaPropietario)
                }
            }

            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            Section {
                HStack {
                    Spacer()
                    if probando { ProgressView().controlSize(.small) }
                    Button("Conectar", action: conectar)
                        .keyboardShortcut(.defaultAction)
                        .disabled(probando || !esValida)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 620)
        .padding()
        .onAppear(perform: cargar)
    }

    private var configuracion: ConfiguracionConexion {
        ConfiguracionConexion(
            servidor: ConfiguracionConexion.normalizarServidor(servidor),
            puerto: puerto,
            esMacPrincipal: esMacPrincipal,
            modoTLS: verificarCertificado ? .verificar : .cifrarSinVerificar,
            rutaCertificado: verificarCertificado ? rutaCertificado : nil)
    }

    private var esValida: Bool {
        configuracion.esValida && !contrasenaApp.isEmpty
            && (!esMacPrincipal || !contrasenaPropietario.isEmpty)
    }

    private func cargar() {
        guard let c = AlmacenConexion.cargar() else { return }
        servidor = c.servidor
        puerto = c.puerto
        esMacPrincipal = c.esMacPrincipal
        verificarCertificado = c.modoTLS == .verificar
        rutaCertificado = c.rutaCertificado
    }

    private func elegirCertificado() {
        let panel = NSOpenPanel()
        panel.title = "Certificado del Mac principal (server.crt)"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            rutaCertificado = try AlmacenConexion.importarCertificado(desde: url)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func conectar() {
        probando = true
        error = nil
        let c = configuracion
        Task {
            error = await estado.guardarConexion(
                c, contrasenaApp: contrasenaApp,
                contrasenaPropietario: esMacPrincipal ? contrasenaPropietario : nil)
            probando = false
        }
    }
}
