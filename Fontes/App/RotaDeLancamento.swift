import Foundation

// Rotas de lançamento usadas pelo CI para fotografar telas determinísticas.
// O contrato chama de `-rota conversa|voz|ajustes|dsh|artefato`; `artefato` não
// existe em RotaDoApp, então a tabela de lançamento fica aqui e não mexe no enum
// compartilhado.
enum RotaDeLancamento: String, CaseIterable {
    case conversa
    case voz
    case ajustes
    case dsh
    case artefato

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .conversa: return "Conversa"
        case .voz: return "Voz"
        case .ajustes: return "Ajustes"
        case .dsh: return "DSH"
        case .artefato: return "Artefato"
        }
    }

    init?(texto: String) {
        let limpo = texto.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let rota = RotaDeLancamento(rawValue: limpo) else { return nil }
        self = rota
    }
}

struct EstadoDeLancamento {
    var rota: RotaDeLancamento
    var demonstracao: Bool

    static func ler(argumentos: [String]) -> EstadoDeLancamento {
        var rota = RotaDeLancamento.conversa
        var demonstracao = false
        var indice = 0
        while indice < argumentos.count {
            let argumento = argumentos[indice]
            let proximo = indice + 1 < argumentos.count ? argumentos[indice + 1] : nil
            if argumento == "-rota", let proximo, let achada = RotaDeLancamento(texto: proximo) {
                rota = achada
                indice += 1
            } else if argumento.hasPrefix("-rota="), let achada = RotaDeLancamento(texto: String(argumento.dropFirst(6))) {
                rota = achada
            } else if argumento == "-demonstracao" {
                if let proximo, !proximo.hasPrefix("-") {
                    demonstracao = eLigado(proximo)
                    indice += 1
                } else {
                    demonstracao = true
                }
            } else if argumento.hasPrefix("-demonstracao=") {
                demonstracao = eLigado(String(argumento.dropFirst(14)))
            }
            indice += 1
        }
        return EstadoDeLancamento(rota: rota, demonstracao: demonstracao)
    }

    static var atual: EstadoDeLancamento {
        ler(argumentos: ProcessInfo.processInfo.arguments)
    }

    private static func eLigado(_ valor: String) -> Bool {
        let limpo = valor.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return limpo == "1" || limpo == "true" || limpo == "sim" || limpo == "yes"
    }
}
