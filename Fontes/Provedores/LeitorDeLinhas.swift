import Foundation

/// Pedaço de resposta entregue pelo leitor: primeiro o cabeçalho, depois uma
/// linha de cada vez, conforme o corpo chega.
enum EventoDoCorpo {
    case cabecalho(HTTPURLResponse)
    case linha(String)
}

/// Lê uma resposta HTTP linha a linha pela delegação do URLSession.
///
/// A leitura por `bytes(for:)` não serve para resposta comprimida: ela entrega o
/// corpo como veio, sem descomprimir. A API do DeepSeek responde
/// `content-encoding: br` quando o cliente aceita compressão, e aí o app recebia
/// 200 com zero linhas legíveis e mostrava "não mandou nenhum pedaço de texto".
/// Com o delegate quem negocia a compressão é o próprio URLSession, que pede o
/// que suporta e entrega o corpo já descomprimido.
final class LeitorDeLinhas: NSObject, URLSessionDataDelegate {
    private var continuacao: AsyncThrowingStream<EventoDoCorpo, Error>.Continuation?
    private var sessao: URLSession?
    private var tarefa: URLSessionDataTask?
    // Bytes que chegaram sem a quebra de linha que fecha a linha. Guardar o resto
    // evita perder texto quando o pedaço do stream corta no meio de uma linha.
    private var sobra = Data()
    private var terminou = false

    func abrir(
        _ requisicao: URLRequest,
        configuracao base: URLSessionConfiguration = .default
    ) -> AsyncThrowingStream<EventoDoCorpo, Error> {
        AsyncThrowingStream { continuacao in
            self.continuacao = continuacao
            let configuracao = base.copy() as? URLSessionConfiguration ?? .default
            // Vale para a espera entre pacotes: um stream aberto e mudo não pode
            // segurar a conversa para sempre.
            configuracao.timeoutIntervalForRequest = requisicao.timeoutInterval
            let sessao = URLSession(configuration: configuracao, delegate: self, delegateQueue: nil)
            self.sessao = sessao
            let tarefa = sessao.dataTask(with: requisicao)
            self.tarefa = tarefa
            continuacao.onTermination = { [weak self] _ in
                self?.parar()
            }
            tarefa.resume()
        }
    }

    func cancelar() {
        parar()
    }

    private func parar() {
        tarefa?.cancel()
        sessao?.invalidateAndCancel()
        tarefa = nil
        sessao = nil
        if !terminou {
            terminou = true
            continuacao?.finish()
        }
    }

    func urlSession(
        _ sessao: URLSession,
        dataTask: URLSessionDataTask,
        didReceive resposta: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = resposta as? HTTPURLResponse {
            continuacao?.yield(.cabecalho(http))
        }
        completionHandler(.allow)
    }

    func urlSession(_ sessao: URLSession, dataTask: URLSessionDataTask, didReceive dados: Data) {
        sobra.append(dados)
        while let corte = sobra.firstIndex(of: 0x0A) {
            let pedaco = sobra[sobra.startIndex..<corte]
            sobra = sobra[sobra.index(after: corte)...]
            if var texto = String(data: pedaco, encoding: .utf8) {
                if texto.hasSuffix("\r") { texto.removeLast() }
                continuacao?.yield(.linha(texto))
            }
        }
    }

    func urlSession(_ sessao: URLSession, task: URLSessionTask, didCompleteWithError erro: Error?) {
        if !sobra.isEmpty, let texto = String(data: sobra, encoding: .utf8), !texto.isEmpty {
            continuacao?.yield(.linha(texto))
        }
        sobra = Data()
        if terminou { return }
        terminou = true
        if let erro {
            continuacao?.finish(throwing: erro)
        } else {
            continuacao?.finish()
        }
        sessao.invalidateAndCancel()
    }
}
