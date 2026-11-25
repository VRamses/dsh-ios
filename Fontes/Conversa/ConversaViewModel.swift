import Foundation
import Combine
import SwiftData

/// Estado da conversa na tela. Não cria tipo da camada de dados: fala com
/// `Conversa`, `Mensagem` e `Anexo` do núcleo e com `ProvedorDeConversa` do
/// swift-base.
///
/// A classe não é `@MainActor` de propósito: ela precisa nascer no inicializador
/// de uma `View` (que não é isolado) sem quebrar o build. O que toca a tela fica
/// nos métodos marcados `@MainActor`, e o que toca rede e disco fica fora.
final class ConversaViewModel: ObservableObject {
    @Published private(set) var conversa: Conversa?
    @Published private(set) var estaRespondendo = false
    @Published private(set) var textoAoVivo = ""
    @Published private(set) var raciocinioAoVivo = ""

    /// Erro da última tentativa, em português, já pronto para a tela.
    @Published private(set) var erro: String?

    @Published private(set) var sessoes: [SessaoResumo] = []
    @Published private(set) var carregandoSessoes = false
    @Published private(set) var erroDeSessoes: String?

    /// Sessão do DSH em uso, quando a ponte é o caminho da conversa.
    @Published private(set) var sessaoDaPonte: String?

    private var contexto: ModelContext?
    private var ponte: ServicoPonte?
    private var tarefa: Task<Void, Never>?
    private var provedorDoEnvio: (any ProvedorDeConversa)?
    private var executorDeFerramentas: FerramentasDoModelo?

    private var modelo = "deepseek-chat"
    private var temperatura = 1.0
    private var maxTokens = 4096
    private var usaPonte = false

    // MARK: - Ciclo de vida

    /// Liga a tela ao que ela já tem: conversa aberta, contexto do SwiftData e a
    /// ponte do DSH (que vem pronta de quem monta o app, ou `nil`).
    @MainActor
    func preparar(conversa: Conversa?, contexto: ModelContext?, ponte: ServicoPonte?) {
        if self.conversa !== conversa {
            self.conversa = conversa
        }
        self.contexto = contexto
        self.ponte = ponte
    }

    /// Copia as preferências que o provedor precisa. Chamado quando a tela abre
    /// e quando o seletor de modelo muda, para o pedido refletir a escolha.
    @MainActor
    func configurar(modelo: String, temperatura: Double, maxTokens: Int, usaPonte: Bool) {
        self.modelo = modelo
        self.temperatura = temperatura
        self.maxTokens = maxTokens
        self.usaPonte = usaPonte
    }

    @MainActor
    func definirSessao(_ identificador: String?) {
        sessaoDaPonte = identificador
    }

    @MainActor
    func abrir(_ conversa: Conversa?) {
        self.conversa = conversa
        erro = nil
    }

    @MainActor
    func limparErro() {
        erro = nil
    }

    var temPonte: Bool { ponte != nil }

    // MARK: - Envio

    /// Manda o que está na barra de entrada. A mensagem do usuário entra no
    /// SwiftData na hora; a resposta só é salva quando o streaming termina ou é
    /// cancelado, e o texto parcial é o que vale.
    @MainActor
    func enviar(_ texto: String, anexos: [Anexo]) {
        let limpo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpo.isEmpty || !anexos.isEmpty, !estaRespondendo else { return }
        erro = nil
        estaRespondendo = true
        textoAoVivo = ""
        raciocinioAoVivo = ""
        tarefa?.cancel()
        tarefa = Task { [weak self] in
            await self?.executarEnvio(limpo, anexos: anexos)
        }
    }

    @MainActor
    func cancelar() {
        tarefa?.cancel()
        if let provedorDoEnvio {
            Task { await provedorDoEnvio.cancelar() }
        }
    }

    @MainActor
    private func executarEnvio(_ texto: String, anexos: [Anexo]) async {
        if conversa == nil {
            _ = criarConversa(comTitulo: texto)
        }
        guard let conversa else {
            estaRespondendo = false
            erro = "Não há conversa aberta para guardar essa mensagem."
            return
        }

        gravar(papel: .usuario, texto: texto, raciocinio: nil, anexos: anexos, em: conversa)

        guard let provedor = montarProvedor() else {
            estaRespondendo = false
            erro = usaPonte
                ? "A ponte do DSH não respondeu. Confira o endereço e o token em Ajustes."
                : "Falta a chave da DeepSeek. Cole a chave em Ajustes para conversar."
            return
        }

        provedorDoEnvio = provedor

        var resposta = ""
        var pensamento = ""
        // O que só existe nesta resposta: o texto da volta que pediu ferramenta e o
        // resultado de cada ferramenta. Vai como mensagem extra no pedido seguinte,
        // sem entrar no histórico salvo, porque isso não é fala de ninguém.
        var extras: [MensagemDoPedido] = []
        var voltas = 0

        do {
            while true {
                voltas += 1
                let pedido = montarPedido(de: conversa, acrescentando: extras)
                var chamadas: [ChamadaDeFerramenta] = []
                var textoDaVolta = ""

                for try await fragmento in provedor.responder(pedido) {
                    if Task.isCancelled { break }
                    switch fragmento {
                    case .raciocinio(let pedaco):
                        pensamento += pedaco
                        raciocinioAoVivo = pensamento
                    case .texto(let pedaco):
                        textoDaVolta += pedaco
                        resposta += pedaco
                        textoAoVivo = resposta
                    case .chamadaDeFerramenta(let chamada):
                        chamadas.append(chamada)
                    case .uso(_, _), .fim(_):
                        continue
                    }
                }

                if Task.isCancelled || chamadas.isEmpty || voltas >= 3 {
                    break
                }

                let nomes = chamadas.map(\.nome).joined(separator: ", ")
                pensamento += (pensamento.isEmpty ? "" : "\n\n") + "Usei a ferramenta \(nomes)."
                raciocinioAoVivo = pensamento

                if !textoDaVolta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    extras.append(MensagemDoPedido(papel: .assistente, texto: textoDaVolta))
                }
                for chamada in chamadas {
                    let resultado = await executarFerramenta(chamada)
                    extras.append(MensagemDoPedido(
                        papel: .usuario,
                        texto: "[resultado da ferramenta \(chamada.nome)]\n\(resultado)"
                    ))
                }
            }
        } catch is CancellationError {
            // Cancelar não apaga o que já chegou: o parcial é o que vale.
        } catch {
            erro = error.localizedDescription
        }

        if !resposta.isEmpty || !pensamento.isEmpty {
            gravar(
                papel: .assistente,
                texto: resposta,
                raciocinio: pensamento.isEmpty ? nil : pensamento,
                anexos: [],
                em: conversa
            )
        }

        textoAoVivo = ""
        raciocinioAoVivo = ""
        estaRespondendo = false
        provedorDoEnvio = nil
        tarefa = nil
    }

    // MARK: - Montagem do pedido

    /// Monta o pedido a partir do que está salvo, mais o que só vale nesta resposta
    /// (texto intermediário e resultado de ferramenta). As definições de ferramenta
    /// vão sempre, para o modelo poder pedir busca ou agenda quando precisar.
    @MainActor
    private func montarPedido(
        de conversa: Conversa,
        acrescentando extras: [MensagemDoPedido] = []
    ) -> PedidoDeConversa {
        let historico = conversa.mensagens
            .sorted { $0.criadaEm < $1.criadaEm }
            .filter { $0.papel != .sistema }
        var mensagens = historico.map { mensagem in
            MensagemDoPedido(papel: mensagem.papel, texto: mensagem.conteudo, anexos: mensagem.anexos)
        }
        mensagens.append(contentsOf: extras)
        return PedidoDeConversa(
            mensagens: mensagens,
            promptDeSistema: conversa.promptDeSistema,
            temperatura: temperatura,
            maxTokens: maxTokens,
            ferramentas: ferramentasDoApp().definicoes()
        )
    }

    /// O executor é um só por tela: ele guarda o `EKEventStore` e seria desperdício
    /// criar um por mensagem. Nascido dentro de método principal, porque a classe é
    /// `@MainActor` e o inicializador dela não pode rodar fora da tela.
    @MainActor
    private func ferramentasDoApp() -> FerramentasDoModelo {
        if let executorDeFerramentas { return executorDeFerramentas }
        let novo = FerramentasDoModelo()
        executorDeFerramentas = novo
        return novo
    }

    /// Roda a ferramenta e devolve sempre texto: falha vira resultado com motivo em
    /// português, porque derrubar a conversa por causa de uma busca não ajuda ninguém.
    @MainActor
    private func executarFerramenta(_ chamada: ChamadaDeFerramenta) async -> String {
        do {
            return try await ferramentasDoApp().executar(chamada)
        } catch {
            return "Não deu para usar a ferramenta \(chamada.nome): \(error.localizedDescription)"
        }
    }

    /// Quem responde: a sessão do DSH pela ponte ou a API da DeepSeek com a
    /// chave do cofre. Sem um dos dois, devolve `nil` e a tela diz o que falta.
    private func montarProvedor() -> (any ProvedorDeConversa)? {
        if usaPonte {
            guard let ponte else { return nil }
            if let sessaoDaPonte {
                ponte.definirSessao(sessaoDaPonte)
            }
            return ponte
        }
        guard let apiKey = try? CofreDeChaves.ler(ChaveDoCofre.apiKeyDeepSeek),
              !apiKey.isEmpty
        else { return nil }
        let servico = ServicoDeepSeek(apiKey: apiKey, modelo: modelo)
        return servico
    }

    // MARK: - Sessões da ponte

    @MainActor
    func carregarSessoes() async {
        guard let ponte else {
            sessoes = []
            erroDeSessoes = "Sem ponte configurada. O endereço e o token da ponte do DSH ficam em Ajustes."
            return
        }
        carregandoSessoes = true
        erroDeSessoes = nil
        defer { carregandoSessoes = false }
        do {
            sessoes = try await ponte.listarSessoes()
        } catch {
            sessoes = []
            erroDeSessoes = error.localizedDescription
        }
    }

    // MARK: - SwiftData

    @discardableResult
    @MainActor
    func criarConversa(comTitulo titulo: String) -> Conversa? {
        guard let contexto else { return nil }
        let nova = Conversa(
            id: UUID(),
            titulo: tituloCurto(de: titulo),
            criadaEm: Date(),
            atualizadaEm: Date(),
            fixada: false,
            anonima: false,
            promptDeSistema: nil,
            projetoID: nil,
            mensagens: []
        )
        contexto.insert(nova)
        conversa = nova
        try? contexto.save()
        return nova
    }

    @MainActor
    private func gravar(papel: Papel, texto: String, raciocinio: String?, anexos: [Anexo], em conversa: Conversa) {
        guard let contexto else { return }
        let mensagem = Mensagem(
            id: UUID(),
            papel: papel,
            conteudo: texto,
            raciocinio: raciocinio,
            criadaEm: Date(),
            anexos: anexos,
            conversa: conversa
        )
        contexto.insert(mensagem)
        conversa.atualizadaEm = Date()
        if conversa.titulo.isEmpty, papel == .usuario {
            conversa.titulo = tituloCurto(de: texto)
        }
        try? contexto.save()
    }

    private func tituloCurto(de texto: String) -> String {
        let linha = texto
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
        if linha.isEmpty { return "Conversa" }
        return linha.count > 42 ? String(linha.prefix(42)) + "…" : linha
    }
}
