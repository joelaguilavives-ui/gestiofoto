import Foundation

/// Configuración de las copias en el Mac principal. Vive en
/// `~/Library/Application Support/GestioFoto/copias.conf`, que leen también
/// los scripts `backup.sh` y `restore.sh` (formato `CLAVE='valor'` de bash).
public struct ConfiguracionCopias: Sendable, Equatable {
    /// Carpeta donde se guardan las copias (Time Machine, disco externo…).
    public var carpeta: String
    public var hora: Int
    public var minuto: Int
    public var conservarDiarias: Int
    public var conservarMensuales: Int
    /// Carpeta `bin` de Postgres.app.
    public var pgBin: String
    public var baseDeDatos: String

    public init(
        carpeta: String,
        hora: Int = 2,
        minuto: Int = 0,
        conservarDiarias: Int = 30,
        conservarMensuales: Int = 12,
        pgBin: String = "/Applications/Postgres.app/Contents/Versions/latest/bin",
        baseDeDatos: String = "gestiofoto"
    ) {
        self.carpeta = carpeta
        self.hora = hora
        self.minuto = minuto
        self.conservarDiarias = conservarDiarias
        self.conservarMensuales = conservarMensuales
        self.pgBin = pgBin
        self.baseDeDatos = baseDeDatos
    }

    public var horaTexto: String {
        String(format: "%02d:%02d", hora, minuto)
    }

    public var esValida: Bool {
        !carpeta.isEmpty && (0...23).contains(hora) && (0...59).contains(minuto)
            && conservarDiarias > 0 && conservarMensuales >= 0
    }

    // MARK: fichero

    public func texto() -> String {
        """
        # GestioFoto — configuración de copias de seguridad (la escribe la app)
        CARPETA=\(Self.comillas(carpeta))
        HORA=\(hora)
        MINUTO=\(minuto)
        CONSERVAR_DIARIAS=\(conservarDiarias)
        CONSERVAR_MENSUALES=\(conservarMensuales)
        PGBIN=\(Self.comillas(pgBin))
        BASE=\(Self.comillas(baseDeDatos))

        """
    }

    public static func leer(_ texto: String) -> ConfiguracionCopias {
        var valores: [String: String] = [:]
        for linea in texto.split(whereSeparator: \.isNewline) {
            let l = linea.trimmingCharacters(in: .whitespaces)
            guard !l.hasPrefix("#"), let igual = l.firstIndex(of: "=") else { continue }
            let clave = String(l[..<igual])
            valores[clave] = sinComillas(String(l[l.index(after: igual)...]))
        }
        var c = ConfiguracionCopias(carpeta: valores["CARPETA"] ?? "")
        c.hora = valores["HORA"].flatMap(Int.init) ?? c.hora
        c.minuto = valores["MINUTO"].flatMap(Int.init) ?? c.minuto
        c.conservarDiarias = valores["CONSERVAR_DIARIAS"].flatMap(Int.init) ?? c.conservarDiarias
        c.conservarMensuales = valores["CONSERVAR_MENSUALES"].flatMap(Int.init) ?? c.conservarMensuales
        c.pgBin = valores["PGBIN"] ?? c.pgBin
        c.baseDeDatos = valores["BASE"] ?? c.baseDeDatos
        return c
    }

    /// 'texto' para bash; una comilla simple dentro se escribe '\''.
    static func comillas(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    static func sinComillas(_ s: String) -> String {
        if s.count >= 2, s.hasPrefix("'"), s.hasSuffix("'") {
            return String(s.dropFirst().dropLast()).replacingOccurrences(of: #"'\''"#, with: "'")
        }
        if s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") {
            return String(s.dropFirst().dropLast())
        }
        return s
    }
}

/// Una copia guardada en la carpeta de copias.
public struct CopiaDisponible: Sendable, Hashable, Identifiable {
    public enum Tipo: String, Sendable { case diaria, mensual, previaRestauracion }
    public let url: URL
    public let tipo: Tipo
    public let fecha: Date
    public let bytes: Int64
    public var id: URL { url }
}

/// Copias de seguridad en el Mac principal: se apoyan en los scripts que
/// instala `Tools/setup_server/setup.sh` (la copia nocturna la lanza launchd con
/// el mismo `backup.sh`).
public struct ServicioCopias: Sendable {
    public let directorio: URL

    public init(directorio: URL = ServicioCopias.directorioPorDefecto) {
        self.directorio = directorio
    }

    public static var directorioPorDefecto: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/GestioFoto", isDirectory: true)
    }

    var ficheroConfiguracion: URL { directorio.appendingPathComponent("copias.conf") }
    func script(_ nombre: String) -> URL { directorio.appendingPathComponent("scripts/\(nombre)") }

    /// `true` si `setup.sh` ya instaló los scripts en este Mac.
    public var instalado: Bool {
        FileManager.default.isExecutableFile(atPath: script("backup.sh").path)
    }

    public func configuracion() throws -> ConfiguracionCopias {
        ConfiguracionCopias.leer(try String(contentsOf: ficheroConfiguracion, encoding: .utf8))
    }

    /// Guarda la configuración y reprograma la copia nocturna.
    public func guardar(_ c: ConfiguracionCopias) async throws {
        guard c.esValida else { throw ErrorProceso.configuracionNoValida }
        try c.texto().write(to: ficheroConfiguracion, atomically: true, encoding: .utf8)
        _ = try await EjecutorProceso.ejecutar(URL(fileURLWithPath: "/bin/bash"),
                                               [script("instalar_agente.sh").path])
    }

    /// «Hacer copia ahora». Devuelve la salida del script.
    public func hacerCopia() async throws -> String {
        try await EjecutorProceso.ejecutar(URL(fileURLWithPath: "/bin/bash"), [script("backup.sh").path])
    }

    /// Restaura una copia. `enPruebas` = en la base `gestiofoto_prueba`, sin
    /// tocar la real (criterio de la fase 1). La restauración real hace antes
    /// una copia del estado actual (la hace el script).
    public func restaurar(_ copia: URL, enPruebas: Bool) async throws -> String {
        var argumentos = [script("restore.sh").path, copia.path]
        if enPruebas { argumentos.append("--prueba") }
        return try await EjecutorProceso.ejecutar(URL(fileURLWithPath: "/bin/bash"), argumentos)
    }

    /// Copias en la carpeta configurada, de la más reciente a la más antigua.
    public func copias() throws -> [CopiaDisponible] {
        let base = URL(fileURLWithPath: try configuracion().carpeta, isDirectory: true)
        let fm = FileManager.default
        var resultado: [CopiaDisponible] = []
        let subcarpetas: [(String, CopiaDisponible.Tipo)] =
            [("diarias", .diaria), ("mensuales", .mensual), ("previas", .previaRestauracion)]
        for (sub, tipo) in subcarpetas {
            let carpeta = base.appendingPathComponent(sub, isDirectory: true)
            guard let nombres = try? fm.contentsOfDirectory(atPath: carpeta.path) else { continue }
            for nombre in nombres where nombre.hasSuffix(".dump") {
                let url = carpeta.appendingPathComponent(nombre)
                let atributos = try fm.attributesOfItem(atPath: url.path)
                resultado.append(CopiaDisponible(
                    url: url, tipo: tipo,
                    fecha: atributos[.modificationDate] as? Date ?? .distantPast,
                    bytes: (atributos[.size] as? NSNumber)?.int64Value ?? 0))
            }
        }
        return resultado.sorted { $0.fecha > $1.fecha }
    }
}
