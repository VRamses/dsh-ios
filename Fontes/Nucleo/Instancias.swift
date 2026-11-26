import Foundation
import Combine

/// Um computador com DSH aberto que este iPhone já sabe alcançar.
///
/// O endereço é público dentro do tailnet e pode ficar em `UserDefaults`; o
/// token de cada computador fica no cofre, numa conta própria por instância.
/// Antes disto o app guardava um endereço e um token só: parear com o notebook
/// apagava o SUPERCOLLIDER, e voltar exigia redigitar tudo.
struct InstanciaDoDsh: Codable, Identifiable, Hashable {
    var id: UUID
    var nome: String
    var endereco: String
    var criadaEm: Date

    init(id: UUID = UUID(), nome: String = "", endereco: String, criadaEm: Date = Date()) {
        self.id = id
        self.nome = nome
        self.endereco = endereco
        self.criadaEm = criadaEm
    }

    /// O que a lista mostra. Nome vazio cai para o primeiro pedaço do host, que
    /// é o que identifica a máquina para quem já conhece o tailnet.
    var rotulo: String {
        let limpo = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        return limpo.isEmpty ? Self.host(de: endereco) : limpo
    }

    var host: String { Self.host(de: endereco) }

    static func normalizar(_ endereco: String) -> String {
        var limpo = endereco.trimmingCharacters(in: .whitespacesAndNewlines)
        while limpo.hasSuffix("/") { limpo.removeLast() }
        return limpo
    }

    static func host(de endereco: String) -> String {
        let limpo = normalizar(endereco)
        if let host = URLComponents(string: limpo)?.host, !host.isEmpty {
            return host.split(separator: ".").first.map(String.init) ?? host
        }
        let semEsquema = limpo
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        return semEsquema.split(separator: "/").first.map(String.init) ?? "computador"
    }
}

/// Lista dos computadores conhecidos e qual deles está em uso.
///
/// A instância ativa é a dona do `Preferencias.enderecoDaPonte` e da conta
/// `ponte.token` do cofre, que é o que `ServicoPonte.aPartirDasPreferencias()`
/// lê. Trocar de instância é copiar o endereço e o token dela para esses dois
/// lugares, e é por isso que nada mais no app precisou mudar para ter mais de
/// um computador. O token de cada uma continua guardado na conta dela, então
/// trocar de lado e voltar não perde pareamento.
@MainActor
final class Instancias: ObservableObject {
    static let compartilhada = Instancias()

    private enum Chave {
        static let lista = "dsh.instancias"
        static let ativa = "dsh.instanciaAtiva"
    }

    @Published private(set) var lista: [InstanciaDoDsh] = []
    @Published private(set) var ativa: UUID?

    private let padroes: UserDefaults

    /// Ligado só enquanto `ativar` copia endereço e token para as preferências.
    /// Sem ele, o espelho do endereço (`Preferencias.enderecoDaPonte.didSet`)
    /// trataria a troca de instância como edição manual e desfaria a troca.
    private var aplicandoAtivacao = false

    init(padroes: UserDefaults = .standard) {
        self.padroes = padroes
        carregar()
    }

    // MARK: - Leitura

    func instancia(_ id: UUID) -> InstanciaDoDsh? {
        lista.first { $0.id == id }
    }

    var ativaEmUso: InstanciaDoDsh? {
        guard let ativa else { return nil }
        return instancia(ativa)
    }

    func token(de id: UUID) -> String? {
        guard let valor = try? CofreDeChaves.ler(Instancias.chaveDoToken(id)), !valor.isEmpty else {
            return nil
        }
        return valor
    }

    static func chaveDoToken(_ id: UUID) -> String {
        "\(ChaveDoCofre.tokenDaPonte).\(id.uuidString.lowercased())"
    }

    // MARK: - Escrita

    /// Guarda um computador e o deixa em uso. Endereço repetido não duplica a
    /// linha: atualiza o nome e o token do que já estava lá, que é o que o
    /// usuário espera ao parear de novo com a mesma máquina.
    @discardableResult
    func adicionar(nome: String, endereco: String, token: String?) throws -> InstanciaDoDsh {
        let limpo = InstanciaDoDsh.normalizar(endereco)
        let rotulo = nome.trimmingCharacters(in: .whitespacesAndNewlines)

        if let indice = lista.firstIndex(where: { $0.endereco == limpo }) {
            if !rotulo.isEmpty { lista[indice].nome = rotulo }
            if let token, !token.isEmpty {
                try CofreDeChaves.guardar(token, para: Instancias.chaveDoToken(lista[indice].id))
            }
            persistir()
            ativar(lista[indice].id)
            return lista[indice]
        }

        let nova = InstanciaDoDsh(
            nome: rotulo.isEmpty ? InstanciaDoDsh.host(de: limpo) : rotulo,
            endereco: limpo
        )
        if let token, !token.isEmpty {
            try CofreDeChaves.guardar(token, para: Instancias.chaveDoToken(nova.id))
        }
        lista.append(nova)
        persistir()
        ativar(nova.id)
        return nova
    }

    /// Põe esta instância em uso: endereço nas preferências, token na conta que
    /// o `ServicoPonte` lê e o identificador gravado para a tela saber qual é.
    func ativar(_ id: UUID) {
        guard let indice = lista.firstIndex(where: { $0.id == id }) else { return }
        aplicandoAtivacao = true
        Preferencias.compartilhada.enderecoDaPonte = lista[indice].endereco
        aplicandoAtivacao = false

        if let token = token(de: id) {
            try? CofreDeChaves.guardar(token, para: ChaveDoCofre.tokenDaPonte)
        } else {
            try? CofreDeChaves.apagar(ChaveDoCofre.tokenDaPonte)
        }

        ativa = id
        padroes.set(id.uuidString, forKey: Chave.ativa)
    }

    func renomear(_ id: UUID, para nome: String) {
        guard let indice = lista.firstIndex(where: { $0.id == id }) else { return }
        lista[indice].nome = nome
        persistir()
    }

    /// Esquece o computador e o token dele. Se era o que estava em uso, o app
    /// passa para o primeiro que sobrou em vez de ficar com um endereço órfão.
    func remover(_ id: UUID) {
        guard let indice = lista.firstIndex(where: { $0.id == id }) else { return }
        lista.remove(at: indice)
        try? CofreDeChaves.apagar(Instancias.chaveDoToken(id))
        persistir()

        guard ativa == id else { return }
        ativa = nil
        padroes.removeObject(forKey: Chave.ativa)
        guard let proxima = lista.first else {
            Preferencias.compartilhada.enderecoDaPonte = ""
            try? CofreDeChaves.apagar(ChaveDoCofre.tokenDaPonte)
            return
        }
        ativar(proxima.id)
    }

    /// Chamado pelo `didSet` do endereço nas preferências: o que se digita em
    /// Ajustes é o endereço do computador em uso, não um campo solto ao lado da
    /// lista. Endereço que já é de outra instância só troca para ela.
    func enderecoDaPonteMudou(_ endereco: String) {
        guard !aplicandoAtivacao else { return }
        let limpo = InstanciaDoDsh.normalizar(endereco)
        guard !limpo.isEmpty else { return }

        if let id = ativa, let indice = lista.firstIndex(where: { $0.id == id }) {
            guard lista[indice].endereco != limpo else { return }
            lista[indice].endereco = limpo
            if lista[indice].nome.trimmingCharacters(in: .whitespaces).isEmpty {
                lista[indice].nome = InstanciaDoDsh.host(de: limpo)
            }
            persistir()
            return
        }

        if let existente = lista.first(where: { $0.endereco == limpo }) {
            ativar(existente.id)
            return
        }

        // Endereço novo digitado à mão entra como computador novo. `ativar`
        // apaga o token da ponte de propósito: ele era do computador anterior e
        // não vale para este, então é melhor a tela pedir o token do que falhar
        // um 401 sem explicação.
        lista.append(InstanciaDoDsh(endereco: limpo))
        persistir()
        ativar(lista[lista.count - 1].id)
    }

    /// Chamado quando o token é salvo ou apagado em Ajustes: o cofre da conta
    /// ativa acompanha, para trocar de computador e voltar não pedir token de novo.
    func tokenDaAtivaMudou(_ token: String?) {
        guard let ativa else { return }
        if let token, !token.isEmpty {
            try? CofreDeChaves.guardar(token, para: Instancias.chaveDoToken(ativa))
        } else {
            try? CofreDeChaves.apagar(Instancias.chaveDoToken(ativa))
        }
    }

    // MARK: - Pareamento e inicialização

    /// Fecha a conta depois de parear: o computador entra na lista com o nome
    /// que a ponte informou, o token vai para a conta dele e ele fica em uso.
    @discardableResult
    func registrarPareamento(endereco: String, nome: String?, token: String) throws -> InstanciaDoDsh {
        try adicionar(nome: nome ?? "", endereco: endereco, token: token)
    }

    /// Chamado quando Ajustes abre. Conserta duas situações que vêm de versões
    /// anteriores do app: a de quem já tinha endereço e token salvos e nunca viu
    /// esta lista, e a de quem ficou sem instância ativa.
    func sincronizarComPreferencias(endereco: String, temToken: Bool) {
        let limpo = InstanciaDoDsh.normalizar(endereco)
        if lista.isEmpty {
            guard !limpo.isEmpty else { return }
            let nova = InstanciaDoDsh(endereco: limpo)
            if temToken, let atual = try? CofreDeChaves.ler(ChaveDoCofre.tokenDaPonte),
               !atual.isEmpty {
                try? CofreDeChaves.guardar(atual, para: Instancias.chaveDoToken(nova.id))
            }
            lista.append(nova)
            persistir()
            ativa = nova.id
            padroes.set(nova.id.uuidString, forKey: Chave.ativa)
            return
        }

        if ativa == nil || (ativa.flatMap { instancia($0) } == nil) {
            ativar(lista[0].id)
        }
    }

    // MARK: - Persistência

    private func carregar() {
        if let dados = padroes.data(forKey: Chave.lista),
           let lidas = try? JSONDecoder().decode([InstanciaDoDsh].self, from: dados) {
            lista = lidas
        }
        if let texto = padroes.string(forKey: Chave.ativa), let id = UUID(uuidString: texto) {
            ativa = id
        }
    }

    private func persistir() {
        guard let dados = try? JSONEncoder().encode(lista) else { return }
        padroes.set(dados, forKey: Chave.lista)
    }
}
