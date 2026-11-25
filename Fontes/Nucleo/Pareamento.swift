import Foundation

// Pareamento da ponte por QR code.
//
// O QR não carrega o token: carrega o endereço da ponte e um código de uso
// único, que vale cinco minutos. O app troca esse código pelo token em
// `POST /v1/pareamento/trocar`, grava no Keychain e passa a usar a ponte.
// Assim o token nunca aparece numa tela que alguém possa fotografar.
//
// Formato lido: dsh://ajustes?parear=<código>&endereco=https%3A%2F%2F...
// A rota é a `ajustes` que já existe, então nada muda no contrato de rotas.
struct PedidoDePareamento: Sendable {
    let endereco: String
    let codigo: String

    static func de(url: URL) -> PedidoDePareamento? {
        guard let componentes = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let itens = componentes.queryItems else {
            return nil
        }
        func valor(_ nome: String) -> String? {
            let bruto = itens.first { $0.name.lowercased() == nome }?.value
            let limpo = bruto?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (limpo?.isEmpty ?? true) ? nil : limpo
        }
        guard let codigo = valor("parear"), let endereco = valor("endereco") else { return nil }
        return PedidoDePareamento(endereco: endereco, codigo: codigo)
    }
}

// Ponte entre o URL que chega e a tela de Ajustes, que é quem aplica o pedido.
// Fica em memória de propósito: pareamento é coisa de segundos, não de sessão.
@MainActor
enum PendenciaDePareamento {
    static var atual: PedidoDePareamento?

    static func recolher(de endereco: String) {
        guard let url = URL(string: endereco) else { return }
        atual = PedidoDePareamento.de(url: url)
    }
}
