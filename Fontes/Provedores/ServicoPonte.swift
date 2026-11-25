import Foundation

enum ModoDeEnvio: String {
    case queue
    case steer
}

struct SessaoResumo: Identifiable, Hashable {
    var id: String
    var curto: String
    var titulo: String
    var rodando: Bool
    var vazia: Bool
    var cwd: String?
    var atualizadoEm: Double?
    var contexto: Int
    var tokens: Int?
    var turnos: Int
    var seq: Int
    var aberta: Bool
    var arquivada: Bool
    var grupo: String?
    var grupoId: String?
}

struct Registro: Identifiable, Hashable {
    var seq: Int
    var tipo: String
    var em: String?
    var dados: String
    var textoDoAssistente: String?
    var raciocinioDoAssistente: String?
    var textoDoUsuario: String?

    var id: Int { seq }
}

struct EventoDaPonte {
    var nome: String
    var json: String
    var registros: [Registro]
    var erro: String?
    var sessaoID: String?
}

struct ResultadoDaBusca: Identifiable, Hashable {
    var id: String
    var titulo: String
    var trecho: String
    var sessaoID: String?
    var seq: Int?
}

struct SaudeDaPonte: Equatable {
    var ok: Bool
    var versao: String?
    var rotulo: String?
    var maquina: String?
    var detalhe: String?
}

/// O que a ponte devolveu quando o app pediu as chaves do cofre da máquina.
struct ChavesImportadas {
    var chaves: [String: String]
    var faltando: [String]
}

final class ServicoPonte: ProvedorDeConversa {
    private let endereco: String
    private let token: String
    private let sessao: URLSession
    private var tarefaDaResposta: Task<Void, Never>?
    private var tarefaDeEventos: Task<Void, Never>?

    var sessaoID: String?

    init(endereco: String, token: String, sessaoID: String? = nil, sessao: URLSession = .shared) {
        self.endereco = endereco
        self.token = token
        self.sessaoID = sessaoID
        self.sessao = sessao
    }

    @MainActor
    static func aPartirDasPreferencias() -> ServicoPonte? {
        let preferencias = Preferencias.compartilhada
        guard !preferencias.enderecoDaPonte.isEmpty else { return nil }
        guard let token = try? CofreDeChaves.ler(ChaveDoCofre.tokenDaPonte), !token.isEmpty else {
            return nil
        }
        return ServicoPonte(endereco: preferencias.enderecoDaPonte, token: token)
    }

    func definirSessao(_ id: String) {
        sessaoID = id
    }

    var temToken: Bool {
        !token.isEmpty
    }

    /// Traz do cofre da máquina da ponte as chaves que já estão lá.
    ///
    /// O endpoint `POST /v1/credenciais/llm/exportar` existe para transportar
    /// chave de motor entre instâncias e exige o cabeçalho `x-ponte-exportar: 1`
    /// de propósito: assim o valor não sai numa leitura distraída. O `Bearer`
    /// continua sendo o token da ponte, o mesmo que a conversa já usa, então
    /// nada precisa ser configurado a mais para importar.
    ///
    /// Nenhum valor desta resposta é impresso em log: só o nome das chaves
    /// aparece nas mensagens da tela.
    func importarChaves(nomes: [String]) async throws -> ChavesImportadas {
        guard !nomes.isEmpty else { return ChavesImportadas(chaves: [:], faltando: []) }
        let (objeto, _) = try await pedir(
            "/v1/credenciais/llm/exportar",
            metodo: "POST",
            corpo: ["chaves": nomes],
            cabecalhos: ["x-ponte-exportar": "1"]
        )
        let raiz = objeto as? [String: Any] ?? [:]
        let recebidas = raiz["chaves"] as? [String: Any] ?? [:]
        var limpas: [String: String] = [:]
        for (nome, bruto) in recebidas {
            guard let valor = bruto as? String else { continue }
            let semEspaco = valor.trimmingCharacters(in: .whitespacesAndNewlines)
            if !semEspaco.isEmpty { limpas[nome] = semEspaco }
        }
        let faltando = (raiz["faltando"] as? [String]) ?? nomes.filter { limpas[$0] == nil }
        return ChavesImportadas(chaves: limpas, faltando: faltando)
    }

    func listarSessoes() async throws -> [SessaoResumo] {
        let (objeto, _) = try await pedir("/v1/sessoes")
        let raiz = objeto as? [String: Any] ?? [:]
        let itens = (raiz["itens"] as? [[String: Any]]) ?? (raiz["sessoes"] as? [[String: Any]]) ?? []
        return itens.map(SessaoResumo.iniciar(com:))
    }

    func criarSessao() async throws -> String {
        let (objeto, _) = try await pedir("/v1/sessoes", metodo: "POST", corpo: [:])
        let raiz = objeto as? [String: Any] ?? [:]
        guard let id = (raiz["sessionId"] as? String) ?? (raiz["id"] as? String), !id.isEmpty else {
            throw ErroDaConversa.rede("a ponte não devolveu o id da sessão criada")
        }
        sessaoID = id
        return id
    }

    func enviar(texto: String, modo: ModoDeEnvio = .queue) async throws {
        let id = try sessaoAtual()
        _ = try await pedir(
            "/v1/sessoes/\(id)/mensagem",
            metodo: "POST",
            corpo: ["texto": texto, "modo": modo.rawValue]
        )
    }

    func cancelarSessao() async throws {
        let id = try sessaoAtual()
        _ = try await pedir("/v1/sessoes/\(id)/cancelar", metodo: "POST", corpo: [:])
    }

    func pagina(throughSeq: Int, maxMessages: Int? = nil) async throws -> [Registro] {
        let id = try sessaoAtual()
        var caminho = "/v1/sessoes/\(id)/pagina?throughSeq=\(throughSeq)"
        if let maxMessages {
            caminho += "&maxMessages=\(maxMessages)"
        }
        let (objeto, _) = try await pedir(caminho)
        let raiz = objeto as? [String: Any] ?? [:]
        let lista = (raiz["registros"] as? [[String: Any]]) ?? (raiz["itens"] as? [[String: Any]]) ?? []
        return lista.compactMap(Registro.iniciar(com:))
    }

    func buscar(termo: String) async throws -> [ResultadoDaBusca] {
        guard let codificado = termo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw ErroDaConversa.enderecoInvalido
        }
        let (objeto, _) = try await pedir("/v1/busca?q=\(codificado)&termo=\(codificado)")
        let raiz = objeto as? [String: Any] ?? [:]
        let bruto = raiz["itens"] ?? raiz["sessoes"] ?? raiz["resultados"] ?? raiz["resposta"]
        var lista: [[String: Any]] = []
        if let direta = bruto as? [[String: Any]] {
            lista = direta
        } else if let aninhada = bruto as? [String: Any] {
            lista = (aninhada["itens"] as? [[String: Any]])
                ?? (aninhada["sessoes"] as? [[String: Any]])
                ?? (aninhada["hits"] as? [[String: Any]])
                ?? []
        }
        return lista.enumerated().compactMap { indice, item in
            ResultadoDaBusca.iniciar(com: item, indice: indice)
        }
    }

    func saude() async throws -> SaudeDaPonte {
        let (objeto, _) = try await pedir("/v1/saude")
        let raiz = objeto as? [String: Any] ?? [:]
        let dsh = raiz["dsh"] as? [String: Any]
        return SaudeDaPonte(
            ok: raiz["ok"] as? Bool ?? false,
            versao: raiz["versao"] as? String,
            rotulo: raiz["rotulo"] as? String,
            maquina: raiz["maquina"] as? String,
            detalhe: dsh?["erro"] as? String
        )
    }

    func eventos() -> AsyncThrowingStream<EventoDaPonte, Error> {
        tarefaDaResposta?.cancel()
        tarefaDeEventos?.cancel()
        return fluxoDeEventos()
    }

    private func fluxoDeEventos() -> AsyncThrowingStream<EventoDaPonte, Error> {
        AsyncThrowingStream { continuacao in
            let tarefa = Task { [self] in
                do {
                    let id = try sessaoAtual()
                    guard let url = url("/v1/sessoes/\(id)/eventos") else {
                        throw ErroDaConversa.enderecoInvalido
                    }
                    guard !token.isEmpty else { throw ErroDaConversa.semToken }
                    var requisicao = URLRequest(url: url)
                    requisicao.timeoutInterval = 3600
                    requisicao.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    requisicao.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    let (bytes, resposta) = try await sessao.bytes(for: requisicao)
                    let codigo = (resposta as? HTTPURLResponse)?.statusCode ?? 0
                    guard codigo == 200 else {
                        throw ErroDaConversa.http(codigo, "a ponte recusou a abertura dos eventos")
                    }
                    var acumulador = AcumuladorDeSSE()
                    for try await linha in bytes.lines {
                        if Task.isCancelled { throw CancellationError() }
                        guard let quadro = acumulador.consumir(linha: linha) else { continue }
                        continuacao.yield(ServicoPonte.evento(de: quadro))
                    }
                    continuacao.finish()
                } catch {
                    if ServicoPonte.ehCancelamento(error) {
                        continuacao.finish()
                    } else {
                        continuacao.finish(throwing: error)
                    }
                }
            }
            self.tarefaDeEventos = tarefa
            continuacao.onTermination = { _ in
                tarefa.cancel()
            }
        }
    }

    func responder(_ pedido: PedidoDeConversa) -> AsyncThrowingStream<FragmentoDaResposta, Error> {
        tarefaDaResposta?.cancel()
        let texto = ServicoPonte.textoDoPedido(pedido)
        return AsyncThrowingStream { continuacao in
            let tarefa = Task { [self] in
                do {
                    try await enviar(texto: texto, modo: .queue)
                    var textoEmitido = ""
                    var raciocinioEmitido = ""
                    for try await evento in fluxoDeEventos() {
                        if let erro = evento.erro {
                            throw ErroDaConversa.rede(erro)
                        }
                        for registro in evento.registros {
                            if let raciocinio = registro.raciocinioDoAssistente,
                               let pedaco = delta(raciocinio, emitido: raciocinioEmitido) {
                                continuacao.yield(.raciocinio(pedaco))
                                raciocinioEmitido = raciocinio
                            }
                            if let novo = registro.textoDoAssistente,
                               let pedaco = delta(novo, emitido: textoEmitido) {
                                continuacao.yield(.texto(pedaco))
                                textoEmitido = novo
                            }
                        }
                    }
                    continuacao.yield(.fim(motivo: nil))
                    continuacao.finish()
                } catch {
                    if ServicoPonte.ehCancelamento(error) {
                        continuacao.finish()
                    } else {
                        continuacao.finish(throwing: error)
                    }
                }
            }
            self.tarefaDaResposta = tarefa
            continuacao.onTermination = { _ in
                tarefa.cancel()
            }
        }
    }

    func cancelar() async {
        tarefaDaResposta?.cancel()
        tarefaDeEventos?.cancel()
        tarefaDaResposta = nil
        tarefaDeEventos = nil
    }

    private func delta(_ texto: String, emitido: String) -> String? {
        guard texto.count > emitido.count, texto.hasPrefix(emitido) else { return nil }
        return String(texto.dropFirst(emitido.count))
    }

    private func sessaoAtual() throws -> String {
        guard let sessaoID, !sessaoID.isEmpty else {
            throw ErroDaConversa.rede("nenhuma sessão da ponte está aberta")
        }
        return sessaoID
    }

    private func url(_ caminho: String) -> URL? {
        var base = endereco.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") {
            base.removeLast()
        }
        guard !base.isEmpty else { return nil }
        return URL(string: base + caminho)
    }

    private func pedir(
        _ caminho: String,
        metodo: String = "GET",
        corpo: [String: Any]? = nil,
        cabecalhos: [String: String] = [:]
    ) async throws -> (Any, Int) {
        guard let url = url(caminho) else { throw ErroDaConversa.enderecoInvalido }
        guard !token.isEmpty else { throw ErroDaConversa.semToken }

        var requisicao = URLRequest(url: url)
        requisicao.httpMethod = metodo
        requisicao.timeoutInterval = 60
        requisicao.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        requisicao.setValue("application/json", forHTTPHeaderField: "Accept")
        for (nome, valor) in cabecalhos {
            requisicao.setValue(valor, forHTTPHeaderField: nome)
        }
        if let corpo {
            requisicao.setValue("application/json", forHTTPHeaderField: "Content-Type")
            requisicao.httpBody = try JSONSerialization.data(withJSONObject: corpo)
        }

        let (dados, resposta) = try await sessao.data(for: requisicao)
        let codigo = (resposta as? HTTPURLResponse)?.statusCode ?? 0
        if codigo < 200 || codigo >= 300 {
            let texto = String(data: dados, encoding: .utf8) ?? ""
            throw ErroDaConversa.http(codigo, String(texto.prefix(300)))
        }
        let objeto = (try? JSONSerialization.jsonObject(with: dados)) ?? [:]
        return (objeto, codigo)
    }

    private static func textoDoPedido(_ pedido: PedidoDeConversa) -> String {
        guard let ultima = pedido.ultimaMensagemDoUsuario else { return "" }
        guard !ultima.anexos.isEmpty else { return ultima.texto }
        var partes: [String] = [ultima.texto]
        for anexo in ultima.anexos {
            let conteudo = anexo.texto.isEmpty ? "(sem texto extraído)" : anexo.texto
            partes.append("[anexo: \(anexo.nome), tipo \(anexo.tipo.rawValue)]\n\(conteudo)")
        }
        return partes.joined(separator: "\n\n")
    }

    static func evento(de quadro: QuadroDeSSE) -> EventoDaPonte {
        var nome = quadro.evento ?? "mensagem"
        var registros: [Registro] = []
        var erro: String?
        var sessao: String?
        var objeto: [String: Any]?
        if let dados = quadro.dados.data(using: .utf8),
           let raiz = try? JSONSerialization.jsonObject(with: dados) {
            objeto = raiz as? [String: Any]
        }
        if let objeto {
            erro = objeto["erro"] as? String
            sessao = (objeto["sessao"] as? String) ?? (objeto["sessionId"] as? String)
            if let lista = objeto["registros"] as? [[String: Any]] {
                registros = lista.compactMap(Registro.iniciar(com:))
            } else if let lista = objeto["snapshot"] as? [[String: Any]] {
                registros = lista.compactMap(Registro.iniciar(com:))
            } else if let registro = Registro.iniciar(com: objeto) {
                registros = [registro]
            }
            if nome == "mensagem", let tipo = objeto["tipo"] as? String {
                nome = tipo
            }
        }
        return EventoDaPonte(nome: nome, json: quadro.dados, registros: registros, erro: erro, sessaoID: sessao)
    }

    static func ehCancelamento(_ erro: Error) -> Bool {
        if erro is CancellationError { return true }
        if let erroDeURL = erro as? URLError, erroDeURL.code == .cancelled { return true }
        return false
    }
}

extension SessaoResumo {
    static func iniciar(com item: [String: Any]) -> SessaoResumo {
        let curto = item["curto"] as? String ?? ""
        let bruto = (item["id"] as? String) ?? (item["sessionId"] as? String)
        let identificador = bruto ?? curto
        let tituloBruto = (item["titulo"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return SessaoResumo(
            id: identificador,
            curto: curto,
            titulo: tituloBruto.isEmpty ? "Conversa sem título" : tituloBruto,
            rodando: item["rodando"] as? Bool ?? false,
            vazia: item["vazia"] as? Bool ?? false,
            cwd: item["cwd"] as? String,
            atualizadoEm: item["atualizadoEm"] as? Double,
            contexto: item["contexto"] as? Int ?? 0,
            tokens: item["tokens"] as? Int,
            turnos: item["turnos"] as? Int ?? 0,
            seq: item["seq"] as? Int ?? 0,
            aberta: item["aberta"] as? Bool ?? false,
            arquivada: item["arquivada"] as? Bool ?? false,
            grupo: item["grupo"] as? String,
            grupoId: item["grupoId"] as? String
        )
    }
}

extension Registro {
    static func iniciar(com objeto: [String: Any]) -> Registro? {
        guard let tipo = objeto["tipo"] as? String else { return nil }
        let em: String?
        if let texto = objeto["em"] as? String {
            em = texto
        } else if let numero = objeto["em"] as? Double {
            em = String(Int64(numero))
        } else {
            em = nil
        }
        let dados = texto(de: objeto["dados"])
        let conteudo = ServicoPonte.textoDoAssistente(em: dados)
        let ehDoUsuario = dados.contains("\"role\":\"user\"") || dados.contains("\"autor\":\"usuario\"")
        return Registro(
            seq: objeto["seq"] as? Int ?? 0,
            tipo: tipo,
            em: em,
            dados: dados,
            textoDoAssistente: ehDoUsuario ? nil : conteudo.texto,
            raciocinioDoAssistente: ehDoUsuario ? nil : conteudo.raciocinio,
            textoDoUsuario: ehDoUsuario ? conteudo.texto : nil
        )
    }

    private static func texto(de valor: Any?) -> String {
        guard let valor else { return "" }
        if let texto = valor as? String { return texto }
        guard JSONSerialization.isValidJSONObject(valor) else { return "" }
        guard let dados = try? JSONSerialization.data(withJSONObject: valor) else { return "" }
        return String(data: dados, encoding: .utf8) ?? ""
    }
}

extension ResultadoDaBusca {
    static func iniciar(com item: [String: Any], indice: Int) -> ResultadoDaBusca? {
        let sessao = (item["sessaoID"] as? String) ?? (item["sessionId"] as? String) ?? (item["id"] as? String)
        let titulo = (item["titulo"] as? String) ?? (item["title"] as? String) ?? ""
        let trecho = (item["trecho"] as? String)
            ?? (item["texto"] as? String)
            ?? (item["snippet"] as? String)
            ?? (item["preview"] as? String)
            ?? ""
        guard !titulo.isEmpty || !trecho.isEmpty || sessao != nil else { return nil }
        return ResultadoDaBusca(
            id: sessao.map { "\($0)-\(indice)" } ?? "resultado-\(indice)",
            titulo: titulo,
            trecho: trecho,
            sessaoID: sessao,
            seq: item["seq"] as? Int
        )
    }
}

extension ServicoPonte {
    static func textoDoAssistente(em json: String) -> (texto: String?, raciocinio: String?) {
        guard let dados = json.data(using: .utf8),
              let raiz = try? JSONSerialization.jsonObject(with: dados)
        else { return (nil, nil) }
        var textos: [String] = []
        var raciocinios: [String] = []
        coletar(raiz, profundidade: 0, textos: &textos, raciocinios: &raciocinios)
        let texto = textos.isEmpty ? nil : textos.joined()
        let raciocinio = raciocinios.isEmpty ? nil : raciocinios.joined()
        return (texto, raciocinio)
    }

    private static func coletar(
        _ valor: Any,
        profundidade: Int,
        textos: inout [String],
        raciocinios: inout [String]
    ) {
        guard profundidade < 8 else { return }
        if let dicionario = valor as? [String: Any] {
            if let partes = dicionario["content"] as? [[String: Any]] {
                for parte in partes {
                    let tipo = (parte["type"] as? String ?? "").lowercased()
                    guard let trecho = (parte["text"] as? String) ?? (parte["reasoning"] as? String),
                          !trecho.isEmpty
                    else { continue }
                    if tipo.contains("reason") {
                        raciocinios.append(trecho)
                    } else {
                        textos.append(trecho)
                    }
                }
            } else if let conteudo = dicionario["content"] as? String, !conteudo.isEmpty {
                textos.append(conteudo)
            }
            for (chave, filho) in dicionario where chave != "content" {
                coletar(filho, profundidade: profundidade + 1, textos: &textos, raciocinios: &raciocinios)
            }
        } else if let lista = valor as? [Any] {
            for filho in lista {
                coletar(filho, profundidade: profundidade + 1, textos: &textos, raciocinios: &raciocinios)
            }
        }
    }
}
