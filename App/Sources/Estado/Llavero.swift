import Foundation
import Security

/// Contraseñas de la base de datos en el Llavero de macOS (PDF §7).
enum Llavero {
    enum Cuenta: String {
        case app = "gestiofoto_app"
        case propietario = "gestiofoto_owner"
    }

    private static let servicio = "es.gestiofoto.basededatos"

    enum ErrorLlavero: Error, LocalizedError {
        case estado(OSStatus)
        var errorDescription: String? {
            if case .estado(let codigo) = self {
                let detalle = SecCopyErrorMessageString(codigo, nil) as String? ?? "\(codigo)"
                return "No se pudo guardar la contraseña en el Llavero: \(detalle)"
            }
            return nil
        }
    }

    private static func consulta(_ cuenta: Cuenta) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servicio,
            kSecAttrAccount as String: cuenta.rawValue,
        ]
    }

    static func guardar(_ contrasena: String, en cuenta: Cuenta) throws {
        SecItemDelete(consulta(cuenta) as CFDictionary)
        var atributos = consulta(cuenta)
        atributos[kSecValueData as String] = Data(contrasena.utf8)
        atributos[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let estado = SecItemAdd(atributos as CFDictionary, nil)
        guard estado == errSecSuccess else { throw ErrorLlavero.estado(estado) }
    }

    static func leer(_ cuenta: Cuenta) -> String? {
        var q = consulta(cuenta)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var resultado: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &resultado) == errSecSuccess,
              let datos = resultado as? Data
        else { return nil }
        return String(data: datos, encoding: .utf8)
    }

    static func borrar(_ cuenta: Cuenta) {
        SecItemDelete(consulta(cuenta) as CFDictionary)
    }
}
