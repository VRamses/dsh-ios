import Foundation

struct QuadroDeSSE {
    var evento: String?
    var dados: String
}

struct AcumuladorDeSSE {
    private var evento: String?
    private var linhasDeDados: [String] = []

    mutating func consumir(linha: String) -> QuadroDeSSE? {
        if linha.isEmpty {
            return descarregar()
        }
        if linha.hasPrefix(":") {
            return nil
        }
        guard let separador = linha.firstIndex(of: ":") else {
            return nil
        }
        let campo = String(linha[linha.startIndex..<separador])
        var valor = String(linha[linha.index(after: separador)...])
        if valor.hasPrefix(" ") {
            valor.removeFirst()
        }
        switch campo {
        case "event":
            evento = valor
        case "data":
            linhasDeDados.append(valor)
        default:
            break
        }
        return nil
    }

    mutating func descarregar() -> QuadroDeSSE? {
        defer {
            evento = nil
            linhasDeDados = []
        }
        guard !linhasDeDados.isEmpty else { return nil }
        return QuadroDeSSE(evento: evento, dados: linhasDeDados.joined(separator: "\n"))
    }
}
