import AppIntents
import UIKit

// Intenções do sistema (Siri, Atalhos, busca) do DSH.
// Nenhuma delas abre o app: a resposta curta volta em diálogo, porque a Siri
// corta texto longo na fala. Quando não há conexão pronta, a pergunta fica
// guardada no armazém compartilhado e o app a encontra ao abrir.

// MARK: - Conexão com a conversa

// Contrato mínimo entre a intenção e o cliente de rede do app.
// A implementação real é do swift-base: `AdaptadorDePerguntaRapida`, em
// `Fontes/Nucleo/`, que resolve por ServicoPonte quando há token e por
// ServicoDeepSeek com a chave do cofre quando não há.
// O boot do app chama `AdaptadorDePerguntaRapida.registrar()`, que instala o
// motor em `ConectorDePerguntas.compartilhado.motor`.
// Não criamos cliente HTTP aqui de propósito: duplicar a rede significaria
// duplicar chave, token e tratamento de erro da conversa.
protocol MotorDePerguntaRapida {
    // Devolve a resposta inteira de uma pergunta única. Quem chama encurta.
    func responderUmaVez(_ pergunta: String) async throws -> String
}

// Ponto único onde o app instala o motor usado pelas intenções.
final class ConectorDePerguntas {
    static let compartilhado = ConectorDePerguntas()
    var motor: (any MotorDePerguntaRapida)?
    private init() {}
}

// MARK: - Erros

enum ErroDeIntencao: LocalizedError {
    case perguntaVazia
    case areaDeTransferenciaVazia
    case respostaIndisponivel

    var errorDescription: String? {
        switch self {
        case .perguntaVazia:
            return "Digite a pergunta que você quer fazer ao DSH."
        case .areaDeTransferenciaVazia:
            return "A área de transferência está vazia. Copie um texto primeiro."
        case .respostaIndisponivel:
            return "Não consegui falar com o DSH agora. Sua pergunta ficou guardada no app."
        }
    }
}

// MARK: - Texto curto para fala

// A Siri trunca diálogo longo, então todo retorno passa por aqui: no máximo
// três frases e um teto de caracteres, para a fala terminar com sentido.
enum TextoCurto {
    static let limiteDeFrases = 3
    static let limiteDeCaracteres = 300

    static func frases(de texto: String, limite: Int) -> [String] {
        let normalizado = texto.replacingOccurrences(of: "\r\n", with: "\n")
        var resultado: [String] = []
        var atual = ""
        for caractere in normalizado {
            atual.append(caractere)
            let terminou = caractere == "." || caractere == "!" || caractere == "?" || caractere == "\n"
            guard terminou else { continue }
            let frase = atual.trimmingCharacters(in: .whitespacesAndNewlines)
            if !frase.isEmpty {
                resultado.append(frase)
            }
            atual = ""
            if resultado.count >= limite {
                break
            }
        }
        if resultado.count < limite {
            let resto = atual.trimmingCharacters(in: .whitespacesAndNewlines)
            if !resto.isEmpty {
                resultado.append(resto)
            }
        }
        return resultado
    }

    static func paraDialogo(_ texto: String) -> String {
        let trecho = frases(de: texto, limite: limiteDeFrases).joined(separator: " ")
        var limpo = trecho.trimmingCharacters(in: .whitespacesAndNewlines)
        if limpo.isEmpty {
            limpo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard limpo.count > limiteDeCaracteres else { return limpo }
        return String(limpo.prefix(limiteDeCaracteres)) + "..."
    }
}

// MARK: - Perguntar ao DSH

struct PerguntarAoDSH: AppIntent {
    static var title: LocalizedStringResource = "Perguntar ao DSH"
    static var description: IntentDescription? = IntentDescription(
        "Faz uma pergunta ao DSH e responde em voz alta, sem abrir o app."
    )
    // Fica no lugar: a intenção responde na hora ou guarda a pergunta.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Pergunta")
    var texto: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let pergunta = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pergunta.isEmpty else {
            throw ErroDeIntencao.perguntaVazia
        }

        if let motor = ConectorDePerguntas.compartilhado.motor {
            do {
                let resposta = try await motor.responderUmaVez(pergunta)
                return .result(dialog: IntentDialog(stringLiteral: TextoCurto.paraDialogo(resposta)))
            } catch {
                // Falhou a rede: a pergunta não se perde, vira texto pendente
                // para a conversa do app.
                guardarParaConversa(pergunta)
                throw ErroDeIntencao.respostaIndisponivel
            }
        }

        // Sem motor instalado, o app ainda não foi aberto nesta instalação.
        guardarParaConversa(pergunta)
        return .result(dialog: "Pergunta guardada no DSH. Abra o app para ver a resposta.")
    }

    private func guardarParaConversa(_ pergunta: String) {
        ArmazemCompartilhado.guardarTextoParaConversa(pergunta)
        ArmazemCompartilhado.guardarRotaPendente(.conversa)
    }
}

// MARK: - Resumir área de transferência

struct ResumirAreaDeTransferencia: AppIntent {
    static var title: LocalizedStringResource = "Resumir área de transferência"
    static var description: IntentDescription? = IntentDescription(
        "Lê o texto copiado e devolve um resumo curto em voz alta."
    )
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // No iOS 16 ou mais novo o sistema pode pedir confirmação antes de
        // entregar a área de transferência; é o comportamento esperado.
        let copiado = (UIPasteboard.general.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !copiado.isEmpty else {
            throw ErroDeIntencao.areaDeTransferenciaVazia
        }

        if let motor = ConectorDePerguntas.compartilhado.motor {
            let pedido = """
            Resuma o texto a seguir em até 3 frases, em português do Brasil, sem listas e sem markdown.

            \(copiado)
            """
            if let resumo = try? await motor.responderUmaVez(pedido) {
                let limpo = TextoCurto.paraDialogo(resumo)
                if !limpo.isEmpty {
                    return .result(dialog: IntentDialog(stringLiteral: limpo))
                }
            }
        }

        // Sem resumo de verdade disponível, devolver um trecho do próprio texto
        // é melhor que inventar resumo. A fala diz que é trecho.
        let trecho = TextoCurto.paraDialogo(copiado)
        return .result(dialog: IntentDialog(stringLiteral: "O resumo precisa do DSH conectado. Trecho copiado: \(trecho)"))
    }
}

// MARK: - Frases de ativação na Siri

struct AtalhosDoDSH: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PerguntarAoDSH(),
            phrases: [
                "Perguntar ao \(.applicationName)",
                "Pergunte ao \(.applicationName)",
                "Quero perguntar ao \(.applicationName)"
            ],
            shortTitle: "Perguntar ao DSH",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: ResumirAreaDeTransferencia(),
            phrases: [
                "Resumir a área de transferência no \(.applicationName)",
                "Resuma o que copiei no \(.applicationName)"
            ],
            shortTitle: "Resumir área de transferência",
            systemImageName: "doc.on.clipboard"
        )
    }
}

// Lista usada pelo app quando precisa registrar ou depurar as intenções.
enum IntencoesRegistradas {
    static var todas: [any AppIntent.Type] {
        [PerguntarAoDSH.self, ResumirAreaDeTransferencia.self]
    }
}
