import SwiftUI

/// Markdown da resposta, renderizado sem dependência de terceiro.
///
/// O que a API manda é markdown comum: parágrafo, título, lista, citação, tabela,
/// bloco de código e link. `AttributedString` resolve o inline (negrito, itálico,
/// link, código) e o resto é lido linha a linha aqui, porque tabela e cerca de
/// código não têm vista pronta no SwiftUI. O resultado é uma sequência de blocos
/// com o ritmo do `Espaco`, não um `Text` gigante.
struct TextoRico: View {
    var texto: String

    init(_ texto: String) {
        self.texto = texto
    }

    var body: some View {
        let blocos = TextoRico.blocos(de: texto)
        VStack(alignment: .leading, spacing: Espaco.m) {
            ForEach(blocos.indices, id: \.self) { indice in
                vista(de: blocos[indice])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(Cores.acento)
        .textSelection(.enabled)
    }

    // MARK: - Blocos na tela

    @ViewBuilder
    private func vista(de bloco: Bloco) -> some View {
        switch bloco {
        case .paragrafo(let conteudo):
            base(conteudo)
                .font(Tipografia.corpo())
                .foregroundStyle(Cores.texto)
                .lineSpacing(4)

        case .titulo(let conteudo, let nivel):
            base(conteudo)
                .font(nivel <= 2 ? Tipografia.titulo(20) : Tipografia.corpo())
                .fontWeight(.semibold)
                .foregroundStyle(Cores.texto)
                .padding(.top, Espaco.xs)

        case .item(let conteudo):
            HStack(alignment: .firstTextBaseline, spacing: Espaco.s) {
                Text("•")
                    .font(Tipografia.corpo())
                    .foregroundStyle(Cores.textoFraco)
                base(conteudo)
                    .font(Tipografia.corpo())
                    .foregroundStyle(Cores.texto)
                    .lineSpacing(4)
            }
            .padding(.leading, Espaco.s)

        case .numerado(let conteudo, let numero):
            HStack(alignment: .firstTextBaseline, spacing: Espaco.s) {
                Text("\(numero).")
                    .font(Tipografia.codigo(13))
                    .foregroundStyle(Cores.textoFraco)
                base(conteudo)
                    .font(Tipografia.corpo())
                    .foregroundStyle(Cores.texto)
                    .lineSpacing(4)
            }
            .padding(.leading, Espaco.s)

        case .citacao(let conteudo):
            HStack(spacing: Espaco.m) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Cores.borda)
                    .frame(width: 2)
                base(conteudo)
                    .font(Tipografia.corpo())
                    .foregroundStyle(Cores.textoFraco)
                    .lineSpacing(4)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .codigo(let linguagem, let corpo):
            BlocoDeCodigo(linguagem: linguagem, codigo: corpo)

        case .tabela(let cabecalho, let linhas):
            tabela(cabecalho: cabecalho, linhas: linhas)

        case .regra:
            Rectangle()
                .fill(Cores.borda.opacity(0.55))
                .frame(height: 1)
                .padding(.vertical, Espaco.xs)
        }
    }

    private func base(_ conteudo: String) -> Text {
        Text(TextoRico.atribuido(conteudo))
    }

    @ViewBuilder
    private func tabela(cabecalho: [String], linhas: [[String]]) -> some View {
        if cabecalho.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: Espaco.m, verticalSpacing: Espaco.s) {
                    GridRow {
                        ForEach(cabecalho.indices, id: \.self) { coluna in
                            base(cabecalho[coluna])
                                .font(Tipografia.corpo())
                                .fontWeight(.semibold)
                                .foregroundStyle(Cores.texto)
                                .frame(minWidth: 72, alignment: .leading)
                        }
                    }
                    Divider()
                        .gridCellColumns(cabecalho.count)
                    ForEach(linhas.indices, id: \.self) { linha in
                        GridRow {
                            ForEach(linhas[linha].indices, id: \.self) { coluna in
                                base(linhas[linha][coluna])
                                    .font(Tipografia.corpo())
                                    .foregroundStyle(Cores.texto)
                                    .frame(minWidth: 72, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(Espaco.m)
            }
            .background(Cores.superficieElevada)
            .clipShape(RoundedRectangle(cornerRadius: Raio.m, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Raio.m, style: .continuous)
                    .strokeBorder(Cores.borda.opacity(0.55), lineWidth: 1)
            )
        }
    }

    // MARK: - Inline

    static func atribuido(_ texto: String) -> AttributedString {
        let opcoes = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        guard var resultado = try? AttributedString(markdown: texto, options: opcoes) else {
            return AttributedString(texto)
        }
        var trechosDeCodigo: [Range<AttributedString.Index>] = []
        for trecho in resultado.runs where trecho.inlinePresentationIntent?.contains(.code) == true {
            trechosDeCodigo.append(trecho.range)
        }
        for faixa in trechosDeCodigo {
            resultado[faixa].font = Tipografia.codigo(15)
        }
        return resultado
    }
}

// MARK: - Leitura dos blocos

private enum Bloco {
    case paragrafo(String)
    case titulo(String, nivel: Int)
    case item(String)
    case numerado(String, numero: String)
    case citacao(String)
    case tabela(cabecalho: [String], linhas: [[String]])
    case codigo(linguagem: String, corpo: String)
    case regra
}

private extension TextoRico {
    enum Marcador {
        case ponto
        case numero(String)
    }

    static func blocos(de texto: String) -> [Bloco] {
        let linhas = texto
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var resultado: [Bloco] = []
        var paragrafo: [String] = []
        var indice = 0

        func despejarParagrafo() {
            let junto = paragrafo
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !junto.isEmpty { resultado.append(.paragrafo(junto)) }
            paragrafo.removeAll()
        }

        while indice < linhas.count {
            let limpa = linhas[indice].trimmingCharacters(in: .whitespaces)
            if limpa.isEmpty {
                despejarParagrafo()
                indice += 1
                continue
            }

            if limpa.hasPrefix("```") {
                despejarParagrafo()
                let linguagem = String(limpa.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var corpo: [String] = []
                indice += 1
                while indice < linhas.count {
                    if linhas[indice].trimmingCharacters(in: .whitespaces).hasPrefix("```") { break }
                    corpo.append(linhas[indice])
                    indice += 1
                }
                resultado.append(.codigo(linguagem: linguagem, corpo: corpo.joined(separator: "\n")))
                indice += 1
                continue
            }

            if let (nivel, conteudo) = titulo(de: limpa) {
                despejarParagrafo()
                resultado.append(.titulo(conteudo, nivel: nivel))
                indice += 1
                continue
            }

            if regra(limpa) {
                despejarParagrafo()
                resultado.append(.regra)
                indice += 1
                continue
            }

            if limpa.hasPrefix("|"), let (tabela, consumidas) = tabela(de: linhas, aPartir: indice) {
                despejarParagrafo()
                resultado.append(tabela)
                indice += consumidas
                continue
            }

            if limpa.hasPrefix(">") {
                despejarParagrafo()
                var citacao: [String] = []
                while indice < linhas.count {
                    let atual = linhas[indice].trimmingCharacters(in: .whitespaces)
                    guard atual.hasPrefix(">") else { break }
                    citacao.append(String(atual.dropFirst()).trimmingCharacters(in: .whitespaces))
                    indice += 1
                }
                resultado.append(.citacao(citacao.joined(separator: "\n")))
                continue
            }

            if let (marcador, conteudo) = itemDeLista(limpa) {
                despejarParagrafo()
                switch marcador {
                case .ponto: resultado.append(.item(conteudo))
                case .numero(let numero): resultado.append(.numerado(conteudo, numero: numero))
                }
                indice += 1
                continue
            }

            paragrafo.append(limpa)
            indice += 1
        }

        despejarParagrafo()
        return resultado
    }

    static func titulo(de linha: String) -> (Int, String)? {
        var nivel = 0
        var resto = Substring(linha)
        while nivel < 6, resto.hasPrefix("#") {
            nivel += 1
            resto = resto.dropFirst()
        }
        guard nivel > 0, resto.hasPrefix(" ") else { return nil }
        let conteudo = String(resto).trimmingCharacters(in: .whitespaces)
        return conteudo.isEmpty ? nil : (nivel, conteudo)
    }

    static func regra(_ linha: String) -> Bool {
        linha == "---" || linha == "***" || linha == "___"
    }

    static func itemDeLista(_ linha: String) -> (Marcador, String)? {
        for prefixo in ["- ", "* ", "+ "] where linha.hasPrefix(prefixo) {
            let conteudo = String(linha.dropFirst(prefixo.count)).trimmingCharacters(in: .whitespaces)
            return conteudo.isEmpty ? nil : (.ponto, conteudo)
        }
        var digitos = ""
        var resto = Substring(linha)
        while let primeiro = resto.first, primeiro.isNumber, digitos.count < 3 {
            digitos.append(primeiro)
            resto = resto.dropFirst()
        }
        guard !digitos.isEmpty else { return nil }
        if resto.hasPrefix(". ") || resto.hasPrefix(") ") {
            let conteudo = String(resto.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            return conteudo.isEmpty ? nil : (.numero(digitos), conteudo)
        }
        return nil
    }

    static func tabela(de linhas: [String], aPartir inicio: Int) -> (Bloco, Int)? {
        guard inicio + 1 < linhas.count else { return nil }
        let cabecalho = celulas(de: linhas[inicio])
        let separador = celulas(de: linhas[inicio + 1])
        guard !cabecalho.isEmpty,
              separador.count == cabecalho.count,
              separador.allSatisfy({ $0.contains("-") })
        else { return nil }

        var corpo: [[String]] = []
        var indice = inicio + 2
        while indice < linhas.count {
            let limpa = linhas[indice].trimmingCharacters(in: .whitespaces)
            guard limpa.hasPrefix("|") else { break }
            var valores = celulas(de: limpa)
            if valores.count < cabecalho.count {
                valores.append(contentsOf: Array(repeating: "", count: cabecalho.count - valores.count))
            }
            corpo.append(Array(valores.prefix(cabecalho.count)))
            indice += 1
        }
        return (.tabela(cabecalho: cabecalho, linhas: corpo), indice - inicio)
    }

    static func celulas(de linha: String) -> [String] {
        var limpa = linha.trimmingCharacters(in: .whitespaces)
        if limpa.hasPrefix("|") { limpa.removeFirst() }
        if limpa.hasSuffix("|") { limpa.removeLast() }
        return limpa
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty || limpa.isEmpty }
    }
}
