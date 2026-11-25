import SwiftUI

/// Tipografia do app: só a fonte do sistema, três pesos e quatro papéis.
///
/// O tamanho pedido escolhe o estilo mais próximo da escala da Apple em vez de
/// fixar um corpo em pontos. É de propósito: assim o Texto Dinâmico funciona em
/// todos os papéis sem `@ScaledMetric` espalhado pelas telas, e quem aumenta a
/// letra no ajuste do iPhone vê o app inteiro crescer, inclusive o bloco de
/// código.
///
/// A escala padrão, em pontos, é: largeTitle 34, title 28, title2 22, title3 20,
/// headline 17, body 17, callout 16, subheadline 15, footnote 13, caption 12,
/// caption2 11.
enum Tipografia {
    /// Título de tela e de estado vazio. Padrão 22, que é o `title2`.
    static func titulo(_ tamanho: CGFloat = 22) -> Font {
        .system(estiloPara(tamanho), design: .default, weight: .semibold)
    }

    /// Texto de leitura: resposta, fala do usuário, corpo de cartão. 17 pontos.
    static func corpo() -> Font {
        .system(.body, design: .default, weight: .regular)
    }

    /// Texto de apoio: meta, rótulo de modelo, estado vazio, tempo. 13 pontos.
    static func legenda() -> Font {
        .system(.footnote, design: .default, weight: .regular)
    }

    /// Código, nome de modelo e termo técnico. Padrão 13.
    static func codigo(_ tamanho: CGFloat = 13) -> Font {
        let estilo: Font.TextStyle
        switch tamanho {
        case 16...: estilo = .callout
        case 13..<16: estilo = .footnote
        case 12..<13: estilo = .caption
        default: estilo = .caption2
        }
        return .system(estilo, design: .monospaced, weight: .regular)
    }

    /// Rótulo de campo, de chip e de seção: 12 pontos, semibold, caixa da frase
    /// (a tela escreve "Fixadas", não "FIXADAS").
    static func rotulo() -> Font {
        .system(.caption, design: .default, weight: .semibold)
    }

    private static func estiloPara(_ tamanho: CGFloat) -> Font.TextStyle {
        switch tamanho {
        case 30...: return .largeTitle
        case 26..<30: return .title
        case 22..<26: return .title2
        case 19..<22: return .title3
        case 17..<19: return .headline
        default: return .subheadline
        }
    }
}
