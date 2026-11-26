import Foundation
import Combine

@MainActor
final class Preferencias: ObservableObject {
    static let compartilhada = Preferencias()

    static let modeloPadrao = "deepseek-chat"
    static let enderecoDaPontePadrao = "https://desktop-nvl84h2.tail056d02.ts.net:8443"

    private enum Chave {
        static let modelo = "dsh.modelo"
        static let temperatura = "dsh.temperatura"
        static let maxTokens = "dsh.maxTokens"
        static let usaPonte = "dsh.usaPonte"
        static let enderecoDaPonte = "dsh.enderecoDaPonte"
        static let vozAutomatica = "dsh.vozAutomatica"
        static let sessaoDaPonte = "dsh.sessaoDaPonte"
        static let tituloDaSessaoDaPonte = "dsh.tituloDaSessaoDaPonte"
    }

    private let padroes: UserDefaults

    @Published var modelo: String {
        didSet { padroes.set(modelo, forKey: Chave.modelo) }
    }

    @Published var temperatura: Double {
        didSet { padroes.set(temperatura, forKey: Chave.temperatura) }
    }

    @Published var maxTokens: Int {
        didSet { padroes.set(maxTokens, forKey: Chave.maxTokens) }
    }

    @Published var usaPonte: Bool {
        didSet { padroes.set(usaPonte, forKey: Chave.usaPonte) }
    }

    @Published var enderecoDaPonte: String {
        didSet { padroes.set(enderecoDaPonte, forKey: Chave.enderecoDaPonte) }
    }

    @Published var vozAutomatica: Bool {
        didSet { padroes.set(vozAutomatica, forKey: Chave.vozAutomatica) }
    }

    /// Última sessão do DSH escolhida, guardada só para a tela saber o que dizer
    /// em Ajustes depois de o app reabrir. O motor não volta sozinho para a ponte
    /// por causa dela: quem decide é `sessaoAbertaAgora`.
    @Published var sessaoDaPonte: String {
        didSet { padroes.set(sessaoDaPonte, forKey: Chave.sessaoDaPonte) }
    }

    @Published var tituloDaSessaoDaPonte: String {
        didSet { padroes.set(tituloDaSessaoDaPonte, forKey: Chave.tituloDaSessaoDaPonte) }
    }

    /// Sessão aberta nesta execução. Fica só em memória, de propósito: reabrir o
    /// app volta para a DeepSeek direta até alguém escolher uma sessão de novo, e
    /// Ajustes precisa saber a diferença entre "marcado" e "respondendo pela
    /// ponte agora" para não mentir no estado do motor.
    @Published private(set) var sessaoAbertaAgora: String?

    init(padroes: UserDefaults = .standard) {
        self.padroes = padroes
        let modeloSalvo = padroes.string(forKey: Chave.modelo) ?? Self.modeloPadrao
        let temperaturaSalva = padroes.object(forKey: Chave.temperatura) as? Double ?? 1.0
        let maxTokensSalvo = padroes.object(forKey: Chave.maxTokens) as? Int ?? 4096
        let usaPonteSalvo = padroes.object(forKey: Chave.usaPonte) as? Bool ?? false
        let enderecoSalvo = padroes.string(forKey: Chave.enderecoDaPonte) ?? Self.enderecoDaPontePadrao
        let vozSalva = padroes.object(forKey: Chave.vozAutomatica) as? Bool ?? false
        let sessaoSalva = padroes.string(forKey: Chave.sessaoDaPonte) ?? ""
        let tituloSalvo = padroes.string(forKey: Chave.tituloDaSessaoDaPonte) ?? ""

        self.modelo = modeloSalvo
        self.temperatura = temperaturaSalva
        self.maxTokens = maxTokensSalvo
        self.usaPonte = usaPonteSalvo
        self.enderecoDaPonte = enderecoSalvo
        self.vozAutomatica = vozSalva
        self.sessaoDaPonte = sessaoSalva
        self.tituloDaSessaoDaPonte = tituloSalvo
        self.sessaoAbertaAgora = nil
    }

    /// Chamado pela conversa quando uma sessão do DSH é aberta ou descartada.
    func marcarSessaoAberta(_ identificador: String?, titulo: String = "") {
        sessaoAbertaAgora = identificador
        guard let identificador, !identificador.isEmpty else { return }
        sessaoDaPonte = identificador
        tituloDaSessaoDaPonte = titulo
    }

    var modeloEhReasoner: Bool {
        modelo.lowercased().contains("reasoner")
    }

    var temperaturaEfetiva: Double {
        min(max(temperatura, 0), 2)
    }

    var maxTokensEfetivo: Int {
        max(maxTokens, 256)
    }
}
