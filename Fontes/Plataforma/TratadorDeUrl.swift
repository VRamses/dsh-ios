import Foundation

// Tratamento dos endereços do DSH: dsh:// e deepseekharness://.
// O app entrega o URL aqui, a rota fica gravada no armazém compartilhado e uma
// notificação avisa quem estiver escutando. A extensão de compartilhamento não
// importa este arquivo (ela não está no alvo do app), por isso o endereço que ela
// abre é o mesmo texto literal tratado aqui.

enum TratadorDeUrl {

    // MARK: - Notificação

    // Nome único da notificação. O DSHApp do swift-base escuta por ele.
    static let notificacaoDaRota = Notification.Name("dev.ramses.dsh.rotaRecebida")

    // Chaves de userInfo que acompanham a notificação.
    enum Chave {
        // RotaDoApp com a rota reconhecida.
        static let rota = "rota"
        // String com o valor de origem quando existe, por exemplo "compartilhar".
        static let origem = "origem"
        // String com o endereço completo, útil para diagnóstico.
        static let endereco = "endereco"
    }

    // Origem usada pelo ShareViewController ao enviar texto para o app.
    // Fica repetida como literal na extensão porque Fontes/Compartilhado é do
    // swift-base; se um dia virar constante lá, os dois lados apontam para ela.
    static let origemDeCompartilhamento = "compartilhar"

    // Endereço que a extensão abre depois de gravar o texto pendente.
    static let enderecoDeCompartilhamento = "dsh://novo?origem=compartilhar"

    // MARK: - Leitura

    // Aceita dsh:conversa, dsh://conversa, dsh://conversa/qualquer e os mesmos
    // formatos com o esquema alternativo deepseekharness. Devolve nil para o que
    // não for rota conhecida.
    static func rota(de url: URL) -> RotaDoApp? {
        guard let esquema = url.scheme?.lowercased(), DeepLinks.todosOsEsquemas.contains(esquema) else {
            return nil
        }
        if let rota = DeepLinks.rota(de: url) {
            return rota
        }
        // Esquema sem host e sem caminho: abrir o app cai na conversa, que é a
        // rota padrão do contrato.
        if semDestino(url) {
            return .conversa
        }
        return nil
    }

    // Parâmetro origem, tolerante a ausência, a caixa alta e a espaços.
    static func origem(de url: URL) -> String? {
        guard let componentes = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let itens = componentes.queryItems,
              let valor = itens.first(where: { $0.name.lowercased() == "origem" })?.value else {
            return nil
        }
        let limpo = valor.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return limpo.isEmpty ? nil : limpo
    }

    // Precisa ser tratado como compartilhamento: rota novo vinda da extensão.
    static func veioDoCompartilhamento(_ url: URL) -> Bool {
        if url.absoluteString == enderecoDeCompartilhamento {
            return true
        }
        return rota(de: url) == .novo && origem(de: url) == origemDeCompartilhamento
    }

    // MARK: - Abertura

    // Grava a rota e avisa o app. Chamar daqui é idempotente: a extensão já pode
    // ter gravado a mesma rota antes de abrir o endereço.
    @MainActor
    static func abrir(_ url: URL) {
        guard let rota = rota(de: url) else { return }

        ArmazemCompartilhado.guardarRotaPendente(rota)

        var dados: [AnyHashable: Any] = [
            Chave.rota: rota,
            Chave.endereco: url.absoluteString
        ]
        if let origem = origem(de: url) {
            dados[Chave.origem] = origem
        }
        NotificationCenter.default.post(name: notificacaoDaRota, object: nil, userInfo: dados)
    }

    // MARK: - Apoio

    private static let barras = CharacterSet(charactersIn: "/")

    private static func semDestino(_ url: URL) -> Bool {
        let host = (url.host ?? "").trimmingCharacters(in: barras)
        let caminho = url.path.trimmingCharacters(in: barras)
        return host.isEmpty && caminho.isEmpty
    }
}
