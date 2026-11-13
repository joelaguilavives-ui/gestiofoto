import Foundation

public enum ErrorProceso: Error, LocalizedError, Equatable {
    case fallo(codigo: Int32, salida: String)
    case configuracionNoValida

    public var errorDescription: String? {
        switch self {
        case .fallo(let codigo, let salida):
            let detalle = salida.trimmingCharacters(in: .whitespacesAndNewlines)
            return "El proceso terminó con error (\(codigo)).\n\(detalle.suffix(1500))"
        case .configuracionNoValida:
            return "La configuración de las copias no es válida."
        }
    }
}

/// Ejecuta un programa y devuelve su salida (stdout y stderr juntos).
/// La salida va a un fichero temporal, no a una tubería, para que un proceso
/// con mucha salida no se quede bloqueado.
public enum EjecutorProceso {
    public static func ejecutar(
        _ ejecutable: URL,
        _ argumentos: [String],
        entorno: [String: String]? = nil
    ) async throws -> String {
        let salida = FileManager.default.temporaryDirectory
            .appendingPathComponent("gestiofoto-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: salida.path, contents: nil)
        let manejador = try FileHandle(forWritingTo: salida)

        let codigo: Int32 = try await withCheckedThrowingContinuation { continuacion in
            let proceso = Process()
            proceso.executableURL = ejecutable
            proceso.arguments = argumentos
            if let entorno {
                proceso.environment = ProcessInfo.processInfo.environment.merging(entorno) { $1 }
            }
            proceso.standardOutput = manejador
            proceso.standardError = manejador
            proceso.standardInput = FileHandle.nullDevice
            proceso.terminationHandler = { terminado in
                continuacion.resume(returning: terminado.terminationStatus)
            }
            do {
                try proceso.run()
            } catch {
                continuacion.resume(throwing: error)
            }
        }

        try? manejador.close()
        let texto = (try? String(contentsOf: salida, encoding: .utf8)) ?? ""
        try? FileManager.default.removeItem(at: salida)
        guard codigo == 0 else { throw ErrorProceso.fallo(codigo: codigo, salida: texto) }
        return texto
    }
}
