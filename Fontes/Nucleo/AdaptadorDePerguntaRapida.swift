import Foundation

// Liga as intenções do sistema (Siri, Atalhos) ao mesmo cliente de rede da
// conversa. Mora aqui, e não em Fontes/Plataforma, para não duplicar rede,
// chave e token: usa ServicoPonte quando há token e ServicoDeepSeek quando só
// existe a chave da API.
final class AdaptadorDePerguntaRapida: MotorDePerguntaRapida {
    static let compartilhado = AdaptadorDePerguntaRapida()

    private init() {}

    // Idempotente: o boot do app pode chamar quantas vezes quiser.
    static func registrar() {
        ConectorDePerguntas.compartilhado.motor = compartilhado
    }

    func responderUmaVez(_ pergunta: String) async throws -> String {
        let texto = pergunta.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty else { throw ErroDeIntencao.perguntaVazia }

        let modelo = await Preferencias.compartilhada.modelo
        let pedido = PedidoDeConversa(
            mensagens: [MensagemDoPedido(papel: .usuario, texto: texto)],
            maxTokens: 1024
        )

        let provedor: any ProvedorDeConversa
        if let ponte = await ServicoPonte.aPartirDasPreferencias() {
            provedor = ponte
        } else if let chave = try? CofreDeChaves.ler(ChaveDoCofre.apiKeyDeepSeek), !chave.isEmpty {
            provedor = ServicoDeepSeek(apiKey: chave, modelo: modelo)
        } else {
            throw ErroDaConversa.semChave
        }

        var resposta = ""
        for try await fragmento in provedor.responder(pedido) {
            if case .texto(let pedaco) = fragmento {
                resposta += pedaco
            }
        }
        await provedor.cancelar()

        let limpa = resposta.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpa.isEmpty else { throw ErroDeIntencao.respostaIndisponivel }
        return limpa
    }
}
