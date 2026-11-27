import Foundation

/// Liga uma sessão do DSH no computador à conversa que a espelha aqui.
///
/// Fica em `UserDefaults` de propósito: nada no banco local muda de formato, e
/// o vínculo é descartável. Se ele sumir, a próxima abertura da sessão cria
/// outra conversa em vez de quebrar a que existe.
///
/// Guarda também o menor `seq` já trazido da sessão, que é o que diz de onde
/// continuar quando a pessoa pede as mensagens mais antigas.
struct VinculoDeSessoes {
    struct Vinculo: Codable {
        var conversa: UUID
        var menorSeq: Int
    }

    static let compartilhado = VinculoDeSessoes()

    private let chave = "dsh.vinculosDeSessao"
    private let padroes: UserDefaults

    init(padroes: UserDefaults = .standard) {
        self.padroes = padroes
    }

    func vinculo(de sessao: String) -> Vinculo? {
        todos()[sessao]
    }

    /// Caminho de volta: qual sessão esta conversa espelha.
    func sessao(deConversa conversa: UUID) -> (sessao: String, vinculo: Vinculo)? {
        for (sessao, vinculo) in todos() where vinculo.conversa == conversa {
            return (sessao, vinculo)
        }
        return nil
    }

    func salvar(_ vinculo: Vinculo, para sessao: String) {
        var atual = todos()
        atual[sessao] = vinculo
        gravar(atual)
    }

    func esquecer(_ sessao: String) {
        var atual = todos()
        atual.removeValue(forKey: sessao)
        gravar(atual)
    }

    func esquecerConversa(_ conversa: UUID) {
        let atual = todos().filter { $0.value.conversa != conversa }
        gravar(atual)
    }

    private func todos() -> [String: Vinculo] {
        guard let dados = padroes.data(forKey: chave) else { return [:] }
        return (try? JSONDecoder().decode([String: Vinculo].self, from: dados)) ?? [:]
    }

    private func gravar(_ mapa: [String: Vinculo]) {
        guard let dados = try? JSONEncoder().encode(mapa) else { return }
        padroes.set(dados, forKey: chave)
    }
}
