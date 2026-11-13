import Foundation

/// Bloqueo de la sesión tras un tiempo sin uso (clave `sesion.bloqueo_minutos`).
public struct PoliticaBloqueo: Sendable, Equatable {
    /// 0 = no bloquear nunca.
    public var minutos: Int

    public init(minutos: Int) {
        self.minutos = max(0, minutos)
    }

    public static let porDefecto = PoliticaBloqueo(minutos: 10)

    public func debeBloquear(ultimaActividad: Date, ahora: Date) -> Bool {
        guard minutos > 0 else { return false }
        return ahora.timeIntervalSince(ultimaActividad) >= Double(minutos) * 60
    }
}

/// Estado de la última copia de seguridad. La app avisa si tiene más de 2 días
/// (PDF §7).
public enum EstadoCopia: Sendable, Equatable {
    case nunca
    case reciente(Date)
    case antigua(Date)

    public static let diasMaximos = 2

    public static func evaluar(ultima: Date?, ahora: Date) -> EstadoCopia {
        guard let ultima else { return .nunca }
        let limite = Double(diasMaximos) * 24 * 3600
        return ahora.timeIntervalSince(ultima) > limite ? .antigua(ultima) : .reciente(ultima)
    }

    public var requiereAviso: Bool {
        switch self {
        case .reciente: false
        case .nunca, .antigua: true
        }
    }
}
