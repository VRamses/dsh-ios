import Foundation
import SwiftUI

/// Folha modal do artefato: visualização em página isolada, código cru, recarga e
/// exportação. O WKWebView é criado por `VisualizadorDeArtefato` e não guarda estado
/// entre aberturas. O documento é montado uma vez no init para não reconstruir a
/// página a cada mensagem de console que chega.
struct TelaDeArtefato: View {
    var artefato: Artefato

    @Environment(\.dismiss) private var fechar
    @State private var aba = 0
    @State private var recarga = 0
    @State private var registros: [String] = []
    @State private var urlParaExportar: URL?

    private let documento: String

    init(artefato: Artefato) {
        self.artefato = artefato
        self.documento = TelaDeArtefato.documentoParaVisualizar(artefato)
    }

    var body: some View {
        VStack(spacing: 0) {
            cabecalho

            Picker("Modo de exibição", selection: $aba) {
                Text("Visualização").tag(0)
                Text("Código").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Espaco.m)
            .padding(.bottom, Espaco.s)

            if aba == 0 {
                VisualizadorDeArtefato(html: documento, recarga: recarga, registros: $registros)
            } else {
                codigoVisivel
            }

            if !registros.isEmpty {
                faixaDeConsole
            }
        }
        .background(Cores.fundo)
        .onAppear { prepararExportacao() }
    }

    private var cabecalho: some View {
        HStack(spacing: Espaco.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(artefato.titulo)
                    .font(Tipografia.titulo(17))
                    .foregroundStyle(Cores.texto)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(artefato.linguagem)
                    .font(Tipografia.legenda())
                    .foregroundStyle(Cores.textoFraco)
                    .lineLimit(1)
            }

            Spacer(minLength: Espaco.s)

            Button(action: recarregar) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Recarregar")

            if let urlParaExportar = urlParaExportar {
                ShareLink(item: urlParaExportar) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Exportar arquivo")
            }

            Button(action: { fechar() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Fechar")
        }
        .foregroundStyle(Cores.texto)
        .padding(.horizontal, Espaco.m)
        .padding(.vertical, Espaco.s)
        .background(Cores.superficie)
    }

    private var codigoVisivel: some View {
        ScrollView {
            Text(artefato.codigo)
                .font(Tipografia.codigo())
                .foregroundStyle(Cores.texto)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Espaco.m)
        }
        .background(Cores.fundo)
    }

    private var faixaDeConsole: some View {
        VStack(alignment: .leading, spacing: Espaco.xs) {
            HStack(spacing: Espaco.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Cores.perigo)
                Text("Console e erros")
                    .font(Tipografia.legenda())
                    .foregroundStyle(Cores.texto)
                Spacer(minLength: 0)
                Button("Limpar") { registros.removeAll() }
                    .font(Tipografia.legenda())
                    .foregroundStyle(Cores.acento)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(registros.indices, id: \.self) { indice in
                        Text(registros[indice])
                            .font(Tipografia.codigo(11))
                            .foregroundStyle(registros[indice].hasPrefix("erro") ? Cores.perigo : Cores.textoFraco)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 120)
        }
        .padding(Espaco.s)
        .background(Cores.perigo.opacity(0.12))
    }

    // MARK: - Ações

    private func recarregar() {
        registros.removeAll()
        recarga += 1
    }

    private func prepararExportacao() {
        let extensao = artefato.tipo == .svg ? "svg" : "html"
        let nome = "\(TelaDeArtefato.nomeSeguro(artefato.titulo))-\(artefato.id).\(extensao)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(nome)
        // SVG sai cru para abrir em ferramenta de desenho; HTML e gráfico saem como a
        // página montada, que é o que o usuário está vendo na tela.
        let conteudo = artefato.tipo == .svg ? artefato.codigo : documento
        do {
            try conteudo.write(to: url, atomically: true, encoding: .utf8)
            urlParaExportar = url
        } catch {
            // Sem arquivo temporário o botão de exportar simplesmente não aparece.
            urlParaExportar = nil
        }
    }

    // MARK: - Montagem do documento

    private static func documentoParaVisualizar(_ artefato: Artefato) -> String {
        switch artefato.tipo {
        case .html:
            return comViewport(artefato.codigo)
        case .svg:
            return pagina(
                corpo: artefato.codigo,
                estiloExtra: "body { display: flex; align-items: center; justify-content: center; } svg { max-width: 100%; height: auto; }"
            )
        case .grafico:
            return pagina(
                corpo: corpoDoGrafico(artefato.codigo),
                estiloExtra: "canvas { max-width: 100%; height: auto; } body { padding: 12px; }"
            )
        }
    }

    /// O gráfico costuma vir como script solto, que sem a tela de desenho não mostra nada.
    private static func corpoDoGrafico(_ codigo: String) -> String {
        if codigo.contains("<canvas") || codigo.contains("<div") || codigo.contains("<svg") {
            return codigo
        }
        let seguro = codigo.replacingOccurrences(of: "</script", with: "<\\/script", options: [.caseInsensitive])
        return """
        <canvas id="grafico" width="640" height="400"></canvas>
        <script>
        \(seguro)
        </script>
        """
    }

    private static func pagina(corpo: String, estiloExtra: String) -> String {
        let estilo = """
        html, body { margin: 0; padding: 0; min-height: 100%; background: #ffffff; color: #111111; }
        body { font-family: -apple-system, "Helvetica Neue", Arial, sans-serif; }
        \(estiloExtra)
        """
        return """
        <!DOCTYPE html>
        <html lang="pt-BR">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <style>
        \(estilo)
        </style>
        </head>
        <body>
        \(corpo)
        </body>
        </html>
        """
    }

    /// Sem viewport, página feita para desktop abre reduzida e ilegível no iPhone.
    private static func comViewport(_ html: String) -> String {
        let minusculo = html.lowercased()
        let jaTem = minusculo.contains("name=\"viewport\"") || minusculo.contains("name='viewport'")
        guard !jaTem else { return html }

        let meta = "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1, viewport-fit=cover\">"
        if let comHead = inserindo(meta, depoisDaTag: "head", em: html) { return comHead }
        if let comHtml = inserindo(meta, depoisDaTag: "html", em: html) { return comHtml }
        if let comDoctype = inserindo(meta, depoisDaTag: "!doctype", em: html) { return comDoctype }
        return meta + html
    }

    private static func inserindo(_ trecho: String, depoisDaTag tag: String, em html: String) -> String? {
        guard let abertura = html.range(of: "<\(tag)", options: .caseInsensitive) else { return nil }
        guard let fim = html[abertura.upperBound...].firstIndex(of: ">") else { return nil }
        var copia = html
        copia.insert(contentsOf: trecho, at: copia.index(after: fim))
        return copia
    }

    private static func nomeSeguro(_ titulo: String) -> String {
        let proibidos = CharacterSet(charactersIn: "/\\:*?\"<>|#%")
        let semProibidos = titulo.components(separatedBy: proibidos).joined(separator: "-")
        let semEspaco = semProibidos.split(whereSeparator: { $0.isWhitespace }).joined(separator: "-")
        let aparado = semEspaco.prefix(40)
        return aparado.isEmpty ? "artefato" : String(aparado)
    }
}
