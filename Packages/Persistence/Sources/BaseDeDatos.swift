import Domain
import Foundation
import Logging
import NIOSSL
import PostgresNIO

/// Conexión con el PostgreSQL del Mac principal.
///
/// Uso: crear, lanzar `ejecutar()` en una tarea que viva mientras se use, y
/// trabajar con `leer` o `transaccion`. Al cancelar esa tarea se cierran las
/// conexiones.
public final class BaseDeDatos: Sendable {
    public let client: PostgresClient
    public let logger: Logger

    public init(
        configuracion: ConfiguracionConexion,
        usuario: String,
        contrasena: String,
        logger: Logger = Logger(label: "gestiofoto.db")
    ) throws {
        let tls: PostgresClient.Configuration.TLS =
            try Self.configuracionTLS(configuracion).map { .require($0) } ?? .disable
        var pg = PostgresClient.Configuration(
            host: configuracion.servidor,
            port: configuracion.puerto,
            username: usuario,
            password: contrasena,
            database: configuracion.baseDeDatos,
            tls: tls
        )
        pg.options.connectTimeout = .seconds(5)
        self.client = PostgresClient(configuration: pg, backgroundLogger: logger)
        self.logger = logger
    }

    /// nil = sin TLS (solo pruebas automáticas).
    static func configuracionTLS(_ c: ConfiguracionConexion) throws -> TLSConfiguration? {
        switch c.modoTLS {
        case .desactivado:
            return nil
        case .cifrarSinVerificar:
            var tls = TLSConfiguration.makeClientConfiguration()
            tls.certificateVerification = .none
            return tls
        case .verificar:
            var tls = TLSConfiguration.makeClientConfiguration()
            let certificados = try NIOSSLCertificate.fromPEMFile(c.rutaCertificado ?? "")
            tls.trustRoots = .certificates(certificados)
            // El certificado es propio de la tienda: se confía solo en él, sin
            // exigir que el nombre coincida (el Mac puede cambiar de nombre).
            tls.certificateVerification = .noHostnameVerification
            return tls
        }
    }

    /// Prueba unos datos de conexión con una conexión directa (sin grupo de
    /// conexiones), para dar el error exacto: contraseña, nombre de red, TLS…
    /// Devuelve nil si todo va bien, o el motivo del fallo.
    public static func probar(
        _ configuracion: ConfiguracionConexion, usuario: String, contrasena: String,
        logger: Logger = Logger(label: "gestiofoto.db.prueba")
    ) async -> String? {
        do {
            let tls: PostgresConnection.Configuration.TLS
            if let configuracionTLS = try configuracionTLS(configuracion) {
                tls = .require(try NIOSSLContext(configuration: configuracionTLS))
            } else {
                tls = .disable
            }
            var pg = PostgresConnection.Configuration(
                host: configuracion.servidor,
                port: configuracion.puerto,
                username: usuario,
                password: contrasena,
                database: configuracion.baseDeDatos,
                tls: tls
            )
            pg.options.connectTimeout = .seconds(8)
            let conexion = try await PostgresConnection.connect(configuration: pg, id: 1, logger: logger)
            defer { Task { try? await conexion.close() } }
            _ = try await conexion.ejecutar("SELECT 1", logger)
            return nil
        } catch {
            switch ErrorBaseDeDatos.traducir(error) {
            case ErrorBaseDeDatos.servidor(let mensaje, _):
                return mensaje
            case ErrorBaseDeDatos.sinConexion(let detalle):
                return "No responde (\(detalle)). Comprueba el nombre de red y que el Mac principal está encendido."
            case let otro:
                return otro.localizedDescription
            }
        }
    }

    /// Mantiene vivas las conexiones. Vuelve cuando se cancela la tarea.
    public func ejecutar() async {
        await client.run()
    }

    /// Lectura u operación sin firmar (consultas, inicio de sesión).
    public func leer<T: Sendable>(
        _ cuerpo: (PostgresConnection, Logger) async throws -> T
    ) async throws -> T {
        do {
            return try await client.withConnection { conexion in
                try await cuerpo(conexion, logger)
            }
        } catch {
            throw ErrorBaseDeDatos.traducir(error)
        }
    }

    /// Transacción firmada por un usuario: o se guarda todo o nada (PDF §7).
    /// `usuario` nil solo para el inicio de sesión, que firma por sí mismo.
    public func transaccion<T: Sendable>(
        usuario: Int64?,
        _ cuerpo: (PostgresConnection, Logger) async throws -> T
    ) async throws -> T {
        try await leer { conexion, logger in
            try await conexion.ejecutar("BEGIN", logger)
            do {
                if let usuario {
                    try await conexion.ejecutar(
                        "SELECT set_config('app.usuario_id', \(String(usuario)), true)", logger)
                }
                let resultado = try await cuerpo(conexion, logger)
                try await conexion.ejecutar("COMMIT", logger)
                return resultado
            } catch {
                _ = try? await conexion.ejecutar("ROLLBACK", logger)
                throw error
            }
        }
    }

    /// `true` si el servidor responde en menos de `segundos`.
    public func comprobarConexion(segundos: Double = 5) async -> Bool {
        do {
            return try await conLimiteDeTiempo(segundos) { [self] in
                try await self.leer { conexion, logger in
                    let filas = try await conexion.ejecutar("SELECT 1", logger)
                    return filas.count == 1
                }
            }
        } catch {
            return false
        }
    }
}

extension PostgresConnection {
    /// Ejecuta una sentencia y devuelve todas sus filas.
    @discardableResult
    public func ejecutar(_ consulta: PostgresQuery, _ logger: Logger) async throws -> [PostgresRow] {
        try await query(consulta, logger: logger).collect()
    }
}

/// Lanza `operacion` y falla con `.sinConexion` si tarda más de `segundos`.
public func conLimiteDeTiempo<T: Sendable>(
    _ segundos: Double,
    _ operacion: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { grupo in
        grupo.addTask { try await operacion() }
        grupo.addTask {
            try await Task.sleep(for: .seconds(segundos))
            throw ErrorBaseDeDatos.sinConexion(detalle: "Tiempo de espera agotado")
        }
        defer { grupo.cancelAll() }
        guard let resultado = try await grupo.next() else {
            throw ErrorBaseDeDatos.sinConexion(detalle: "Sin respuesta")
        }
        return resultado
    }
}
