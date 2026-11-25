import Foundation

enum ArmazemCompartilhado {
    static let identificadorDoGrupo = "group.dev.ramses.dsh"

    private static let chaveRota = "dsh.rotaPendente"
    private static let chaveTexto = "dsh.textoPendente"

    private static var padroes: UserDefaults? {
        UserDefaults(suiteName: identificadorDoGrupo)
    }

    static func guardarRotaPendente(_ rota: RotaDoApp) {
        guard let padroes else { return }
        padroes.set(rota.rawValue, forKey: chaveRota)
    }

    static func consumirRotaPendente() -> RotaDoApp? {
        guard let padroes, let bruto = padroes.string(forKey: chaveRota) else { return nil }
        padroes.removeObject(forKey: chaveRota)
        return RotaDoApp(rawValue: bruto)
    }

    static func guardarTextoParaConversa(_ texto: String) {
        guard let padroes else { return }
        padroes.set(texto, forKey: chaveTexto)
    }

    static func consumirTextoPendente() -> String? {
        guard let padroes, let texto = padroes.string(forKey: chaveTexto) else { return nil }
        padroes.removeObject(forKey: chaveTexto)
        return texto.isEmpty ? nil : texto
    }
}
