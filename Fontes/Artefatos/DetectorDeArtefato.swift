import Foundation

/// Encontra, na resposta do modelo, os blocos de código que formam uma página inteira.
/// A cerca de código é o corte confiável entre "documento terminado" e "trecho solto":
/// texto fora de cerca não é artefato, porque não há como saber onde o autor parou.
enum DetectorDeArtefato {

    /// Bloco acima disso é despejo de dados, não página: carregar no WKWebView custaria
    /// memória e a lista do chat ficaria pesada sem ganho para o usuário.
    static let limiteDeCaracteresPorBloco = 400_000

    static func detectar(em texto: String) -> [Artefato] {
        // CRLF de texto colado quebra o reconhecimento da cerca de fechamento.
        let normalizado = texto
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var artefatos: [Artefato] = []
        var ocorrenciasDosIDs: [String: Int] = [:]

        for bloco in blocosDeCodigo(em: normalizado) {
            guard bloco.texto.count <= limiteDeCaracteresPorBloco else { continue }
            guard let tipo = classificar(linguagem: bloco.linguagem, codigo: bloco.texto) else { continue }

            let artefato = Artefato(
                id: assinatura(de: bloco.texto),
                tipo: tipo,
                titulo: titulo(para: tipo, codigo: bloco.texto),
                linguagem: linguagemParaExibir(tipo: tipo, informada: bloco.linguagem),
                codigo: bloco.texto
            )

            // Dois blocos idênticos na mesma resposta geram o mesmo id; o sufixo evita
            // identificador repetido na lista do SwiftUI e continua determinístico.
            let ocorrencias = ocorrenciasDosIDs[artefato.id, default: 0] + 1
            ocorrenciasDosIDs[artefato.id] = ocorrencias
            if ocorrencias == 1 {
                artefatos.append(artefato)
            } else {
                var copia = artefato
                copia.id = "\(artefato.id)-\(ocorrencias)"
                artefatos.append(copia)
            }
        }

        return artefatos
    }

    // MARK: - Cercas de código

    private static func blocosDeCodigo(em texto: String) -> [(linguagem: String, texto: String)] {
        var blocos: [(linguagem: String, texto: String)] = []
        var dentro = false
        var caractereDaCerca: Character = "`"
        var tamanhoDaCerca = 0
        var informacao = ""
        var corpo: [String] = []

        for linha in texto.components(separatedBy: "\n") {
            if dentro {
                if ehFechamento(linha, caractere: caractereDaCerca, minimo: tamanhoDaCerca) {
                    blocos.append((linguagem: informacao, texto: corpo.joined(separator: "\n")))
                    dentro = false
                    corpo.removeAll()
                    informacao = ""
                } else {
                    corpo.append(linha)
                }
                continue
            }
            if let abertura = aberturaDeCerca(linha) {
                dentro = true
                caractereDaCerca = abertura.caractere
                tamanhoDaCerca = abertura.tamanho
                informacao = abertura.informacao
                corpo.removeAll()
            }
        }

        // Cerca que abre e não fecha é resposta ainda chegando: fica de fora, porque
        // meio documento na tela é pior que documento nenhum.
        return blocos
    }

    private static func aberturaDeCerca(_ linha: String) -> (caractere: Character, tamanho: Int, informacao: String)? {
        let semRecuo = linha.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let primeiro = semRecuo.first, primeiro == "`" || primeiro == "~" else { return nil }

        var tamanho = 0
        for caractere in semRecuo {
            guard caractere == primeiro else { break }
            tamanho += 1
        }
        guard tamanho >= 3 else { return nil }

        let informacao = String(semRecuo.dropFirst(tamanho)).trimmingCharacters(in: .whitespaces)
        return (primeiro, tamanho, informacao)
    }

    private static func ehFechamento(_ linha: String, caractere: Character, minimo: Int) -> Bool {
        let semRecuo = linha.trimmingCharacters(in: .whitespacesAndNewlines)
        guard semRecuo.count >= minimo else { return false }
        return semRecuo.allSatisfy { $0 == caractere }
    }

    // MARK: - Classificação

    private static func classificar(linguagem: String, codigo: String) -> Artefato.Tipo? {
        let minusculo = codigo.lowercased()
        let lingua = normalizar(linguagem)

        // HTML completo primeiro: uma página que desenha SVG também contém "</svg>".
        if ehHtmlCompleto(minusculo) { return .html }
        if temSvgCompleto(minusculo) { return .svg }

        // Gráfico é widget de tela única e roda mesmo fora de um documento completo.
        if ehGrafico(lingua: lingua, minusculo: minusculo) { return .grafico }

        // Cerca marcada como html sem estrutura e sem desenho é pedaço de página: fica
        // de fora para não abrir uma tela branca no meio da resposta.
        return nil
    }

    private static func ehHtmlCompleto(_ minusculo: String) -> Bool {
        let temEstrutura = minusculo.contains("<html")
            || minusculo.contains("<!doctype")
            || minusculo.contains("<body")
        guard temEstrutura else { return false }

        // Fechamento junto: sem ele o bloco é documento cortado ao meio, e abrir isso
        // na tela só produz a página branca que este app existe para evitar.
        return minusculo.contains("</html") || minusculo.contains("</body")
    }

    private static func temSvgCompleto(_ minusculo: String) -> Bool {
        minusculo.contains("<svg") && minusculo.contains("</svg>")
    }

    private static func ehGrafico(lingua: String, minusculo: String) -> Bool {
        let linguasDeGrafico: Set<String> = ["javascript", "js", "chart", "chartjs", "echarts", "d3", "plotly", "vega", "canvas"]
        let temCanvas = minusculo.contains("<canvas")
        let temBiblioteca = minusculo.contains("getcontext(")
            || minusculo.contains("new chart(")
            || minusculo.contains("echarts.init")
            || minusculo.contains("d3.select")
            || minusculo.contains("plotly.newplot")
            || minusculo.contains("new highcharts.chart")

        if temCanvas && (temBiblioteca || minusculo.contains("<script")) { return true }
        return linguasDeGrafico.contains(lingua) && (temCanvas || temBiblioteca)
    }

    private static func normalizar(_ informacao: String) -> String {
        var bruta = informacao.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if bruta.hasPrefix("{") {
            bruta = bruta.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
        }
        let primeira = bruta.split(whereSeparator: { $0.isWhitespace }).map { String($0) }.first ?? ""
        let semPontuacao = primeira.trimmingCharacters(in: CharacterSet(charactersIn: ".:;,"))

        switch semPontuacao {
        case "htm", "xhtml":
            return "html"
        case "js", "mjs", "cjs":
            return "javascript"
        default:
            return semPontuacao
        }
    }

    private static func linguagemParaExibir(tipo: Artefato.Tipo, informada: String) -> String {
        let lingua = normalizar(informada)
        switch tipo {
        case .html:
            return "html"
        case .svg:
            return "svg"
        case .grafico:
            return lingua.isEmpty || lingua == "html" ? "javascript" : lingua
        }
    }

    // MARK: - Título e identidade

    private static func titulo(para tipo: Artefato.Tipo, codigo: String) -> String {
        if let daTag = tituloDaTag(codigo), !daTag.isEmpty {
            return encurtar(daTag)
        }
        if let doComentario = comentarioInicial(codigo), !doComentario.isEmpty {
            return encurtar(doComentario)
        }
        if tipo == .grafico, let daLinha = primeiraLinhaDeTexto(codigo) {
            return encurtar(daLinha)
        }
        switch tipo {
        case .html:
            return "Página HTML"
        case .svg:
            return "Desenho SVG"
        case .grafico:
            return "Gráfico interativo"
        }
    }

    private static func tituloDaTag(_ codigo: String) -> String? {
        guard let abertura = codigo.range(of: "<title", options: .caseInsensitive) else { return nil }
        guard let fimDaAbertura = codigo[abertura.upperBound...].firstIndex(of: ">") else { return nil }
        let inicio = codigo.index(after: fimDaAbertura)
        guard let fechamento = codigo.range(of: "</title", options: .caseInsensitive, range: inicio..<codigo.endIndex) else { return nil }
        let bruto = String(codigo[inicio..<fechamento.lowerBound])
        return normalizarTexto(removendoTags(bruto))
    }

    private static func comentarioInicial(_ codigo: String) -> String? {
        let semEspaco = codigo.trimmingCharacters(in: .whitespacesAndNewlines)

        if semEspaco.hasPrefix("<!--"), let fim = semEspaco.range(of: "-->") {
            let corpo = semEspaco[semEspaco.startIndex..<fim.lowerBound].dropFirst(4)
            return normalizarTexto(String(corpo))
        }

        for linha in semEspaco.split(separator: "\n") {
            let texto = String(linha).trimmingCharacters(in: .whitespaces)
            if texto.hasPrefix("//") {
                return normalizarTexto(String(texto.dropFirst(2)))
            }
            if texto.hasPrefix("/*") {
                if let fim = texto.range(of: "*/") {
                    let corpo = texto[texto.index(texto.startIndex, offsetBy: 2)..<fim.lowerBound]
                    return normalizarTexto(String(corpo))
                }
            }
            if !texto.isEmpty { return nil }
        }
        return nil
    }

    private static func primeiraLinhaDeTexto(_ codigo: String) -> String? {
        for linha in codigo.split(separator: "\n") {
            let texto = String(linha).trimmingCharacters(in: .whitespaces)
            guard !texto.isEmpty else { continue }
            // Linha que começa com marcação ou com chave é estrutura, não descrição.
            guard !texto.hasPrefix("<"), !texto.hasPrefix("{"), !texto.hasPrefix("}") else { return nil }
            return normalizarTexto(texto)
        }
        return nil
    }

    private static func normalizarTexto(_ bruto: String) -> String {
        var texto = bruto
        let entidades = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&nbsp;": " "]
        for (chave, valor) in entidades {
            texto = texto.replacingOccurrences(of: chave, with: valor)
        }
        return texto.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func removendoTags(_ bruto: String) -> String {
        var saida = ""
        var dentroDeTag = false
        for caractere in bruto {
            if caractere == "<" {
                dentroDeTag = true
                continue
            }
            if caractere == ">" {
                dentroDeTag = false
                continue
            }
            if !dentroDeTag { saida.append(caractere) }
        }
        return saida
    }

    private static func encurtar(_ texto: String) -> String {
        let limite = 48
        guard texto.count > limite else { return texto }
        return String(texto.prefix(limite - 1)) + "..."
    }

    private static func assinatura(de texto: String) -> String {
        // FNV-1a de 64 bits: hash estável entre execuções. O Hasher do Swift muda a
        // semente a cada processo, então o id do artefato não sobreviveria ao app.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in texto.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hexadecimal = String(hash, radix: 16)
        let preenchido = String(repeating: "0", count: max(0, 16 - hexadecimal.count)) + hexadecimal
        return "art-" + preenchido
    }
}
