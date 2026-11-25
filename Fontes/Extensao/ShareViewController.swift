import UIKit
import UniformTypeIdentifiers

#if canImport(PDFKit)
import PDFKit
#endif

// Controlador da extensao de compartilhamento.
// Recebe texto, link ou PDF do menu de compartilhar do sistema e entrega o
// conteudo ao app pelo armazem compartilhado, que e o unico caminho disponivel
// porque a extensao nao enxerga o banco do app. Depois de gravar, abre o app ja
// na conversa nova pela URL dsh://novo.
final class ShareViewController: UIViewController {

    // Tipos de item que a extensao aceita. A ordem importa: o primeiro que
    // existir no item provider define como o conteudo sera lido.
    private let tiposAceitos: [UTType] = [.plainText, .url, .pdf]

    // Texto ja montado a partir de todos os itens recebidos.
    private var textoRecebido: String = ""

    private let rotuloPrevia: UILabel = {
        let rotulo = UILabel()
        rotulo.translatesAutoresizingMaskIntoConstraints = false
        rotulo.numberOfLines = 0
        rotulo.lineBreakMode = .byTruncatingTail
        rotulo.font = .preferredFont(forTextStyle: .body)
        rotulo.textColor = .label
        // Previa curta: o conteudo inteiro fica no armazem, nao na tela.
        rotulo.text = "Lendo o conteudo compartilhado..."
        return rotulo
    }()

    private lazy var botaoEnviar: UIButton = {
        var configuracao = UIButton.Configuration.filled()
        configuracao.title = "Enviar para o DSH"
        let botao = UIButton(configuration: configuracao)
        botao.translatesAutoresizingMaskIntoConstraints = false
        botao.addTarget(self, action: #selector(enviarParaODsh), for: .touchUpInside)
        return botao
    }()

    private lazy var botaoCancelar: UIButton = {
        var configuracao = UIButton.Configuration.plain()
        configuracao.title = "Cancelar"
        let botao = UIButton(configuration: configuracao)
        botao.translatesAutoresizingMaskIntoConstraints = false
        botao.addTarget(self, action: #selector(cancelar), for: .touchUpInside)
        return botao
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        montarInterface()
        carregarItensCompartilhados()
    }

    // MARK: - Interface

    private func montarInterface() {
        view.backgroundColor = .systemBackground

        let pilha = UIStackView(arrangedSubviews: [rotuloPrevia, botaoEnviar, botaoCancelar])
        pilha.translatesAutoresizingMaskIntoConstraints = false
        pilha.axis = .vertical
        pilha.spacing = 16
        pilha.alignment = .fill
        view.addSubview(pilha)

        let guia = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            pilha.topAnchor.constraint(equalTo: guia.topAnchor, constant: 24),
            pilha.leadingAnchor.constraint(equalTo: guia.leadingAnchor, constant: 20),
            pilha.trailingAnchor.constraint(equalTo: guia.trailingAnchor, constant: -20),
            pilha.bottomAnchor.constraint(lessThanOrEqualTo: guia.bottomAnchor, constant: -24),
            botaoEnviar.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])

        // Enquanto nada foi lido, enviar nao faz sentido.
        botaoEnviar.isEnabled = false
    }

    private func atualizarPrevia() {
        let texto = textoRecebido.trimmingCharacters(in: .whitespacesAndNewlines)
        if texto.isEmpty {
            rotuloPrevia.text = "Nenhum texto, link ou PDF encontrado no que foi compartilhado."
            botaoEnviar.isEnabled = false
            return
        }
        // Previa limitada para nao estourar a tela com um PDF ou texto longo.
        if texto.count > 400 {
            rotuloPrevia.text = String(texto.prefix(400)) + "..."
        } else {
            rotuloPrevia.text = texto
        }
        botaoEnviar.isEnabled = true
    }

    // MARK: - Leitura do que veio do sistema

    private func carregarItensCompartilhados() {
        guard let itens = extensionContext?.inputItems as? [NSExtensionItem] else {
            atualizarPrevia()
            return
        }

        let provedores: [NSItemProvider] = itens.flatMap { $0.attachments ?? [] }
        guard !provedores.isEmpty else {
            atualizarPrevia()
            return
        }

        carregar(provedores: provedores, indice: 0, acumulado: [])
    }

    // Le os provedores em sequencia para preservar a ordem em que o sistema
    // entregou os itens: link no meio do caminho nao pode embaralhar o texto.
    private func carregar(provedores: [NSItemProvider], indice: Int, acumulado: [String]) {
        if indice >= provedores.count {
            textoRecebido = acumulado.joined(separator: "\n")
            atualizarPrevia()
            return
        }

        let provedor = provedores[indice]
        guard let tipo = tipoAceito(em: provedor) else {
            carregar(provedores: provedores, indice: indice + 1, acumulado: acumulado)
            return
        }

        carregarItem(do: provedor, tipo: tipo) { [weak self] trecho in
            guard let self = self else { return }
            var proximo = acumulado
            if let trecho = trecho, !trecho.isEmpty {
                proximo.append(trecho)
            }
            self.carregar(provedores: provedores, indice: indice + 1, acumulado: proximo)
        }
    }

    private func tipoAceito(em provedor: NSItemProvider) -> UTType? {
        for tipo in tiposAceitos where provedor.hasItemConformingToTypeIdentifier(tipo.identifier) {
            return tipo
        }
        return nil
    }

    private func carregarItem(do provedor: NSItemProvider, tipo: UTType, conclusao: @escaping (String?) -> Void) {
        if tipo == .pdf {
            // PDF precisa do arquivo em disco para a extracao ler as paginas.
            provedor.loadFileRepresentation(forTypeIdentifier: tipo.identifier) { [weak self] url, _ in
                var trecho: String?
                if let url = url {
                    trecho = self?.textoDePdf(em: url)
                }
                DispatchQueue.main.async {
                    conclusao(trecho)
                }
            }
            return
        }

        provedor.loadItem(forTypeIdentifier: tipo.identifier, options: nil) { item, _ in
            var trecho: String?
            if tipo == .url {
                if let url = item as? URL {
                    trecho = url.absoluteString
                } else if let url = item as? NSURL {
                    trecho = (url as URL).absoluteString
                }
            } else if let texto = item as? String {
                trecho = texto
            } else if let dados = item as? Data {
                trecho = String(data: dados, encoding: .utf8)
            }
            DispatchQueue.main.async {
                conclusao(trecho)
            }
        }
    }

    // Extrai o texto do PDF quando o sistema consegue abrir o documento. Se nao
    // conseguir, so o nome do arquivo e melhor que nada, porque ao menos diz ao
    // usuario o que foi enviado.
    private func textoDePdf(em url: URL) -> String {
        let nome = url.lastPathComponent
        #if canImport(PDFKit)
        if let documento = PDFDocument(url: url),
           let texto = documento.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !texto.isEmpty {
            return "\(nome)\n\(texto)"
        }
        #endif
        return nome
    }

    // MARK: - Acoes

    @objc private func enviarParaODsh() {
        let texto = textoRecebido.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty else {
            cancelar()
            return
        }

        // Grava primeiro, abre depois: se o app demorar a subir, o conteudo ja
        // esta no armazem compartilhado e nao se perde.
        ArmazemCompartilhado.guardarTextoParaConversa(texto)
        ArmazemCompartilhado.guardarRotaPendente(.novo)

        guard let url = URL(string: "dsh://novo?origem=compartilhar") else {
            cancelar()
            return
        }

        extensionContext?.open(url) { [weak self] sucesso in
            guard let self = self else { return }
            if sucesso {
                self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            } else {
                self.extensionContext?.cancelRequest(withError: self.erroDeCompartilhamento(
                    codigo: 1,
                    descricao: "Nao foi possivel abrir o DSH."
                ))
            }
        }
    }

    @objc private func cancelar() {
        extensionContext?.cancelRequest(withError: erroDeCompartilhamento(
            codigo: 0,
            descricao: "Compartilhamento cancelado."
        ))
    }

    private func erroDeCompartilhamento(codigo: Int, descricao: String) -> NSError {
        return NSError(
            domain: "dev.ramses.dsh.compartilhar",
            code: codigo,
            userInfo: [NSLocalizedDescriptionKey: descricao]
        )
    }
}
