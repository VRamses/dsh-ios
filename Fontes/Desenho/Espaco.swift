import CoreGraphics

/// Régua de espaço do app, em pontos: 4, 8, 12, 16, 24, 32.
///
/// Uso: `xs` para o que anda junto (ícone e rótulo), `s` entre linhas de uma
/// mesma peça, `m` entre peças de um cartão, `l` na margem da tela e no recheio
/// do cartão grande, `xl` entre turnos da conversa, `xxl` para respiro de fim de
/// rolagem e para o vão que centraliza um estado vazio.
///
/// Fora dessa régua só existe `1` para linha de 1 ponto e `44` para alvo de
/// toque, que são medidas de acessibilidade, não de ritmo.
enum Espaco {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}
