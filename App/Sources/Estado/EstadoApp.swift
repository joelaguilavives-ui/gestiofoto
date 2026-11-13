import AppKit
import Domain
import Foundation
import Integrations
import Observation
import Persistence

/// Estado global de la app: conexión, sesión del usuario, bloqueo por
/// inactividad y vigilancia de la conexión con el Mac principal.
@MainActor
@Observable
final class EstadoApp {
    enum Fase: Equatable {
        case iniciando
        case configurarConexion
        case preparando(String)
        case error(String)
        /// Mac principal sin usuarios: crear el primer titular.
        case primerTitular
        /// Segundo Mac sin usuarios: hay que crearlos en el principal.
        case esperandoTitular
        case login
        case trabajando
    }

    enum ErrorApp: Error, LocalizedError {
        case sinPropietario
        case sinConexion

        var errorDescription: String? {
            switch self {
            case .sinPropietario: "Esta operación solo se puede hacer en el Mac principal."
            case .sinConexion: "Sin conexión con el Mac principal."
            }
        }
    }

    private(set) var fase: Fase = .iniciando
    private(set) var conexion: ConfiguracionConexion?
    private(set) var usuario: Usuario?
    /// Al bloquear la sesión se recuerda quién estaba, para proponerlo al volver.
    private(set) var usuarioBloqueado: Int64?
    private(set) var configuracion = ValoresConfiguracion()
    /// La conexión se ha perdido: la interfaz no deja trabajar hasta que vuelva.
    private(set) var sinConexion = false
    private(set) var db: BaseDeDatos?

    @ObservationIgnored private var tareaCliente: Task<Void, Never>?
    @ObservationIgnored private var tareaMonitor: Task<Void, Never>?
    @ObservationIgnored private var tareaInactividad: Task<Void, Never>?
    @ObservationIgnored private var ultimaActividad = Date()
    @ObservationIgnored private var monitorEventos: Any?

    var esMacPrincipal: Bool { conexion?.esMacPrincipal ?? false }
    var esTitular: Bool { usuario?.esTitular ?? false }

    // MARK: - Arranque y conexión

    func arrancar() async {
        instalarMonitorActividad()
        guard let c = AlmacenConexion.cargar(), c.esValida, let contrasena = Llavero.leer(.app) else {
            fase = .configurarConexion
            return
        }
        await conectar(c, contrasenaApp: contrasena)
    }

    /// Prueba los datos de conexión y, si funcionan, los guarda y conecta.
    /// Devuelve el motivo del error, o nil.
    func guardarConexion(
        _ c: ConfiguracionConexion, contrasenaApp: String, contrasenaPropietario: String?
    ) async -> String? {
        if let fallo = await BaseDeDatos.probar(c, usuario: c.usuarioApp, contrasena: contrasenaApp) {
            return "Usuario \(c.usuarioApp): \(fallo)"
        }
        if c.esMacPrincipal {
            guard let propietario = contrasenaPropietario, !propietario.isEmpty else {
                return "En el Mac principal hace falta la contraseña de \(c.usuarioPropietario)."
            }
            if let fallo = await BaseDeDatos.probar(c, usuario: c.usuarioPropietario, contrasena: propietario) {
                return "Usuario \(c.usuarioPropietario): \(fallo)"
            }
        }
        do {
            try Llavero.guardar(contrasenaApp, en: .app)
            if c.esMacPrincipal, let propietario = contrasenaPropietario {
                try Llavero.guardar(propietario, en: .propietario)
            } else {
                Llavero.borrar(.propietario)
            }
        } catch {
            return error.localizedDescription
        }
        AlmacenConexion.guardar(c)
        await conectar(c, contrasenaApp: contrasenaApp)
        return nil
    }

    func cambiarConexion() {
        detener()
        usuario = nil
        usuarioBloqueado = nil
        fase = .configurarConexion
    }

    func reintentar() async {
        await arrancar()
    }

    private func conectar(_ c: ConfiguracionConexion, contrasenaApp: String) async {
        detener()
        conexion = c
        fase = .preparando("Conectando con el Mac principal…")

        let nueva: BaseDeDatos
        do {
            nueva = try BaseDeDatos(configuracion: c, usuario: c.usuarioApp, contrasena: contrasenaApp)
        } catch {
            fase = .error("No se pudo preparar la conexión: \(error.localizedDescription)")
            return
        }
        db = nueva
        tareaCliente = Task.detached { await nueva.ejecutar() }

        if c.esMacPrincipal {
            fase = .preparando("Actualizando la base de datos…")
            do {
                try await migrar()
            } catch {
                fase = .error("No se pudo actualizar la base de datos.\n\(error.localizedDescription)")
                return
            }
        }

        guard await nueva.comprobarConexion() else {
            fase = .error("Sin conexión con el Mac principal (\(c.servidor)). Comprueba que está encendido, con Postgres.app abierto, y en la misma red.")
            return
        }
        do {
            configuracion = try await RepositorioConfiguracion(db: nueva).valores()
            let hayUsuarios = try await RepositorioUsuarios(db: nueva).hayUsuarios()
            if hayUsuarios {
                fase = .login
            } else {
                fase = c.esMacPrincipal ? .primerTitular : .esperandoTitular
            }
        } catch {
            fase = .error(error.localizedDescription)
            return
        }
        iniciarMonitor()
        iniciarControlInactividad()
    }

    /// Aplica las migraciones incluidas en la app (solo Mac principal).
    private func migrar() async throws {
        guard let carpeta = Bundle.main.url(forResource: "migrations", withExtension: nil) else {
            throw ErrorBaseDeDatos.migracionesInvalidas("la app no incluye la carpeta de migraciones")
        }
        let migraciones = try Migracion.cargar(desde: carpeta)
        let seed = Bundle.main.url(forResource: "seed", withExtension: "sql", subdirectory: "seed")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        try await conPropietario { db in
            _ = try await EjecutorMigraciones(db: db).aplicar(migraciones, seed: seed)
        }
    }

    /// Ejecuta algo con la conexión del propietario (solo en el Mac principal).
    func conPropietario<T: Sendable>(
        _ cuerpo: @Sendable (BaseDeDatos) async throws -> T
    ) async throws -> T {
        guard let c = conexion, c.esMacPrincipal, let contrasena = Llavero.leer(.propietario) else {
            throw ErrorApp.sinPropietario
        }
        let propietario = try BaseDeDatos(configuracion: c, usuario: c.usuarioPropietario, contrasena: contrasena)
        return try await withThrowingTaskGroup(of: Void.self) { grupo in
            grupo.addTask { await propietario.ejecutar() }
            defer { grupo.cancelAll() }
            return try await cuerpo(propietario)
        }
    }

    private func detener() {
        tareaMonitor?.cancel()
        tareaInactividad?.cancel()
        tareaCliente?.cancel()
        tareaMonitor = nil
        tareaInactividad = nil
        tareaCliente = nil
        db = nil
        sinConexion = false
    }

    // MARK: - Sesión

    func crearPrimerTitular(nombre: String, pin: String) async throws {
        let id = try await conPropietario { propietario in
            try await RepositorioUsuarios(db: propietario).crear(nombre: nombre, rol: .titular, pin: pin, por: 1)
        }
        guard let db else { throw ErrorApp.sinConexion }
        let repositorio = RepositorioUsuarios(db: db)
        _ = try await repositorio.verificarPIN(usuario: id, pin: pin)
        entrar(try await repositorio.usuario(id: id))
    }

    func entrar(_ u: Usuario) {
        usuario = u
        usuarioBloqueado = nil
        ultimaActividad = .now
        fase = .trabajando
    }

    func bloquear() {
        guard let u = usuario else { return }
        usuarioBloqueado = u.id
        usuario = nil
        fase = .login
    }

    func cerrarSesion() {
        usuario = nil
        usuarioBloqueado = nil
        fase = .login
    }

    /// Tras editar usuarios, refresca el de la sesión (nombre, rol).
    func actualizarUsuarioActual(_ u: Usuario) {
        guard u.id == usuario?.id else { return }
        if u.activo {
            usuario = u
        } else {
            cerrarSesion()
        }
    }

    func recargarConfiguracion() async {
        guard let db else { return }
        if let valores = try? await RepositorioConfiguracion(db: db).valores() {
            configuracion = valores
        }
    }

    // MARK: - Vigilancia

    /// Cada 5 s comprueba la conexión; tras 2 fallos seguidos bloquea la interfaz
    /// con «Sin conexión con el Mac principal» (PDF §2).
    private func iniciarMonitor() {
        tareaMonitor = Task { [weak self] in
            var fallos = 0
            var vueltas = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, let db = self.db else { return }
                let responde = await db.comprobarConexion(segundos: 4)
                fallos = responde ? 0 : fallos + 1
                self.sinConexion = fallos >= 2
                vueltas += 1
                if responde && vueltas % 12 == 0 {   // cada minuto
                    await self.recargarConfiguracion()
                }
            }
        }
    }

    private func iniciarControlInactividad() {
        tareaInactividad = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self else { return }
                if self.fase == .trabajando,
                   self.configuracion.politicaBloqueo.debeBloquear(
                       ultimaActividad: self.ultimaActividad, ahora: .now) {
                    self.bloquear()
                }
            }
        }
    }

    private func instalarMonitorActividad() {
        guard monitorEventos == nil else { return }
        monitorEventos = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel, .mouseMoved]
        ) { [weak self] evento in
            MainActor.assumeIsolated {
                self?.ultimaActividad = .now
            }
            return evento
        }
    }
}
