import Domain
import Foundation

/// Datos de conexión de este Mac (sin contraseñas, que van al Llavero).
enum AlmacenConexion {
    private static let clave = "conexion"

    static func cargar() -> ConfiguracionConexion? {
        guard let datos = UserDefaults.standard.data(forKey: clave) else { return nil }
        return try? JSONDecoder().decode(ConfiguracionConexion.self, from: datos)
    }

    static func guardar(_ c: ConfiguracionConexion) {
        UserDefaults.standard.set(try? JSONEncoder().encode(c), forKey: clave)
    }

    static func borrar() {
        UserDefaults.standard.removeObject(forKey: clave)
    }

    /// Carpeta propia de la app (certificado del servidor, scripts de copias).
    static var carpetaApp: URL {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/GestioFoto", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Copia el certificado elegido a la carpeta de la app y devuelve su ruta.
    static func importarCertificado(desde origen: URL) throws -> String {
        let destino = carpetaApp.appendingPathComponent("servidor.crt")
        try? FileManager.default.removeItem(at: destino)
        try FileManager.default.copyItem(at: origen, to: destino)
        return destino.path
    }
}
