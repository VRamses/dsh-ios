import SwiftUI
import WebKit

/// Ponte entre o SwiftUI e o WKWebView que desenha o artefato.
/// Fica separado da tela para deixar claro que todo o estado de navegação morre junto
/// com a folha, sem cookie, cache ou storage que sobrevivam a ela.
struct VisualizadorDeArtefato: UIViewRepresentable {
    var html: String
    var recarga: Int
    @Binding var registros: [String]

    func makeCoordinator() -> Coordenador {
        Coordenador(registros: $registros)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuracao = WKWebViewConfiguration()
        // Armazenamento só em memória: o artefato não enxerga cookie nem cache da API.
        configuracao.websiteDataStore = .nonPersistent()
        configuracao.defaultWebpagePreferences.allowsContentJavaScript = true
        configuracao.allowsInlineMediaPlayback = true

        let controlador = WKUserContentController()
        controlador.addUserScript(
            WKUserScript(source: scriptDeDiagnostico, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )
        controlador.add(context.coordinator, name: "dshConsole")
        configuracao.userContentController = controlador

        let web = WKWebView(frame: .zero, configuration: configuracao)
        web.navigationDelegate = context.coordinator
        // Página clara fixa: artefato de IA supõe folha branca e texto escuro. Seguir o
        // modo escuro do app deixaria texto preto em fundo escuro e pareceria tela branca.
        web.isOpaque = true
        web.backgroundColor = .white
        web.scrollView.backgroundColor = .white
        web.overrideUserInterfaceStyle = .light

        context.coordinator.ultimaRecarga = recarga
        web.loadHTMLString(html, baseURL: nil)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.registros = $registros
        if context.coordinator.ultimaRecarga != recarga {
            context.coordinator.ultimaRecarga = recarga
            web.loadHTMLString(html, baseURL: nil)
        }
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordenador) {
        web.stopLoading()
        web.configuration.userContentController.removeScriptMessageHandler(forName: "dshConsole")
    }

    /// Recebe o console da página, os erros de script e as falhas de navegação, e repassa
    /// para a faixa da tela. Fica aninhado para não disputar nome com o resto do app e é
    /// classe porque os protocolos do WebKit exigem NSObject.
    final class Coordenador: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var registros: Binding<[String]>
        var ultimaRecarga = -1

        private var ultimoRegistro = ""

        init(registros: Binding<[String]>) {
            self.registros = registros
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "dshConsole", let texto = message.body as? String else { return }
            registrar(texto)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            // Recarga recomeça a página: sem isto o mesmo erro da carga anterior seria
            // engolido pela deduplicação e a faixa ficaria vazia com a tela em branco.
            ultimoRegistro = ""
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body ? (document.body.children.length + (document.body.textContent || '').trim().length) : -1") { [weak self] resultado, _ in
                guard let quantidade = resultado as? Int, quantidade == 0 else { return }
                self?.registrar("aviso: a página carregou sem conteúdo visível")
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            registrar("erro: falha ao carregar (\(error.localizedDescription))")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            registrar("erro: falha ao carregar (\(error.localizedDescription))")
        }

        private func registrar(_ texto: String) {
            DispatchQueue.main.async {
                // Biblioteca de gráfico costuma repetir o mesmo aviso em laço: sem este
                // corte a faixa virava uma parede de linhas iguais.
                guard texto != self.ultimoRegistro else { return }
                self.ultimoRegistro = texto

                var lista = self.registros.wrappedValue
                lista.append(texto)
                if lista.count > 40 {
                    lista.removeFirst(lista.count - 40)
                }
                self.registros.wrappedValue = lista
            }
        }
    }
}

/// Injetado antes de qualquer script da página para que o motivo da tela branca chegue
/// ao app: sem isso, erro de JavaScript do artefato morre dentro do WebKit.
private let scriptDeDiagnostico = """
(function () {
  var ponte = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.dshConsole;
  if (!ponte) { return; }
  var enviar = function (tipo, texto) {
    try { ponte.postMessage(tipo + ": " + texto); } catch (e) {}
  };
  var descrever = function (valor) {
    if (valor === null) { return "null"; }
    if (valor === undefined) { return "undefined"; }
    if (typeof valor === "string") { return valor; }
    if (typeof valor === "object") {
      try { return JSON.stringify(valor); } catch (e) { return String(valor); }
    }
    return String(valor);
  };
  var juntar = function (argumentos) {
    var partes = [];
    for (var i = 0; i < argumentos.length; i++) { partes.push(descrever(argumentos[i])); }
    return partes.join(" ");
  };
  var originais = { log: console.log, warn: console.warn, error: console.error };
  try {
    ["log", "warn", "error"].forEach(function (nivel) {
      console[nivel] = function () {
        enviar(nivel, juntar(arguments));
        if (originais[nivel]) { originais[nivel].apply(console, arguments); }
      };
    });
  } catch (e) {}
  window.addEventListener("error", function (evento) {
    if (evento.target && evento.target !== window && (evento.target.src || evento.target.href)) {
      enviar("erro", "recurso não carregou: " + (evento.target.src || evento.target.href));
      return;
    }
    enviar("erro", (evento.message || "erro de script") + " (" + (evento.filename || "inline") + ":" + (evento.lineno || 0) + ")");
  }, true);
  window.addEventListener("unhandledrejection", function (evento) {
    enviar("erro", "promessa rejeitada: " + descrever(evento.reason));
  });
})();
"""
