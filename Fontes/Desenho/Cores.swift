import SwiftUI
import UIKit

/// Paleta fechada do app: um acento só, poucos neutros e um par claro/escuro
/// para cada papel. O tema claro não é o escuro invertido, é a mesma tinta em
/// papel branco, e o escuro é o padrão do produto.
///
/// Contraste conferido contra todas as superfícies de cada tema, pela fórmula
/// WCAG de luminância relativa:
///
/// | papel | sobre o fundo | sobre a superfície | sobre a superfície elevada |
/// |---|---|---|---|
/// | texto | 16,5:1 escuro, 16,4:1 claro | 15,3:1 / 18,0:1 | 13,4:1 / 18,0:1 |
/// | textoFraco | 8,5:1 / 5,6:1 | 7,9:1 / 6,2:1 | 6,9:1 / 6,2:1 |
/// | acento | 8,7:1 / 5,4:1 | 8,0:1 / 5,9:1 | 7,0:1 / 5,9:1 |
/// | perigo | 6,4:1 / 6,0:1 | 5,9:1 / 6,6:1 | 5,2:1 / 6,6:1 |
/// | sucesso | 9,4:1 / 5,6:1 | 8,7:1 / 6,2:1 | 7,6:1 / 6,2:1 |
///
/// Borda passa 3,1:1 no escuro e 3,2:1 no claro contra a superfície, que é o
/// mínimo de 3:1 para borda de campo e ícone. Texto do usuário sobre o
/// `acentoSuave` fica em 13,3:1 no escuro e 15,2:1 no claro. O glifo do botão
/// de enviar usa `fundo` sobre `acento`: 8,7:1 no escuro e 5,4:1 no claro.
enum Cores {
    /// Chão da tela, onde o transcrito flutua.
    static let fundo = dinamica(claro: 0xF6F4F0, escuro: 0x0E1013)
    /// Superfície de cartão, da barra de entrada e do menu.
    static let superficie = dinamica(claro: 0xFFFFFF, escuro: 0x16191D)
    /// Superfície que sobe um degrau: bloco de código e cartão do pensamento.
    static let superficieElevada = dinamica(claro: 0xFFFFFF, escuro: 0x20252B)
    /// Borda de campo e de cartão. É o mínimo de 3:1 contra a superfície.
    static let borda = dinamica(claro: 0x8B9099, escuro: 0x5F6772)
    /// Texto principal e ícone ativo.
    static let texto = dinamica(claro: 0x15171A, escuro: 0xEDEFF2)
    /// Texto de apoio: raciocínio, meta, estado vazio.
    static let textoFraco = dinamica(claro: 0x5C626B, escuro: 0xA6AEB8)
    /// O sinal do produto: ação principal e estado real de trabalho da máquina.
    static let acento = dinamica(claro: 0x8A5A00, escuro: 0xE3A33C)
    /// Fundo da fala do usuário, e só dela.
    static let acentoSuave = dinamica(claro: 0xF7EBD3, escuro: 0x2C2517)
    /// Falha que impede a resposta.
    static let perigo = dinamica(claro: 0xB42318, escuro: 0xF16A6A)
    /// Confirmação de algo que realmente aconteceu.
    static let sucesso = dinamica(claro: 0x15703C, escuro: 0x5FCB8B)

    private static func dinamica(claro: UInt32, escuro: UInt32) -> Color {
        Color(uiColor: UIColor { tracos in
            tracos.userInterfaceStyle == .dark ? UIColor(opaca: escuro) : UIColor(opaca: claro)
        })
    }
}

private extension UIColor {
    convenience init(opaca: UInt32) {
        self.init(
            red: CGFloat((opaca >> 16) & 0xFF) / 255,
            green: CGFloat((opaca >> 8) & 0xFF) / 255,
            blue: CGFloat(opaca & 0xFF) / 255,
            alpha: 1
        )
    }
}
