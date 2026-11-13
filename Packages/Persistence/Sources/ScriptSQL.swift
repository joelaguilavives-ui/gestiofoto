import Foundation

/// Divide un fichero SQL en sentencias para ejecutarlas una a una (PostgresNIO
/// usa el protocolo extendido, que admite una sola sentencia por consulta).
///
/// Respeta cadenas '…' (con '' y E'\'' ), identificadores "…", cuerpos
/// $$…$$ / $etiqueta$…$etiqueta$ y comentarios -- y /* */ (que se descartan
/// fuera de las cadenas).
public enum ScriptSQL {
    public static func sentencias(_ sql: String) -> [String] {
        let s = Array(sql.unicodeScalars)
        let n = s.count
        var resultado: [String] = []
        var actual = String.UnicodeScalarView()
        var i = 0

        func esIdentificador(_ c: Unicode.Scalar) -> Bool {
            c == "_" || CharacterSet.alphanumerics.contains(c)
        }

        func cerrarSentencia() {
            let texto = String(actual).trimmingCharacters(in: .whitespacesAndNewlines)
            if !texto.isEmpty { resultado.append(texto) }
            actual = String.UnicodeScalarView()
        }

        while i < n {
            let c = s[i]
            let siguiente: Unicode.Scalar? = i + 1 < n ? s[i + 1] : nil

            // -- comentario hasta fin de línea
            if c == "-" && siguiente == "-" {
                while i < n && s[i] != "\n" { i += 1 }
                continue
            }

            // /* comentario */ (PostgreSQL permite anidarlos)
            if c == "/" && siguiente == "*" {
                var nivel = 0
                repeat {
                    if s[i] == "/" && i + 1 < n && s[i + 1] == "*" {
                        nivel += 1; i += 2
                    } else if s[i] == "*" && i + 1 < n && s[i + 1] == "/" {
                        nivel -= 1; i += 2
                    } else {
                        i += 1
                    }
                } while nivel > 0 && i < n
                actual.append(" ")
                continue
            }

            // 'cadena' y "identificador"
            if c == "'" || c == "\"" {
                let conBarras = c == "'" && i > 0 && (s[i - 1] == "E" || s[i - 1] == "e")
                    && (i < 2 || !esIdentificador(s[i - 2]))
                actual.append(c)
                i += 1
                while i < n {
                    let d = s[i]
                    actual.append(d)
                    i += 1
                    if conBarras && d == "\\" && i < n {
                        actual.append(s[i])
                        i += 1
                        continue
                    }
                    if d == c {
                        if i < n && s[i] == c {        // '' o "" escapados
                            actual.append(s[i])
                            i += 1
                            continue
                        }
                        break
                    }
                }
                continue
            }

            // $etiqueta$ … $etiqueta$
            if c == "$" && (i == 0 || !esIdentificador(s[i - 1])) {
                var j = i + 1
                while j < n && esIdentificador(s[j]) && !(j == i + 1 && ("0"..."9").contains(s[j])) {
                    j += 1
                }
                if j < n && s[j] == "$" {
                    let etiqueta = Array(s[i...j])
                    actual.append(contentsOf: etiqueta)
                    i = j + 1
                    while i < n {
                        if s[i] == "$" && i + etiqueta.count <= n
                            && Array(s[i..<(i + etiqueta.count)]) == etiqueta {
                            actual.append(contentsOf: etiqueta)
                            i += etiqueta.count
                            break
                        }
                        actual.append(s[i])
                        i += 1
                    }
                    continue
                }
            }

            if c == ";" {
                cerrarSentencia()
                i += 1
                continue
            }

            actual.append(c)
            i += 1
        }
        cerrarSentencia()
        return resultado
    }
}
