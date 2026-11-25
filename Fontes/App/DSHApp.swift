import Combine
import SwiftData
import SwiftUI

// Ponto de entrada do DSH. Monta a `TelaPrincipal` do swift-chat, trata os
// endereços dsh:// vindos da extensão de compartilhamento, instala o motor de
// pergunta rápida usado pelas intenções do sistema e abre as rotas de captura
// do CI (`-rota voz` e `-rota artefato`).
@main
struct DSHApp: App {
    @State private var rota: RotaDeLancamento
    @State private var demonstracao: Bool
    @State private var conversaDeDemonstracao: Conversa?
    @State private var conversaCompartilhada: Conversa?
    @StateObject private var voz: GerenciadorDeVoz

    private let contentor: ModelContainer?
    private let servicoPonte: ServicoPonte?

    init() {
        let estado = EstadoDeLancamento.ler(argumentos: ProcessInfo.processInfo.arguments)
        _rota = State(initialValue: estado.rota)
        _demonstracao = State(initialValue: estado.demonstracao)
        _voz = StateObject(wrappedValue: GerenciadorDeVoz())

        let configuracao = ModelConfiguration(isStoredInMemoryOnly: estado.demonstracao)
        let contentor = try? ModelContainer(
            for: Conversa.self,
            Mensagem.self,
            Projeto.self,
            MemoriaDoUsuario.self,
            configurations: configuracao
        )
        self.contentor = contentor
        self.servicoPonte = ServicoPonte.aPartirDasPreferencias()

        if estado.demonstracao, let contentor {
            let conversa = DadosDeDemonstracao.instalar(em: contentor.mainContext)
            _conversaDeDemonstracao = State(initialValue: conversa)
        }

        print("rota efetiva: \(estado.rota.id)")
        if estado.demonstracao {
            print("demonstracao ligada: dados de captura em memoria")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let contentor {
                    TelaPrincipal(
                        conversaInicial: conversaInicial,
                        servicoPonte: servicoPonte,
                        abrirSessoesInicial: rota == .dsh
                    )
                        .id(identidadeDaRaiz)
                        .modelContainer(contentor)
                        .sheet(isPresented: apresentandoArtefato) {
                            TelaDeArtefato(artefato: DadosDeDemonstracao.artefato())
                        }
                        .sheet(isPresented: apresentandoAjustes) {
                            TelaDeAjustes()
                        }
                        .fullScreenCover(isPresented: apresentandoVoz) {
                            TelaDeVoz(
                                voz: voz,
                                enviar: { texto in enviarPelaVoz(texto) },
                                fechar: { rota = .conversa }
                            )
                        }
                        .task {
                            AdaptadorDePerguntaRapida.registrar()
                            retomarRotaPendente()
                        }
                } else {
                    Text("Não foi possível abrir o banco local do DSH.")
                        .padding()
                }
            }
            .onOpenURL { url in
                TratadorDeUrl.abrir(url)
            }
            .onReceive(NotificationCenter.default.publisher(for: TratadorDeUrl.notificacaoDaRota)) { notificacao in
                receberRota(notificacao.userInfo)
            }
        }
    }

    // MARK: - Apresentação

    private var conversaInicial: Conversa? {
        conversaCompartilhada ?? conversaDeDemonstracao
    }

    // TelaPrincipal só lê `conversaInicial` no primeiro `configurar()`; trocar a
    // identidade força uma tela nova quando chega texto compartilhado ou de voz
    // com o app já aberto.
    private var identidadeDaRaiz: String {
        conversaCompartilhada?.id.uuidString ?? "raiz"
    }

    private var apresentandoArtefato: Binding<Bool> {
        Binding(
            get: { rota == .artefato },
            set: { apresentando in
                if !apresentando { rota = .conversa }
            }
        )
    }

    private var apresentandoVoz: Binding<Bool> {
        Binding(
            get: { rota == .voz },
            set: { apresentando in
                if !apresentando { rota = .conversa }
            }
        )
    }

    private var apresentandoAjustes: Binding<Bool> {
        Binding(
            get: { rota == .ajustes },
            set: { apresentando in
                if !apresentando { rota = .conversa }
            }
        )
    }

    // MARK: - Rotas

    @MainActor
    private func receberRota(_ userInfo: [AnyHashable: Any]?) {
        guard let recebida = userInfo?[TratadorDeUrl.Chave.rota] as? RotaDoApp else { return }
        let origem = userInfo?[TratadorDeUrl.Chave.origem] as? String

        switch recebida {
        case .voz:
            rota = .voz
        case .ajustes:
            rota = .ajustes
        case .novo:
            rota = .conversa
            if origem == TratadorDeUrl.origemDeCompartilhamento {
                abrirTextoCompartilhado()
            }
        default:
            rota = .conversa
        }
    }

    @MainActor
    private func retomarRotaPendente() {
        guard let pendente = ArmazemCompartilhado.consumirRotaPendente() else { return }
        switch pendente {
        case .voz:
            rota = .voz
        case .novo:
            rota = .conversa
            abrirTextoCompartilhado()
        default:
            rota = .conversa
        }
    }

    @MainActor
    private func abrirTextoCompartilhado() {
        guard let texto = ArmazemCompartilhado.consumirTextoPendente() else { return }
        guard let conversa = criarConversa(com: texto, titulo: "Compartilhado de outro app") else { return }
        conversaCompartilhada = conversa
        rota = .conversa
    }

    @MainActor
    private func enviarPelaVoz(_ texto: String) {
        guard let conversa = criarConversa(com: texto, titulo: "Pergunta por voz") else { return }
        conversaCompartilhada = conversa
        rota = .conversa
    }

    @MainActor
    private func criarConversa(com texto: String, titulo: String) -> Conversa? {
        let limpo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpo.isEmpty, let contentor else { return nil }

        let contexto = contentor.mainContext
        let conversa = Conversa(titulo: titulo)
        let mensagem = Mensagem(papel: .usuario, conteudo: limpo, conversa: conversa)
        conversa.mensagens = [mensagem]
        contexto.insert(conversa)
        contexto.insert(mensagem)
        try? contexto.save()
        return conversa
    }
}
