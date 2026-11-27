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
    @Published private(set) var criandoSessao = false
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
        // A faixa de erro sobrevive a sair e voltar na mesma conversa: o motivo da
        // falha é justamente o que o usuário vai querer reler depois de conferir os
        // Ajustes. Só trocar de conversa limpa o aviso.
        let mesmaConversa = self.conversa?.id == conversa?.id
        self.conversa = conversa
        if !mesmaConversa { erro = nil }
    }

    @MainActor
    func limparErro() {
        erro = nil
    }

    var temPonte: Bool { ponte != nil }

    /// Troca a ponte da tela sem fechar nada: a folha de sessões chama isto
    /// quando o usuário escolhe outro computador na lista de instâncias.
    @MainActor
    func trocarPonte(_ nova: ServicoPonte?) {
        ponte = nova
    }

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

    /// Refaz a última resposta sem redigitar a pergunta.
    ///
    /// Apaga o que veio depois da última fala do usuário, inclusive a resposta
    /// que não agradou, e manda a mesma pergunta de novo. A pergunta não é
    /// gravada outra vez: reenviar criaria duas falas iguais no transcrito, e o
    /// histórico que vai para o modelo teria a mesma coisa duas vezes.
    @MainActor
    func repetirUltimaResposta() {
        guard !estaRespondendo, let conversa, contexto != nil else { return }
        let ordenadas = conversa.mensagens.sorted { $0.criadaEm < $1.criadaEm }
        guard let indice = ordenadas.lastIndex(where: { $0.papel == .usuario }) else { return }
        let pergunta = ordenadas[indice]

        if indice + 1 < ordenadas.count {
            for mensagem in ordenadas[(indice + 1)...] {
                contexto?.delete(mensagem)
            }
            try? contexto?.save()
        }

        erro = nil
        estaRespondendo = true
        textoAoVivo = ""
        raciocinioAoVivo = ""
        tarefa?.cancel()
        tarefa = Task { [weak self] in
            await self?.executarEnvio(pergunta.conteudo, anexos: pergunta.anexos, gravandoPergunta: false)
        }
    }

    @MainActor
    private func executarEnvio(_ texto: String, anexos: [Anexo], gravandoPergunta: Bool = true) async {
        if conversa == nil {
            _ = criarConversa(comTitulo: texto)
        }
        guard let conversa else {
            estaRespondendo = false
            erro = "Não há conversa aberta para guardar essa mensagem."
            return
        }

        if gravandoPergunta {
            gravar(papel: .usuario, texto: texto, raciocinio: nil, anexos: anexos, em: conversa)
        }

        // Motor da ponte sem sessão escolhida: abre uma aqui.
        //
        // Antes o envio parava e mandava escolher uma sessão na lista, e a lista
        // traz as sessões que já estão abertas no computador, inclusive a que está
        // respondendo naquele momento. Mandar a pergunta para dentro de uma sessão
        // ocupada devolve turno sem texto, que na tela vira "a sessão do DSH fechou
        // os eventos sem devolver texto". Criando a sessão do iPhone, a pergunta cai
        // numa conversa só dela, que responde.
        if usaPonte && sessaoDaPonte == nil, let nova = await criarSessaoNoDsh() {
            definirSessao(nova.id)
        } else if usaPonte, let escolhida = sessaoDaPonte, await sessaoOcupada(escolhida),
                  let nova = await criarSessaoNoDsh() {
            // A sessão escolhida está respondendo no computador. A pergunta entraria
            // na fila e só voltaria depois do turno de lá, que pode durar minutos.
            // Sessão nova responde agora, e a do computador segue em paz.
            definirSessao(nova.id)
        }

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

        // O que a API contou de gasto nesta resposta. A entrada é a da última
        // volta porque é ela que carrega a conversa inteira, ou seja, o tamanho
        // real do contexto; a saída é a soma das voltas, porque cada uma gastou.
        var entradaDoContexto: Int?
        var saidaTotal = 0

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
                    case .uso(let entrada, let saida):
                        if entrada > 0 { entradaDoContexto = entrada }
                        saidaTotal += saida
                    case .fim(_):
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
            // Cancelar não apaga o que já chegou: o parcial é o que vale. O caso de
            // cancelar antes do primeiro pedaço é tratado depois do laço, junto com
            // o do serviço que responde sem texto, porque os dois terminam aqui.
        } catch {
            erro = error.localizedDescription
        }

        if !resposta.isEmpty || !pensamento.isEmpty {
            gravar(
                papel: .assistente,
                texto: resposta,
                raciocinio: pensamento.isEmpty ? nil : pensamento,
                anexos: [],
                em: conversa,
                tokensDeEntrada: entradaDoContexto,
                tokensDeSaida: saidaTotal > 0 ? saidaTotal : nil
            )
        } else if erro == nil {
            // Fim sem nenhum pedaço de texto e sem erro: a tela mostraria a pergunta
            // sozinha, e o usuário não teria como saber que nada veio. Dizer sempre.
            erro = Task.isCancelled
                ? "A resposta foi interrompida antes de chegar texto, então nada foi guardado. Envie de novo para tentar outra vez."
                : "O serviço terminou a resposta sem mandar texto nenhum. Nada foi guardado; envie de novo para tentar outra vez."
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

    /// A sessão está respondendo no computador neste instante? A lista da ponte
    /// traz esse estado por sessão (`rodando`). Se a ponte não responder, devolve
    /// `false` e o envio segue com a sessão escolhida.
    @MainActor
    private func sessaoOcupada(_ identificador: String) async -> Bool {
        guard let ponte else { return false }
        guard let lista = try? await ponte.listarSessoes() else { return false }
        return lista.first { $0.id == identificador }?.rodando == true
    }

    /// Cria uma sessão nova no DSH pela ponte e devolve o resumo dela, pronto
    /// para abrir. Antes disto o app só listava sessões: quem não tinha nenhuma
    /// aberta no computador não tinha como começar uma conversa pelo iPhone.
    @MainActor
    func criarSessaoNoDsh() async -> SessaoResumo? {
        guard let ponte else {
            erroDeSessoes = "Sem ponte configurada. O endereço e o token da ponte do DSH ficam em Ajustes."
            return nil
        }
        criandoSessao = true
        erroDeSessoes = nil
        defer { criandoSessao = false }
        do {
            let id = try await ponte.criarSessao()
            await carregarSessoes()
            if let achada = sessoes.first(where: { $0.id == id }) { return achada }
            return SessaoResumo(
                id: id,
                curto: String(id.suffix(8)),
                titulo: "Sessão nova",
                rodando: false,
                vazia: true,
                cwd: nil,
                atualizadoEm: nil,
                contexto: 0,
                tokens: nil,
                turnos: 0,
                seq: 0,
                aberta: true,
                arquivada: false,
                grupo: nil,
                grupoId: nil
            )
        } catch {
            erroDeSessoes = error.localizedDescription
            return nil
        }
    }

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
    private func gravar(
        papel: Papel,
        texto: String,
        raciocinio: String?,
        anexos: [Anexo],
        em conversa: Conversa,
        tokensDeEntrada: Int? = nil,
        tokensDeSaida: Int? = nil
    ) {
        guard let contexto else { return }
        let mensagem = Mensagem(
            id: UUID(),
            papel: papel,
            conteudo: texto,
            raciocinio: raciocinio,
            criadaEm: Date(),
            anexos: anexos,
            conversa: conversa,
            tokensDeEntrada: tokensDeEntrada,
            tokensDeSaida: tokensDeSaida
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
