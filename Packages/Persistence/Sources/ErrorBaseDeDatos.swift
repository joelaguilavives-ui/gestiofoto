import Foundation
import PostgresNIO

public enum ErrorBaseDeDatos: Error, LocalizedError, Equatable {
    /// Otra persona guardó el registro antes (número de versión distinto).
    case conflictoVersion
    /// No se encuentra el registro.
    case noEncontrado
    /// El servidor rechazó la operación (regla, permiso, restricción…).
    case servidor(mensaje: String, codigo: String?)
    /// No hay conexión con el Mac principal.
    case sinConexion(detalle: String)
    /// Una migración ya aplicada se ha modificado (nunca se edita una aplicada).
    case migracionModificada(version: Int)
    /// Ficheros de migración mal numerados.
    case migracionesInvalidas(String)

    public var errorDescription: String? {
        switch self {
        case .conflictoVersion:
            "Otra persona ha guardado cambios en este registro mientras lo editabas. Revisa sus cambios antes de volver a guardar."
        case .noEncontrado:
            "El registro ya no existe."
        case .servidor(let mensaje, _):
            mensaje
        case .sinConexion:
            "Sin conexión con el Mac principal."
        case .migracionModificada(let version):
            "La migración \(version) ya aplicada ha cambiado. No se puede continuar."
        case .migracionesInvalidas(let detalle):
            "Migraciones no válidas: \(detalle)"
        }
    }

    /// Código SQLSTATE de permiso denegado.
    public var esPermisoDenegado: Bool {
        if case .servidor(_, let codigo) = self { return codigo == "42501" }
        return false
    }

    /// Convierte los errores de PostgresNIO en errores de la app.
    public static func traducir(_ error: Error) -> Error {
        if error is ErrorBaseDeDatos || error is CancellationError { return error }
        if let psql = error as? PSQLError {
            if let mensaje = psql.serverInfo?[.message] {
                return ErrorBaseDeDatos.servidor(mensaje: mensaje, codigo: psql.serverInfo?[.sqlState])
            }
            return ErrorBaseDeDatos.sinConexion(detalle: String(describing: psql.code))
        }
        return ErrorBaseDeDatos.sinConexion(detalle: String(describing: error))
    }
}
