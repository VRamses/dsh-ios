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
                        emitir(.raciocinio(raciocinio))
                    }
                    if let texto = delta["content"] as? String, !texto.isEmpty {
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
        emitir(.fim(motivo: motivoFinal))
    }

    private static func corpo(pedido: PedidoDeConversa, modelo: String) throws -> Data {
        var mensagens: [[String: Any]] = []
        if let sistema = pedido.promptDeSistema, !sistema.isEmpty {
            mensagens.append(["role": "system", "content": sistema])
        }
        for mensagem in pedido.mensagens {
            mensagens.append([
                "role": papelNaAPI(mensagem.papel),
                "content": textoComAnexos(mensagem),
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

    private static func textoComAnexos(_ mensagem: MensagemDoPedido) -> String {
        guard !mensagem.anexos.isEmpty else { return mensagem.texto }
        var partes: [String] = [mensagem.texto]
        for anexo in mensagem.anexos {
            let conteudo = anexo.texto.isEmpty ? "(sem texto extraído)" : anexo.texto
            partes.append("[anexo: \(anexo.nome), tipo \(anexo.tipo.rawValue)]\n\(conteudo)")
        }
        return partes.joined(separator: "\n\n")
    }

    private static func ehCancelamento(_ erro: Error) -> Bool {
        if erro is CancellationError { return true }
        if let erroDeURL = erro as? URLError, erroDeURL.code == .cancelled { return true }
        return false
    }
}
