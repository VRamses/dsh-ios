import CoreGraphics

/// Raio de canto do app, em pontos: 8, 12, 16, 22.
///
/// Uso: `s` para chip e botão de parar, `m` para bloco de código, campo e
/// cartão pequeno, `l` para a fala do usuário e a barra de entrada, `g` para o
/// cartão do pensamento e a folha de sessões. Tudo com o estilo `.continuous`,
/// que é o canto da Apple e não o arco de compasso.
enum Raio {
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let g: CGFloat = 22
}
