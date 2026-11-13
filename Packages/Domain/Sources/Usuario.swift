import Foundation

/// Rol de un usuario. Por ahora los dos usuarios son titulares; «dependiente»
/// queda preparado para el futuro (PDF §7).
public enum Rol: String, Sendable, CaseIterable, Codable {
    case titular
    case dependiente

    public var nombreVisible: String {
        switch self {
        case .titular: "Titular"
        case .dependiente: "Dependiente"
        }
    }
}

public struct Usuario: Sendable, Hashable, Identifiable {
    public let id: Int64
    public var nombre: String
    public var rol: Rol
    public var activo: Bool
    public var bloqueadoHasta: Date?
    public var ultimoAcceso: Date?
    /// Número de versión del registro (edición simultánea).
    public var version: Int

    public init(
        id: Int64, nombre: String, rol: Rol, activo: Bool,
        bloqueadoHasta: Date? = nil, ultimoAcceso: Date? = nil, version: Int
    ) {
        self.id = id
        self.nombre = nombre
        self.rol = rol
        self.activo = activo
        self.bloqueadoHasta = bloqueadoHasta
        self.ultimoAcceso = ultimoAcceso
        self.version = version
    }

    public var esTitular: Bool { rol == .titular }

    /// Tras 5 PIN fallidos seguidos la base de datos bloquea al usuario 5 minutos.
    public func estaBloqueado(en fecha: Date) -> Bool {
        guard let bloqueadoHasta else { return false }
        return bloqueadoHasta > fecha
    }
}

/// PIN de acceso: entre 4 y 6 cifras (misma regla que `validar_formato_pin` en SQL).
public enum PIN {
    public static let longitud = 4...6

    public static func esValido(_ pin: String) -> Bool {
        longitud.contains(pin.count) && pin.unicodeScalars.allSatisfy { ("0"..."9").contains($0) }
    }
}
