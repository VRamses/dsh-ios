import Foundation

final class ServicoDeepSeek: ProvedorDeConversa {
    private let apiKey: String
    private let sessao: URLSession
    private let endereco: URL?
    private var tarefa: Task<Void, Never>?

    var modelo: String

    init(apiKey: String, modelo: String = "deepseek-chat", sessao: URLSession = .shared) {
        self.apiKey = apiKey
        self.modelo = modelo
        self.sessao = sessao
        self.endereco = URL(string: "https://api.deepseek.com/chat/completions")
    }

    func responder(_ pedido: PedidoDeConversa) -> AsyncThrowingStream<FragmentoDaResposta, Error> {
        tarefa?.cancel()
        let apiKey = self.apiKey
        let sessao = self.sessao
        let endereco = self.endereco
        let modelo = self.modelo
        return AsyncThrowingStream { continuacao in
            let tarefa = Task {
                do {
                    try await ServicoDeepSeek.transmitir(
                        pedido: pedido,
                        apiKey: apiKey,
                        modelo: modelo,
                        endereco: endereco,
                        sessao: sessao
                    ) { fragmento in
                        continuacao.yield(fragmento)
                    }
                    continuacao.finish()
                } catch {
                    if ServicoDeepSeek.ehCancelamento(error) {
                        continuacao.finish()
                    } else {
                        continuacao.finish(throwing: error)
                    }
                }
            }
            self.tarefa = tarefa
            continuacao.onTermination = { _ in
                tarefa.cancel()
            }
        }
    }

    func cancelar() async {
        tarefa?.cancel()
        tarefa = nil
    }

    private static func transmitir(
        pedido: PedidoDeConversa,
        apiKey: String,
        modelo: String,
        endereco: URL?,
        sessao: URLSession,
        emitir: (FragmentoDaResposta) -> Void
    ) async throws {
        guard let endereco else { throw ErroDaConversa.enderecoInvalido }
        let chaveDoPedido = chaveParaCabecalho(apiKey).chave
        guard !chaveDoPedido.isEmpty else { throw ErroDaConversa.semChave }

        var requisicao = URLRequest(url: endereco)
        requisicao.httpMethod = "POST"
        requisicao.timeoutInterval = 180
        requisicao.setValue("application/json", forHTTPHeaderField: "Content-Type")
        requisicao.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // Não mexer no Accept-Encoding: quando o app define esse cabeçalho à mão, o
        // URLSession para de descomprimir a resposta. Se o servidor comprimir de
        // qualquer jeito, o leitor de linhas recebe bytes crus, não reconhece
        // quadro nenhum e o stream termina em 200 com zero pedaços. Deixando o
        // URLSession negociar, ele pede gzip e descomprime sozinho.
        requisicao.setValue("Bearer \(chaveDoPedido)", forHTTPHeaderField: "Authorization")
        requisicao.httpBody = try corpo(pedido: pedido, modelo: modelo)

        var acumulador = AcumuladorDeSSE()
        var chamadas: [Int: (id: String, nome: String, argumentos: String)] = [:]
        var motivoFinal: String?
        // Quantos pedaços chegaram de fato. Um 200 sem nenhum pedaço deixaria a
        // conversa sem resposta e sem erro, e a tela em silêncio; por isso a conta
        // existe e a falta vira erro no fim.
        var pedacos = 0
        // Primeiras linhas cruas do stream. Só servem para o erro conseguir dizer o
        // que chegou quando nada foi reconhecido, que é o caso em que a tela hoje
        // fica muda.
        var cruas: [String] = []
        // Quantas linhas o stream entregou, reconhecidas ou não. É o número que
        // separa "o servidor não mandou nada" de "mandou algo que não foi lido".
        var linhasRecebidas = 0
        var codigo = 0
        var corpoDoErro = ""
        var httpDaResposta: HTTPURLResponse?

        let leitor = LeitorDeLinhas()
        lendo: for try await evento in leitor.abrir(requisicao, configuracao: sessao.configuration) {
            if Task.isCancelled {
                leitor.cancelar()
                throw CancellationError()
            }
            switch evento {
            case .cabecalho(let resposta):
                httpDaResposta = resposta
                codigo = resposta.statusCode
            case .linha(let linha):
                linhasRecebidas += 1
                // Resposta que não é 200 não entra no leitor de quadro: o motivo do
                // erro vem no corpo e é ele que a tela mostra.
                if codigo != 200 {
                    if corpoDoErro.count < 400 { corpoDoErro += linha }
                    continue
                }
                guard let quadro = acumulador.consumir(linha: linha) else { continue }
                if quadro.dados == "[DONE]" { break lendo }
                if cruas.count < 3, !quadro.dados.isEmpty {
                    cruas.append(String(quadro.dados.prefix(160)))
                }
                guard let dados = quadro.dados.data(using: .utf8),
                      let raiz = (try? JSONSerialization.jsonObject(with: dados)) as? [String: Any]
                else { continue }

                // A API também recusa dentro de um stream que já começou com 200, e o
                // motivo vem neste campo. Antes ele era descartado.
                if let erro = raiz["error"] as? [String: Any],
                   let mensagem = erro["message"] as? String {
                    throw ErroDaConversa.rede("a API recusou no meio do stream: \(mensagem)")
                }

                if let escolhas = raiz["choices"] as? [[String: Any]], let primeira = escolhas.first {
                    if let delta = primeira["delta"] as? [String: Any] {
                        if let raciocinio = delta["reasoning_content"] as? String, !raciocinio.isEmpty {
                            pedacos += 1
                            emitir(.raciocinio(raciocinio))
                        }
                        if let texto = delta["content"] as? String, !texto.isEmpty {
                            pedacos += 1
                            emitir(.texto(texto))
                        }
                        if let ferramentas = delta["tool_calls"] as? [[String: Any]] {
                            for item in ferramentas {
                                let indice = item["index"] as? Int ?? 0
                                let funcao = item["function"] as? [String: Any] ?? [:]
                                var atual = chamadas[indice] ?? (
                                    id: item["id"] as? String ?? "chamada-\(indice)",
                                    nome: "",
                                    argumentos: ""
                                )
                                if let identificador = item["id"] as? String, !identificador.isEmpty {
                                    atual.id = identificador
                                }
                                if let nome = funcao["name"] as? String, !nome.isEmpty {
                                    atual.nome = nome
                                }
                                if let argumentos = funcao["arguments"] as? String {
                                    atual.argumentos += argumentos
                                }
                                chamadas[indice] = atual
                            }
                        }
                    }
                    if let motivo = primeira["finish_reason"] as? String {
                        motivoFinal = motivo
                    }
                }

                if let uso = raiz["usage"] as? [String: Any] {
                    let entrada = uso["prompt_tokens"] as? Int ?? 0
                    let saida = uso["completion_tokens"] as? Int ?? 0
                    emitir(.uso(entrada: entrada, saida: saida))
                }
            }
        }

        // A recusa fora do 200 é lida até o fim do corpo e o erro sai aqui, depois
        // que a resposta terminou, e não no meio do stream.
        if codigo != 0 && codigo != 200 {
            throw ErroDaConversa.http(codigo, corpoDoErro)
        }
        guard codigo == 200 else {
            throw ErroDaConversa.rede("resposta sem HTTP")
        }

        // Chamada sem nome não vira fragmento nenhum, então ela também conta como
        // "nada a mostrar" na conferência abaixo.
        var completas: [ChamadaDeFerramenta] = []
        for indice in chamadas.keys.sorted() {
            guard let chamada = chamadas[indice], !chamada.nome.isEmpty else { continue }
            completas.append(ChamadaDeFerramenta(
                id: chamada.id, nome: chamada.nome, argumentos: chamada.argumentos
            ))
        }
        // Nem texto, nem raciocínio, nem ferramenta: a tela não teria o que mostrar e
        // o usuário veria a mensagem dele sozinha. Erro dito é melhor que silêncio.
        if pedacos == 0 && completas.isEmpty {
            let motivo = motivoFinal.map { " (motivo: \($0))" } ?? ""
            let mostra = cruas.isEmpty ? "" : " (primeiras linhas: \(cruas.joined(separator: " | ")))"
            // Cabeçalhos e contagem de linhas entram no erro porque são a única
            // pista disponível no aparelho: sem eles, "200 sem pedaço" não diz se
            // o corpo veio vazio ou veio comprimido.
            let comprimido = httpDaResposta?.value(forHTTPHeaderField: "Content-Encoding") ?? "nenhuma"
            let tipoDoCorpo = httpDaResposta?.value(forHTTPHeaderField: "Content-Type") ?? "sem tipo"
            throw ErroDaConversa.rede(
                "a API respondeu 200 e não mandou nenhum pedaço de texto\(motivo)\(mostra)"
                    + " (linhas: \(linhasRecebidas), corpo: \(tipoDoCorpo), codificação: \(comprimido))"
            )
        }
        for chamada in completas {
            emitir(.chamadaDeFerramenta(chamada))
        }
        emitir(.fim(motivo: motivoFinal))
    }

    private static func corpo(pedido: PedidoDeConversa, modelo: String) throws -> Data {
        var mensagens: [[String: Any]] = []
        if let sistema = pedido.promptDeSistema, !sistema.isEmpty {
            mensagens.append(["role": "system", "content": sistema])
        }
        // Foto pesa no corpo do pedido, então só as duas últimas falas do usuário levam a
        // imagem; as anteriores seguem com o texto já reconhecido delas, que é o que a
        // conversa longa precisa para continuar fazendo sentido.
        let falasDoUsuario = pedido.mensagens.indices.filter { pedido.mensagens[$0].papel == .usuario }
        let comImagem = Set(falasDoUsuario.suffix(2))
        for indice in pedido.mensagens.indices {
            let mensagem = pedido.mensagens[indice]
            mensagens.append([
                "role": papelNaAPI(mensagem.papel),
                "content": conteudo(mensagem, permitirImagem: comImagem.contains(indice)),
            ])
        }

        var corpo: [String: Any] = [
            "model": modelo,
            "messages": mensagens,
            "stream": true,
            "max_tokens": max(pedido.maxTokens, 256),
            "stream_options": ["include_usage": true],
        ]

        let ehReasoner = modelo.lowercased().contains("reasoner")
        if !ehReasoner {
            corpo["temperature"] = min(max(pedido.temperatura, 0), 2)
            if !pedido.ferramentas.isEmpty {
                corpo["tools"] = pedido.ferramentas.map { ferramenta -> [String: Any] in
                    let esquema: [String: Any] = ferramenta.parametros
                        ?? ["type": "object", "properties": [String: Any]()]
                    let funcao: [String: Any] = [
                        "name": ferramenta.nome,
                        "description": ferramenta.descricao,
                        "parameters": esquema,
                    ]
                    return ["type": "function", "function": funcao]
                }
            }
        }

        guard JSONSerialization.isValidJSONObject(corpo) else {
            throw ErroDaConversa.rede("o pedido gerou JSON inválido")
        }
        return try JSONSerialization.data(withJSONObject: corpo)
    }

    private static func papelNaAPI(_ papel: Papel) -> String {
        switch papel {
        case .usuario: return "user"
        case .assistente: return "assistant"
        case .sistema: return "system"
        }
    }

    /// Conteúdo da mensagem no formato da API. Sem foto é texto puro, que é o caso de
    /// quase tudo. Com foto vira lista de blocos: o texto do anexo primeiro e a imagem
    /// em base64 depois, que é como o modelo passa a ver a foto em vez de só ler o OCR.
    /// Só mensagem do usuário leva imagem, porque a API recusa imagem em resposta do
    /// assistente, e foto antiga decodificada sem bytes (chave ausente) cai no texto.
    private static func conteudo(_ mensagem: MensagemDoPedido, permitirImagem: Bool) -> Any {
        let imagens = (permitirImagem && mensagem.papel == .usuario)
            ? mensagem.anexos.filter { !($0.imagemBase64 ?? "").isEmpty }
            : []
        let texto = textoComAnexos(mensagem, imagemViaja: !imagens.isEmpty)
        guard !imagens.isEmpty else { return texto }

        var blocos: [[String: Any]] = []
        if !texto.isEmpty {
            blocos.append(["type": "text", "text": texto])
        }
        for anexo in imagens {
            guard let base64 = anexo.imagemBase64 else { continue }
            blocos.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(base64)"],
            ])
        }
        return blocos
    }

    private static func textoComAnexos(
        _ mensagem: MensagemDoPedido,
        imagemViaja: Bool
    ) -> String {
        guard !mensagem.anexos.isEmpty else { return mensagem.texto }
        var partes: [String] = [mensagem.texto]
        for anexo in mensagem.anexos {
            let conteudo = anexo.texto.isEmpty ? "(sem texto extraído)" : anexo.texto
            let cabecalho: String
            if anexo.tipo == .imagem, imagemViaja, !(anexo.imagemBase64 ?? "").isEmpty {
                cabecalho = "[anexo: \(anexo.nome), tipo imagem, a foto segue anexada nesta mensagem; o texto abaixo foi reconhecido por OCR e pode ter erro]"
            } else if anexo.tipo == .imagem {
                cabecalho = "[anexo: \(anexo.nome), tipo imagem, a foto não vai nesta mensagem, só o texto reconhecido]"
            } else {
                cabecalho = "[anexo: \(anexo.nome), tipo \(anexo.tipo.rawValue)]"
            }
            partes.append("\(cabecalho)\n\(conteudo)")
        }
        return partes.joined(separator: "\n\n")
    }

    private static func ehCancelamento(_ erro: Error) -> Bool {
        if erro is CancellationError { return true }
        if let erroDeURL = erro as? URLError, erroDeURL.code == .cancelled { return true }
        return false
    }

    // MARK: - Diagnóstico da chave

    /// Devolve só o que pode viajar num cabeçalho HTTP, e quantos caracteres
    /// saíram. Caractere fora do ASCII visível (BOM colado na frente, espaço de
    /// largura zero, quebra de linha no meio) faz o iOS descartar o cabeçalho
    /// `Authorization` inteiro no caminho: o pedido chega na API sem chave
    /// nenhuma e a resposta é 401, como se o cofre estivesse vazio.
    static func chaveParaCabecalho(_ bruto: String) -> (chave: String, removidos: Int) {
        let filtrada = bruto.filter { caractere in
            guard let ascii = caractere.asciiValue else { return false }
            return ascii > 0x20 && ascii < 0x7F
        }
        return (filtrada, bruto.count - filtrada.count)
    }

    /// Pedido mínimo à API usando o cabeçalho indicado, sem streaming.
    private static func pedirTeste(
        valor: String,
        cabecalho: String,
        modelo: String
    ) async -> (status: Int, corpo: String) {
        guard let endereco = URL(string: "https://api.deepseek.com/chat/completions") else {
            return (0, "endereço da API inválido")
        }
        var requisicao = URLRequest(url: endereco)
        requisicao.httpMethod = "POST"
        requisicao.timeoutInterval = 60
        requisicao.setValue("application/json", forHTTPHeaderField: "Content-Type")
        requisicao.setValue(valor, forHTTPHeaderField: cabecalho)
        let corpoPedido: [String: Any] = [
            "model": modelo,
            "messages": [["role": "user", "content": "responda apenas: ok"]],
            "max_tokens": 16,
            "stream": false,
        ]
        do {
            requisicao.httpBody = try JSONSerialization.data(withJSONObject: corpoPedido)
            let (dados, resposta) = try await URLSession.shared.data(for: requisicao)
            let status = (resposta as? HTTPURLResponse)?.statusCode ?? 0
            let texto = (String(data: dados, encoding: .utf8) ?? "")
                .replacingOccurrences(of: "\n", with: " ")
            return (status, String(texto.prefix(240)))
        } catch {
            return (0, "não chegou a responder: \(error.localizedDescription)")
        }
    }

    /// Pedido mínimo à API, sem streaming, só para a tela de Ajustes dizer o que
    /// o telefone recebe de verdade. Devolve o código HTTP e o começo do corpo,
    /// que é o que separa chave errada (401), cabeçalho descartado (401 em
    /// `Authorization` e 200 em `x-api-key`) e rede fora.
    static func diagnosticar(chave: String, modelo: String) async -> String {
        let aparada = chave.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !aparada.isEmpty else {
            return "Nenhuma chave no cofre. Cole a chave ou importe do computador."
        }
        let (limpa, removidos) = chaveParaCabecalho(aparada)
        guard !limpa.isEmpty else {
            return "A chave guardada tem \(aparada.count) caracteres e nenhum serve num cabeçalho HTTP."
        }
        // O tamanho e a ponta entram no relatório porque chave com caractere
        // invisível colado passa na tela e muda de comportamento no pedido.
        let ponta = limpa.count >= 4 ? String(limpa.suffix(4)) : limpa
        let ficha = "Chave com \(limpa.count) caracteres, terminando em \(ponta)"
        let invisivel = removidos == 0
            ? "nenhum caractere invisível"
            : "\(removidos) caractere invisível removido"

        let primeira = await pedirTeste(
            valor: "Bearer \(limpa)",
            cabecalho: "Authorization",
            modelo: modelo
        )
        if primeira.status == 200 {
            return "HTTP 200. \(ficha); \(invisivel). A chave vale."
        }
        // A API aceita a mesma chave em `x-api-key`. Se ali der 200, o problema
        // não é a chave: foi o cabeçalho que o iOS descartou.
        let segunda = await pedirTeste(valor: limpa, cabecalho: "x-api-key", modelo: modelo)
        var relatorio = "HTTP \(primeira.status). \(ficha); \(invisivel). Resposta: \(primeira.corpo)."
        if segunda.status == 200 {
            relatorio += " Com x-api-key deu 200: o iOS descartou o cabeçalho Authorization."
        } else {
            relatorio += " Com x-api-key também falhou (HTTP \(segunda.status)): \(segunda.corpo)"
        }
        return relatorio
    }
}
