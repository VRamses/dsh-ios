import Combine
import EventKit
import Foundation

enum ErroDeFerramenta: LocalizedError {
    case nomeDesconhecido(String)
    case argumentosInvalidos(String)
    case buscaFalhou(String)

    var errorDescription: String? {
        switch self {
        case .nomeDesconhecido(let nome):
            return "Não conheço a ferramenta \(nome)."
        case .argumentosInvalidos(let nome):
            return "Os argumentos de \(nome) não são um objeto JSON válido."
        case .buscaFalhou(let motivo):
            return motivo
        }
    }
}

/// Executa as duas ferramentas que o modelo pode chamar e devolve sempre JSON.
/// Regra do arquivo: falha de chave, de permissão ou de rede vira `ok: false` com
/// motivo em português, nunca texto vazio que pareça resposta bem sucedida.
@MainActor
final class FerramentasDoModelo: ObservableObject {
    static let nomeDaBusca = "search_web"
    static let nomeDaAgenda = "manage_ios_calendar_reminders"

    private let armazem = EKEventStore()

    // MARK: - Definições

    func definicoes() -> [DefiniçãoDeFerramenta] {
        [
            DefiniçãoDeFerramenta(
                nome: FerramentasDoModelo.nomeDaBusca,
                descricao: "Busca páginas na web agora e devolve trechos com a URL de cada resultado. Use para notícias, preços, documentação atual e qualquer fato que possa ter mudado depois do seu treino.",
                parametrosJSON: FerramentasDoModelo.esquemaDaBusca
            ),
            DefiniçãoDeFerramenta(
                nome: FerramentasDoModelo.nomeDaAgenda,
                descricao: "Cria ou lista eventos na agenda e lembretes no app Lembretes do iPhone. Ao criar, faço um evento de uma hora e um lembrete com alarme no mesmo horário. Datas em ISO 8601, por exemplo 2026-11-25T18:30:00-03:00.",
                parametrosJSON: FerramentasDoModelo.esquemaDaAgenda
            ),
        ]
    }

    // MARK: - Despacho

    func executar(_ chamada: ChamadaDeFerramenta) async throws -> String {
        try await executar(nome: chamada.nome, argumentos: chamada.argumentos)
    }

    func executar(nome: String, argumentos: String) async throws -> String {
        let entrada = try FerramentasDoModelo.argumentosDe(argumentos, ferramenta: nome)
        switch nome {
        case "search_web":
            return await buscarNaWeb(entrada)
        case "manage_ios_calendar_reminders":
            return await gerenciarAgenda(entrada)
        default:
            throw ErroDeFerramenta.nomeDesconhecido(nome)
        }
    }

    // MARK: - Busca na web

    private func buscarNaWeb(_ argumentos: [String: Any]) async -> String {
        guard let consulta = (argumentos["consulta"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !consulta.isEmpty else {
            return FerramentasDoModelo.erro("A busca precisa do campo consulta com o texto a procurar.")
        }

        var lida: String?
        do {
            lida = try CofreDeChaves.ler(ChaveDoCofre.chaveBuscaWeb)
        } catch {
            return FerramentasDoModelo.erro("Não consegui ler a chave de busca do cofre: \(error.localizedDescription)")
        }
        guard let chave = lida?.trimmingCharacters(in: .whitespacesAndNewlines), !chave.isEmpty else {
            return FerramentasDoModelo.erro("Nenhuma chave de busca configurada. Peça ao usuário para colar a chave da Tavily ou da Brave em Ajustes.")
        }

        do {
            let achados = try await consultarProvedor(consulta: consulta, chave: chave)
            return FerramentasDoModelo.json([
                "ok": true,
                "ferramenta": "search_web",
                "consulta": consulta,
                "resumo": achados.resumo,
                "resultados": achados.itens,
            ])
        } catch {
            return FerramentasDoModelo.erro(error.localizedDescription)
        }
    }

    private struct AchadosDaBusca {
        var resumo: String
        var itens: [[String: Any]]
    }

    private func consultarProvedor(consulta: String, chave: String) async throws -> AchadosDaBusca {
        // O cofre guarda uma chave só para busca, então o provedor sai do formato dela:
        // a Tavily emite chaves com o prefixo tvly- e a Brave não usa prefixo.
        if chave.hasPrefix("tvly-") {
            return try await buscarComTavily(consulta: consulta, chave: chave)
        }
        return try await buscarComBrave(consulta: consulta, chave: chave)
    }

    private func buscarComTavily(consulta: String, chave: String) async throws -> AchadosDaBusca {
        guard let url = URL(string: "https://api.tavily.com/search") else {
            throw ErroDeFerramenta.buscaFalhou("O endereço da Tavily é inválido.")
        }
        var pedido = URLRequest(url: url)
        pedido.httpMethod = "POST"
        pedido.timeoutInterval = 20
        pedido.setValue("application/json", forHTTPHeaderField: "Content-Type")
        pedido.setValue("Bearer \(chave)", forHTTPHeaderField: "Authorization")
        let corpo: [String: Any] = [
            "api_key": chave,
            "query": consulta,
            "search_depth": "basic",
            "max_results": 5,
            "include_answer": true,
        ]
        pedido.httpBody = try JSONSerialization.data(withJSONObject: corpo)

        let (dados, resposta) = try await URLSession.shared.data(for: pedido)
        try FerramentasDoModelo.validar(resposta: resposta, dados: dados)
        guard let objeto = try JSONSerialization.jsonObject(with: dados) as? [String: Any] else {
            throw ErroDeFerramenta.buscaFalhou("A Tavily respondeu algo que não é JSON de objeto.")
        }

        let brutos = objeto["results"] as? [[String: Any]] ?? []
        var itens: [[String: Any]] = []
        for bruto in brutos {
            guard let link = (bruto["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !link.isEmpty else { continue }
            itens.append([
                "titulo": (bruto["title"] as? String) ?? "",
                "url": link,
                "trecho": FerramentasDoModelo.encurtar((bruto["content"] as? String) ?? "", limite: 320),
            ])
        }

        let respostaCurta = FerramentasDoModelo.encurtar((objeto["answer"] as? String) ?? "", limite: 500)
        let resumo: String
        if !respostaCurta.isEmpty {
            resumo = respostaCurta
        } else if itens.isEmpty {
            resumo = "A busca não trouxe resultados para \(consulta)."
        } else {
            resumo = "Encontrei \(itens.count) resultados para \(consulta)."
        }
        return AchadosDaBusca(resumo: resumo, itens: itens)
    }

    private func buscarComBrave(consulta: String, chave: String) async throws -> AchadosDaBusca {
        var componentes = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")
        componentes?.queryItems = [
            URLQueryItem(name: "q", value: consulta),
            URLQueryItem(name: "count", value: "5"),
        ]
        guard let url = componentes?.url else {
            throw ErroDeFerramenta.buscaFalhou("O endereço da Brave é inválido.")
        }
        var pedido = URLRequest(url: url)
        pedido.httpMethod = "GET"
        pedido.timeoutInterval = 20
        pedido.setValue("application/json", forHTTPHeaderField: "Accept")
        pedido.setValue(chave, forHTTPHeaderField: "X-Subscription-Token")

        let (dados, resposta) = try await URLSession.shared.data(for: pedido)
        try FerramentasDoModelo.validar(resposta: resposta, dados: dados)
        guard let objeto = try JSONSerialization.jsonObject(with: dados) as? [String: Any],
              let web = objeto["web"] as? [String: Any] else {
            throw ErroDeFerramenta.buscaFalhou("A Brave respondeu sem o campo web.")
        }

        let brutos = web["results"] as? [[String: Any]] ?? []
        var itens: [[String: Any]] = []
        for bruto in brutos {
            guard let link = (bruto["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !link.isEmpty else { continue }
            itens.append([
                "titulo": (bruto["title"] as? String) ?? "",
                "url": link,
                "trecho": FerramentasDoModelo.encurtar((bruto["description"] as? String) ?? "", limite: 320),
            ])
        }

        let resumo = itens.isEmpty
            ? "A busca não trouxe resultados para \(consulta)."
            : "Encontrei \(itens.count) resultados para \(consulta)."
        return AchadosDaBusca(resumo: resumo, itens: itens)
    }

    private static func validar(resposta: URLResponse, dados: Data) throws {
        guard let http = resposta as? HTTPURLResponse else {
            throw ErroDeFerramenta.buscaFalhou("A busca não devolveu uma resposta HTTP.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let corpo = encurtar(String(data: dados, encoding: .utf8) ?? "", limite: 200)
            throw ErroDeFerramenta.buscaFalhou("A busca respondeu HTTP \(http.statusCode): \(corpo)")
        }
    }

    // MARK: - Agenda e lembretes

    private func gerenciarAgenda(_ argumentos: [String: Any]) async -> String {
        let acao = ((argumentos["acao"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard acao == "criar" || acao == "listar" else {
            return FerramentasDoModelo.erro("O campo acao precisa ser criar ou listar.")
        }

        let agenda = await pedirAcessoAosEventos()
        let lembretes = await pedirAcessoAosLembretes()

        if acao == "criar" {
            return criarNaAgendaELembretes(argumentos, agenda: agenda, lembretes: lembretes)
        }
        return await listarAgendaELembretes(agenda: agenda, lembretes: lembretes)
    }

    private func pedirAcessoAosEventos() async -> Bool {
        return await withCheckedContinuation { continuacao in
            armazem.requestFullAccessToEvents { concedido, _ in
                continuacao.resume(returning: concedido)
            }
        }
    }

    private func pedirAcessoAosLembretes() async -> Bool {
        return await withCheckedContinuation { continuacao in
            armazem.requestFullAccessToReminders { concedido, _ in
                continuacao.resume(returning: concedido)
            }
        }
    }

    private func criarNaAgendaELembretes(
        _ argumentos: [String: Any],
        agenda: Bool,
        lembretes: Bool
    ) -> String {
        guard let titulo = (argumentos["titulo"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !titulo.isEmpty else {
            return FerramentasDoModelo.erro("Para criar, preciso do campo titulo.")
        }
        guard let quando = (argumentos["quando"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !quando.isEmpty else {
            return FerramentasDoModelo.erro("Para criar, preciso do campo quando em ISO 8601, por exemplo 2026-11-25T18:30:00-03:00.")
        }
        guard let data = FerramentasDoModelo.dataDe(quando) else {
            return FerramentasDoModelo.erro("Não entendi a data \(quando). Use ISO 8601, por exemplo 2026-11-25T18:30:00-03:00.")
        }
        guard agenda || lembretes else {
            return FerramentasDoModelo.erro("Sem acesso à agenda e aos lembretes. Autorize em Ajustes, DSH, Agenda e Lembretes.")
        }

        let fim = data.addingTimeInterval(3600)
        var criado: [[String: Any]] = []
        var falhas: [String] = []
        var partesDoResumo: [String] = []

        if agenda {
            if let calendario = armazem.defaultCalendarForNewEvents
                ?? armazem.calendars(for: .event).first {
                let evento = EKEvent(eventStore: armazem)
                evento.title = titulo
                evento.startDate = data
                evento.endDate = fim
                evento.calendar = calendario
                do {
                    try armazem.save(evento, span: .thisEvent, commit: true)
                    criado.append([
                        "tipo": "evento",
                        "titulo": titulo,
                        "inicio": FerramentasDoModelo.iso(data),
                        "fim": FerramentasDoModelo.iso(fim),
                        "calendario": calendario.title,
                    ])
                    partesDoResumo.append(
                        "Criei o evento \(titulo) em \(FerramentasDoModelo.dataLegivel(data)) no calendário \(calendario.title)."
                    )
                } catch {
                    falhas.append("evento: \(error.localizedDescription)")
                }
            } else {
                falhas.append("evento: não há calendário disponível para gravar.")
            }
        } else {
            falhas.append("evento: sem permissão de agenda.")
        }

        if lembretes {
            if let lista = armazem.defaultCalendarForNewReminders()
                ?? armazem.calendars(for: .reminder).first {
                let lembrete = EKReminder(eventStore: armazem)
                lembrete.title = titulo
                lembrete.calendar = lista
                lembrete.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: data
                )
                lembrete.addAlarm(EKAlarm(absoluteDate: data))
                do {
                    try armazem.save(lembrete, commit: true)
                    criado.append([
                        "tipo": "lembrete",
                        "titulo": titulo,
                        "quando": FerramentasDoModelo.iso(data),
                        "lista": lista.title,
                    ])
                    partesDoResumo.append(
                        "Criei o lembrete \(titulo) para \(FerramentasDoModelo.dataLegivel(data)) na lista \(lista.title)."
                    )
                } catch {
                    falhas.append("lembrete: \(error.localizedDescription)")
                }
            } else {
                falhas.append("lembrete: não há lista disponível para gravar.")
            }
        } else {
            falhas.append("lembrete: sem permissão de lembretes.")
        }

        var resumo = partesDoResumo.joined(separator: " ")
        if !falhas.isEmpty {
            if !resumo.isEmpty {
                resumo += " "
            }
            resumo += "Não deu para: \(falhas.joined(separator: "; "))."
        }

        var resultado: [String: Any] = [
            "ok": !criado.isEmpty,
            "ferramenta": "manage_ios_calendar_reminders",
            "acao": "criar",
            "titulo": titulo,
            "quando": FerramentasDoModelo.iso(data),
            "criado": criado,
            "falhas": falhas,
            "resumo": resumo,
        ]
        if criado.isEmpty {
            resultado["erro"] = resumo.isEmpty ? "Nada foi criado." : resumo
        }
        return FerramentasDoModelo.json(resultado)
    }

    private func listarAgendaELembretes(agenda: Bool, lembretes: Bool) async -> String {
        guard agenda || lembretes else {
            return FerramentasDoModelo.erro("Sem acesso à agenda e aos lembretes. Autorize em Ajustes, DSH, Agenda e Lembretes.")
        }

        let agora = Date()
        let limite = Calendar.current.date(byAdding: .day, value: 7, to: agora)
            ?? agora.addingTimeInterval(7 * 86_400)
        var eventos: [[String: Any]] = []
        var pendentes: [[String: Any]] = []
        var falhas: [String] = []

        if agenda {
            let predicado = armazem.predicateForEvents(withStart: agora, end: limite, calendars: nil)
            let encontrados = armazem.events(matching: predicado)
                .sorted { $0.startDate < $1.startDate }
                .prefix(10)
            for evento in encontrados {
                eventos.append([
                    "titulo": evento.title ?? "",
                    "inicio": FerramentasDoModelo.iso(evento.startDate),
                    "calendario": evento.calendar?.title ?? "",
                ])
            }
        } else {
            falhas.append("agenda: sem permissão.")
        }

        if lembretes {
            let predicado = armazem.predicateForReminders(in: nil)
            let encontrados: [EKReminder] = await withCheckedContinuation { continuacao in
                armazem.fetchReminders(matching: predicado) { lista in
                    continuacao.resume(returning: lista ?? [])
                }
            }
            let ordenados = encontrados
                .filter { !$0.isCompleted }
                .sorted {
                    ($0.dueDateComponents?.date ?? .distantFuture)
                        < ($1.dueDateComponents?.date ?? .distantFuture)
                }
                .prefix(10)
            for lembrete in ordenados {
                var item: [String: Any] = [
                    "titulo": lembrete.title ?? "",
                    "lista": lembrete.calendar?.title ?? "",
                ]
                if let data = lembrete.dueDateComponents?.date {
                    item["quando"] = FerramentasDoModelo.iso(data)
                }
                pendentes.append(item)
            }
        } else {
            falhas.append("lembretes: sem permissão.")
        }

        var partesDoResumo: [String] = []
        partesDoResumo.append(
            eventos.isEmpty
                ? "Nenhum evento nos próximos 7 dias."
                : "\(eventos.count) evento(s) nos próximos 7 dias."
        )
        partesDoResumo.append(
            pendentes.isEmpty
                ? "Nenhum lembrete pendente."
                : "\(pendentes.count) lembrete(s) pendente(s)."
        )
        if !falhas.isEmpty {
            partesDoResumo.append("Não consegui ler: \(falhas.joined(separator: "; ")).")
        }

        return FerramentasDoModelo.json([
            "ok": true,
            "ferramenta": "manage_ios_calendar_reminders",
            "acao": "listar",
            "eventos": eventos,
            "lembretes": pendentes,
            "falhas": falhas,
            "resumo": partesDoResumo.joined(separator: " "),
        ])
    }

    // MARK: - Apoio

    private static let esquemaDaBusca = """
    {"type":"object","properties":{"consulta":{"type":"string","description":"Texto da busca em português, com o assunto e o recorte de tempo quando importar."}},"required":["consulta"],"additionalProperties":false}
    """

    private static let esquemaDaAgenda = """
    {"type":"object","properties":{"acao":{"type":"string","enum":["criar","listar"],"description":"criar grava um evento e um lembrete; listar devolve os eventos dos próximos 7 dias e os lembretes pendentes."},"titulo":{"type":"string","description":"Título do evento e do lembrete. Obrigatório quando acao for criar."},"quando":{"type":"string","description":"Data e hora em ISO 8601, por exemplo 2026-11-25T18:30:00-03:00. Obrigatório quando acao for criar."}},"required":["acao"],"additionalProperties":false}
    """

    private static func argumentosDe(_ texto: String, ferramenta: String) throws -> [String: Any] {
        let limpo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpo.isEmpty else { return [:] }
        guard let dados = limpo.data(using: .utf8),
              let objeto = try? JSONSerialization.jsonObject(with: dados),
              let dicionario = objeto as? [String: Any] else {
            throw ErroDeFerramenta.argumentosInvalidos(ferramenta)
        }
        return dicionario
    }

    private static func json(_ objeto: [String: Any]) -> String {
        guard let dados = try? JSONSerialization.data(withJSONObject: objeto),
              let texto = String(data: dados, encoding: .utf8) else {
            return "{\"ok\":false,\"erro\":\"Não consegui montar o resultado em JSON.\"}"
        }
        return texto
    }

    private static func erro(_ mensagem: String) -> String {
        json(["ok": false, "erro": mensagem])
    }

    private static func encurtar(_ texto: String, limite: Int) -> String {
        let limpo = texto
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard limpo.count > limite else { return limpo }
        return String(limpo.prefix(limite)) + "..."
    }

    private static func iso(_ data: Date) -> String {
        let formato = ISO8601DateFormatter()
        formato.formatOptions = [.withInternetDateTime]
        return formato.string(from: data)
    }

    private static func dataLegivel(_ data: Date) -> String {
        let formato = DateFormatter()
        formato.locale = Locale(identifier: "pt_BR")
        formato.timeZone = .current
        formato.dateFormat = "dd/MM/yyyy 'às' HH:mm"
        return formato.string(from: data)
    }

    private static func dataDe(_ texto: String) -> Date? {
        let limpo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpo.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let data = iso.date(from: limpo) { return data }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let data = iso.date(from: limpo) { return data }

        // O modelo às vezes manda ISO sem fuso, ou só a data. Nesses casos a hora
        // local do aparelho é a leitura menos surpreendente para o usuário.
        for padrao in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let formato = DateFormatter()
            formato.locale = Locale(identifier: "en_US_POSIX")
            formato.timeZone = .current
            formato.dateFormat = padrao
            if let data = formato.date(from: limpo) { return data }
        }
        return nil
    }
}
