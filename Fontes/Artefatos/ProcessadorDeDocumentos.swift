import Foundation
import ImageIO
import PDFKit
import UIKit
import Vision

/// Extrai o texto dos anexos sempre fora da main thread. O texto inteiro vai para o
/// prompt do modelo, então cada processador tem teto: acima dele o pedido estoura e a
/// tela fica esperando um anexo que nunca chega.
enum ProcessadorDeDocumentos {

    /// Teto de caracteres por anexo. Ao cortar, o próprio texto do Anexo avisa, porque o
    /// tipo Anexo do contrato não tem campo para aviso.
    static let limiteDeCaracteres = 60_000

    /// Páginas de PDF lidas direto da camada de texto.
    static let limiteDePaginas = 300

    /// Páginas que passam por OCR quando o PDF é digitalizado, isto é, sem camada de texto.
    static let limiteDePaginasComOcr = 8

    /// Lado máximo da imagem mandada ao Vision. Foto de 12 MP sem redução leva minutos.
    static let ladoMaximoDoOcr: CGFloat = 2_400

    /// Prazo do OCR de PDF digitalizado, conferido entre páginas. Vision não expõe
    /// cancelamento público, então o corte é por quantidade de páginas e por relógio.
    static let prazoDoOcr: TimeInterval = 20

    // MARK: - Entradas

    static func dePdf(url: URL) async throws -> Anexo {
        let nome = url.lastPathComponent.isEmpty ? "documento.pdf" : url.lastPathComponent
        return try await foraDaMainThread {
            let tamanho = tamanhoEmBytes(de: url)
            let texto = try textoDePdf(url)
            return Anexo(id: UUID(), nome: nome, tipo: .pdf, texto: truncar(texto), tamanhoEmBytes: tamanho)
        }
    }

    /// Foto da câmera ou da galeria. O contrato do `Anexo` guarda texto e não pixels,
    /// então o que chega ao modelo é o OCR. Quando a foto não tem texto, entra o que o
    /// classificador de cena reconhece, com aviso: foto de paisagem, comida ou bicho
    /// deixa de virar erro e passa a dar ao modelo alguma coisa sobre o que perguntar.
    static func deImagem(_ imagem: UIImage, nome: String? = nil) async throws -> Anexo {
        try await foraDaMainThread {
            // O JPEG é o que alimenta o OCR: recomprimir aqui evita manter o UIImage
            // original vivo na fila de trabalho e normaliza a orientação do EXIF.
            let dados: Data
            let nomePadrao: String
            if let jpeg = imagem.jpegData(compressionQuality: 0.9) {
                dados = jpeg
                nomePadrao = "Imagem.jpg"
            } else if let png = imagem.pngData() {
                dados = png
                nomePadrao = "Imagem.png"
            } else {
                throw erroLocal("Não foi possível ler a imagem.")
            }

            let texto = try reconhecerTexto(em: dados)
            let conteudo: String
            if !texto.isEmpty {
                conteudo = texto
            } else {
                let rotulos = rotularCena(em: dados)
                guard !rotulos.isEmpty else {
                    throw erroLocal("Não achei texto nem cena conhecida nessa foto.")
                }
                conteudo = "[foto sem texto legível; conteúdo provável: \(rotulos.joined(separator: ", "))]"
            }
            return Anexo(
                id: UUID(),
                nome: nome ?? nomePadrao,
                tipo: .imagem,
                texto: truncar(conteudo),
                tamanhoEmBytes: dados.count
            )
        }
    }

    static func deTexto(url: URL) async throws -> Anexo {
        let nome = url.lastPathComponent.isEmpty ? "texto.txt" : url.lastPathComponent
        let tipo: Anexo.Tipo = extensoesDeCodigo.contains(url.pathExtension.lowercased()) ? .codigo : .texto
        return try await foraDaMainThread {
            let dados = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard !dados.isEmpty else {
                throw erroLocal("O arquivo está vazio.")
            }
            let texto = try decodificar(dados)
            let limpo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !limpo.isEmpty else {
                throw erroLocal("O arquivo não tem texto legível.")
            }
            return Anexo(id: UUID(), nome: nome, tipo: tipo, texto: truncar(limpo), tamanhoEmBytes: dados.count)
        }
    }

    // MARK: - PDF

    private static func textoDePdf(_ url: URL) throws -> String {
        guard let documento = PDFDocument(url: url) else {
            throw erroLocal("Não foi possível abrir o PDF.")
        }
        guard !documento.isLocked else {
            throw erroLocal("O PDF está protegido por senha.")
        }

        let total = min(documento.pageCount, limiteDePaginas)
        var partes: [String] = []

        for indice in 0..<total {
            guard let pagina = documento.page(at: indice) else { continue }
            let texto = (pagina.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !texto.isEmpty {
                partes.append(texto)
            }
        }

        if partes.isEmpty {
            // PDF digitalizado: sem camada de texto, a saída é OCR das primeiras páginas.
            let prazo = Date().addingTimeInterval(prazoDoOcr)
            var interrompido = false
            let paginas = min(total, limiteDePaginasComOcr)

            for indice in 0..<paginas {
                if Date() > prazo {
                    interrompido = true
                    break
                }
                guard let pagina = documento.page(at: indice) else { continue }
                let imagem = pagina.thumbnail(of: CGSize(width: 1240, height: 1754), for: .mediaBox)
                if let dados = imagem.jpegData(compressionQuality: 0.9),
                   let texto = try? reconhecerTexto(em: dados),
                   !texto.isEmpty {
                    partes.append(texto)
                }
            }

            if interrompido {
                guard !partes.isEmpty else {
                    throw erroLocal("O OCR do PDF não terminou dentro do tempo.")
                }
                partes.append("[aviso: OCR interrompido após \(Int(prazoDoOcr)) segundos; as páginas seguintes ficaram de fora.]")
            }
        }

        guard !partes.isEmpty else {
            throw erroLocal("O PDF não tem texto que possa ser lido.")
        }
        return partes.joined(separator: "\n\n")
    }

    // MARK: - OCR

    private static func reconhecerTexto(em dados: Data) throws -> String {
        guard let imagem = imagemReduzida(de: dados) else {
            throw erroLocal("Não foi possível preparar a imagem para o OCR.")
        }

        let pedido = VNRecognizeTextRequest()
        pedido.recognitionLanguages = ["pt-BR", "en-US"]
        pedido.recognitionLevel = .accurate
        pedido.usesLanguageCorrection = true

        let manipulador = VNImageRequestHandler(cgImage: imagem, options: [:])
        do {
            try manipulador.perform([pedido])
        } catch {
            throw erroLocal("O OCR falhou: \(error.localizedDescription)")
        }

        let observacoes = pedido.results ?? []
        let linhas = observacoes.compactMap { $0.topCandidates(1).first?.string }
        return linhas.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Rótulos do classificador de cena, do mais provável para o menos, só para foto
    /// sem texto. O corte de confiança existe porque abaixo dele o rótulo vira chute.
    private static func rotularCena(em dados: Data) -> [String] {
        guard let imagem = imagemReduzida(de: dados) else { return [] }

        let pedido = VNClassifyImageRequest()
        let manipulador = VNImageRequestHandler(cgImage: imagem, options: [:])
        guard (try? manipulador.perform([pedido])) != nil else { return [] }

        let observacoes = (pedido.results ?? [])
            .filter { $0.confidence >= 0.35 }
            .prefix(6)
        return observacoes.map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
    }

    private static func imagemReduzida(de dados: Data) -> CGImage? {
        guard let fonte = CGImageSourceCreateWithData(dados as CFData, nil) else { return nil }
        let opcoes: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(ladoMaximoDoOcr),
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(fonte, 0, opcoes as CFDictionary)
    }

    // MARK: - Texto e codificação

    private static let extensoesDeCodigo: Set<String> = [
        "swift", "m", "mm", "h", "c", "cc", "cpp", "hpp", "cs", "java", "kt", "kts",
        "js", "mjs", "cjs", "jsx", "ts", "tsx", "py", "rb", "go", "rs", "php", "pl",
        "lua", "dart", "r", "scala", "sh", "bash", "zsh", "ps1", "bat", "cmd",
        "sql", "json", "yaml", "yml", "toml", "xml", "html", "htm", "css", "scss",
        "sass", "less", "vue", "svelte", "ex", "exs", "erl", "hs", "clj", "groovy",
        "gradle", "mk", "cmake", "ini", "conf", "properties"
    ]

    private static func decodificar(_ dados: Data) throws -> String {
        if dados.starts(with: [0xEF, 0xBB, 0xBF] as [UInt8]) {
            let corpo = dados.dropFirst(3)
            return String(data: Data(corpo), encoding: .utf8) ?? String(decoding: corpo, as: UTF8.self)
        }
        if dados.starts(with: [0xFF, 0xFE] as [UInt8]) {
            return String(data: Data(dados.dropFirst(2)), encoding: .utf16LittleEndian) ?? ""
        }
        if dados.starts(with: [0xFE, 0xFF] as [UInt8]) {
            return String(data: Data(dados.dropFirst(2)), encoding: .utf16BigEndian) ?? ""
        }
        // NUL no começo de arquivo sem BOM é binário: decodificar isso só produziria
        // texto sem sentido dentro do prompt.
        if dados.prefix(4096).contains(0) {
            throw erroLocal("O arquivo parece binário, não texto.")
        }
        if let texto = String(data: dados, encoding: .utf8) { return texto }
        if let texto = String(data: dados, encoding: .windowsCP1252) { return texto }
        return String(decoding: dados, as: UTF8.self)
    }

    // MARK: - Utilidades

    private static func truncar(_ texto: String) -> String {
        guard texto.count > limiteDeCaracteres else { return texto }
        let corte = String(texto.prefix(limiteDeCaracteres))
        let restante = texto.count - limiteDeCaracteres
        return corte + "\n\n[aviso: texto truncado em \(limiteDeCaracteres) caracteres; \(restante) ficaram de fora. Peça o arquivo completo se precisar do restante.]"
    }

    private static func tamanhoEmBytes(de url: URL) -> Int {
        let atributos = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let tamanho = atributos?[.size] as? NSNumber {
            return tamanho.intValue
        }
        return 0
    }

    private static func erroLocal(_ mensagem: String) -> NSError {
        NSError(domain: "ProcessadorDeDocumentos", code: 1, userInfo: [NSLocalizedDescriptionKey: mensagem])
    }

    /// PDFKit, Vision e leitura de arquivo são síncronos: sem sair da main thread a
    /// interface congela durante o processamento.
    private static func foraDaMainThread<T>(_ trabalho: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { (continuacao: CheckedContinuation<T, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuacao.resume(returning: try trabalho())
                } catch {
                    continuacao.resume(throwing: error)
                }
            }
        }
    }
}
