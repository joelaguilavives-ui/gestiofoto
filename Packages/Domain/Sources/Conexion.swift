import Foundation

/// Datos para conectar con la base de datos del Mac principal. Se guardan en
/// cada Mac (las contraseñas, en el Llavero; aquí no).
public struct ConfiguracionConexion: Codable, Sendable, Equatable {
    public enum ModoTLS: String, Codable, Sendable, CaseIterable {
        /// Cifrado y comprobando el certificado del Mac principal (recomendado).
        case verificar
        /// Cifrado sin comprobar el certificado.
        case cifrarSinVerificar
        /// Sin cifrar. Solo para pruebas automáticas; la interfaz no lo ofrece.
        case desactivado
    }

    /// Nombre de red del Mac principal, p. ej. `mac-tienda.local`.
    public var servidor: String
    public var puerto: Int
    public var baseDeDatos: String
    public var usuarioApp: String
    public var usuarioPropietario: String
    /// El Mac principal aplica las migraciones y hace las copias.
    public var esMacPrincipal: Bool
    public var modoTLS: ModoTLS
    /// Certificado del servidor (PEM) para `verificar`.
    public var rutaCertificado: String?

    public init(
        servidor: String,
        puerto: Int = 5432,
        baseDeDatos: String = "gestiofoto",
        usuarioApp: String = "gestiofoto_app",
        usuarioPropietario: String = "gestiofoto_owner",
        esMacPrincipal: Bool,
        modoTLS: ModoTLS = .cifrarSinVerificar,
        rutaCertificado: String? = nil
    ) {
        self.servidor = servidor
        self.puerto = puerto
        self.baseDeDatos = baseDeDatos
        self.usuarioApp = usuarioApp
        self.usuarioPropietario = usuarioPropietario
        self.esMacPrincipal = esMacPrincipal
        self.modoTLS = modoTLS
        self.rutaCertificado = rutaCertificado
    }

    public var esValida: Bool {
        !servidor.isEmpty
            && (1...65535).contains(puerto)
            && !baseDeDatos.isEmpty
            && (modoTLS != .verificar || !(rutaCertificado ?? "").isEmpty)
    }

    /// El Mac principal se localiza por su nombre de red, no por IP (PDF §2).
    /// «mac-tienda» → «mac-tienda.local». Se respetan `localhost`, IPs y nombres
    /// que ya llevan dominio.
    public static func normalizarServidor(_ texto: String) -> String {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !limpio.isEmpty else { return "" }
        if limpio == "localhost" || limpio.contains(".") || limpio.contains(":") {
            return limpio
        }
        return limpio + ".local"
    }
}
