import Foundation

enum ArmazemCompartilhado {
    static let identificadorDoGrupo = "group.dev.ramses.dsh"

    private static let chaveRota = "dsh.rotaPendente"
    private static let chaveTexto = "dsh.textoPendente"

    /// Devolve nil quando o App Group não está no perfil de assinatura, e isso é
    /// esperado: conta Apple gratuita não libera App Group, então o app assinado
    /// com ela abre sem o armazém compartilhado. Todas as leituras e escritas
    /// abaixo checam nil antes de usar, porque a alternativa seria o app morrer
    /// na abertura no único cenário em que ele é instalável de graça.
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
