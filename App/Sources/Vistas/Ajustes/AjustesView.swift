import SwiftUI

/// Ajustes de la fase 1. Formas de pago, tipos de trabajo, conceptos de caja,
/// tarifa, carpetas y plantillas llegan con sus fases.
struct AjustesView: View {
    enum Pestana: Hashable { case tienda, usuarios, copias, auditoria, conexion }
    @State private var pestana: Pestana = .tienda

    var body: some View {
        TabView(selection: $pestana) {
            TiendaView()
                .tabItem { Label("Tienda", systemImage: "storefront") }
                .tag(Pestana.tienda)
            UsuariosView()
                .tabItem { Label("Usuarios", systemImage: "person.2") }
                .tag(Pestana.usuarios)
            CopiasView()
                .tabItem { Label("Copias", systemImage: "externaldrive") }
                .tag(Pestana.copias)
            AuditoriaView()
                .tabItem { Label("Auditoría", systemImage: "clock.arrow.circlepath") }
                .tag(Pestana.auditoria)
            ConexionAjustesView()
                .tabItem { Label("Conexión", systemImage: "network") }
                .tag(Pestana.conexion)
        }
        .padding()
        .navigationTitle("Ajustes")
    }
}

struct ConexionAjustesView: View {
    @Environment(EstadoApp.self) private var estado

    var body: some View {
        Form {
            if let c = estado.conexion {
                LabeledContent("Mac principal", value: c.servidor)
                LabeledContent("Puerto", value: String(c.puerto))
                LabeledContent("Base de datos", value: c.baseDeDatos)
                LabeledContent("Este Mac", value: c.esMacPrincipal ? "Principal" : "Secundario")
                LabeledContent("Cifrado", value: c.modoTLS == .verificar
                               ? "TLS comprobando el certificado" : "TLS sin comprobar el certificado")
            }
            Section {
                Button("Cambiar la conexión…") { estado.cambiarConexion() }
            } footer: {
                Text("Se cierra la sesión y se vuelven a pedir el nombre de red y las contraseñas.")
            }
        }
        .formStyle(.grouped)
    }
}
