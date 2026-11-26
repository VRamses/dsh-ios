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
        guard !apiKey.isEmpty else { throw ErroDaConversa.semChave }

        var requisicao = URLRequest(url: endereco)
        requisicao.httpMethod = "POST"
        requisicao.timeoutInterval = 180
        requisicao.setValue("application/json", forHTTPHeaderField: "Content-Type")
        requisicao.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        requisicao.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        requisicao.httpBody = try corpo(pedido: pedido, modelo: modelo)

        let (bytes, resposta) = try await sessao.bytes(for: requisicao)
        guard let http = resposta as? HTTPURLResponse else {
            throw ErroDaConversa.rede("resposta sem HTTP")
        }
        guard http.statusCode == 200 else {
            var corpoDoErro = ""
            for try await linha in bytes.lines {
                corpoDoErro += linha
                if corpoDoErro.count > 400 { break }
            }
            throw ErroDaConversa.http(http.statusCode, corpoDoErro)
        }

        var acumulador = AcumuladorDeSSE()
        var chamadas: [Int: (id: String, nome: String, argumentos: String)] = [:]
        var motivoFinal: String?
        // Quantos pedaços chegaram de fato. Um 200 sem nenhum pedaço deixaria a
        // conversa sem resposta e sem erro, e a tela em silêncio; por isso a conta
        // existe e a falta vira erro no fim.
        var pedacos = 0

        for try await linha in bytes.lines {
            if Task.isCancelled { throw CancellationError() }
            guard let quadro = acumulador.consumir(linha: linha) else { continue }
            if quadro.dados == "[DONE]" { break }
            guard let dados = quadro.dados.data(using: .utf8),
                  let raiz = (try? JSONSerialization.jsonObject(with: dados)) as? [String: Any]
            else { continue }

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

        for indice in chamadas.keys.sorted() {
            guard let chamada = chamadas[indice], !chamada.nome.isEmpty else { continue }
            emitir(.chamadaDeFerramenta(
                ChamadaDeFerramenta(id: chamada.id, nome: chamada.nome, argumentos: chamada.argumentos)
            ))
        }
        // Nem texto, nem raciocínio, nem ferramenta: a tela não teria o que mostrar e
        // o usuário veria a mensagem dele sozinha. Erro dito é melhor que silêncio.
        if pedacos == 0 && chamadas.isEmpty {
            let motivo = motivoFinal.map { " (motivo: \($0))" } ?? ""
            throw ErroDaConversa.rede(
                "a API respondeu 200 e não mandou nenhum pedaço de texto\(motivo)"
            )
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

    /// Pedido mínimo à API, sem streaming, só para a tela de Ajustes dizer o que
    /// o telefone recebe de verdade. Devolve o código HTTP e o começo do corpo,
    /// que é o que separa chave errada (401), modelo errado (400) e rede fora.
    static func diagnosticar(chave: String, modelo: String) async -> String {
        let limpa = chave.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpa.isEmpty else {
            return "Nenhuma chave no cofre. Cole a chave ou importe do computador."
        }
        guard let endereco = URL(string: "https://api.deepseek.com/chat/completions") else {
            return "Endereço da API inválido."
        }

        var requisicao = URLRequest(url: endereco)
        requisicao.httpMethod = "POST"
        requisicao.timeoutInterval = 60
        requisicao.setValue("application/json", forHTTPHeaderField: "Content-Type")
        requisicao.setValue("Authorization", forHTTPHeaderField: "Bearer \(limpa)")

        let corpo: [String: Any] = [
            "model": modelo,
            "messages": [["role": "user", "content": "responda apenas: ok"]],
            "max_tokens": 16,
            "stream": false,
        ]
        do {
            requisicao.httpBody = try JSONSerialization.data(withJSONObject: corpo)
            let (dados, resposta) = try await URLSession.shared.data(for: requisicao)
            let status = (resposta as? HTTPURLResponse)?.statusCode ?? 0
            let texto = String(data: dados, encoding: .utf8) ?? ""
            let inicio = texto
                .replacingOccurrences(of: "\n", with: " ")
                .prefix(240)
            return "HTTP \(status). Resposta: \(inicio)"
        } catch {
            return "Não chegou a responder: \(error.localizedDescription)"
        }
    }
}
