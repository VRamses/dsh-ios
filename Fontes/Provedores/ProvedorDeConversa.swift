import Foundation

enum OrigemDaConversa: Equatable {
    case deepSeek(modelo: String)
    case ponte(sessaoID: String)
}

struct MensagemDoPedido {
    var papel: Papel
    var texto: String
    var anexos: [Anexo]

    init(papel: Papel, texto: String, anexos: [Anexo] = []) {
        self.papel = papel
        self.texto = texto
        self.anexos = anexos
    }
}

struct PedidoDeConversa {
    var mensagens: [MensagemDoPedido]
    var promptDeSistema: String?
    var temperatura: Double
    var maxTokens: Int
    var ferramentas: [DefiniçãoDeFerramenta]

    init(
        mensagens: [MensagemDoPedido],
        promptDeSistema: String? = nil,
        temperatura: Double = 1.0,
        maxTokens: Int = 4096,
        ferramentas: [DefiniçãoDeFerramenta] = []
    ) {
        self.mensagens = mensagens
        self.promptDeSistema = promptDeSistema
        self.temperatura = temperatura
        self.maxTokens = maxTokens
        self.ferramentas = ferramentas
    }

    var ultimaMensagemDoUsuario: MensagemDoPedido? {
        mensagens.last { $0.papel == .usuario }
    }
}

enum FragmentoDaResposta {
    case raciocinio(String)
    case texto(String)
    case chamadaDeFerramenta(ChamadaDeFerramenta)
    case uso(entrada: Int, saida: Int)
    case fim(motivo: String?)
}

protocol ProvedorDeConversa: AnyObject {
    func responder(_ pedido: PedidoDeConversa) -> AsyncThrowingStream<FragmentoDaResposta, Error>
    func cancelar() async
}

enum ErroDaConversa: LocalizedError {
    case semChave
    case semToken
    case enderecoInvalido
    case http(Int, String)
    case rede(String)
    case cancelado

    var errorDescription: String? {
        switch self {
        case .semChave:
            return "Falta a chave da API da DeepSeek no cofre."
        case .semToken:
            return "Falta o token da ponte do DSH no cofre."
        case .enderecoInvalido:
            return "O endereço do serviço não é uma URL válida."
        case .http(let codigo, let corpo):
            if corpo.isEmpty {
                return "O serviço respondeu com erro \(codigo)."
            }
            return "O serviço respondeu com erro \(codigo): \(corpo)"
        case .rede(let detalhe):
            return "Falha de rede: \(detalhe)"
        case .cancelado:
            return "A resposta foi cancelada."
        }
    }
}
