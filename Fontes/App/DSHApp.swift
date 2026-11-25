import Combine
import SwiftData
import SwiftUI

// Ponto de entrada do DSH. Enquanto as telas do swift-chat não estão no disco,
// a raiz é uma tela mínima própria (TelaInicial); quando `TelaPrincipal` chegar,
// a troca é só a linha dentro da WindowGroup.
@main
struct DSHApp: App {
    @State private var rota: RotaDeLancamento
    @State private var rotaDoApp: RotaDoApp = .conversa
    @State private var demonstracao: Bool
    @State private var textoCompartilhado: String?
    @State private var conversaDeDemonstracao: Conversa?

    private let contentor: ModelContainer?

    init() {
        let estado = EstadoDeLancamento.ler(argumentos: ProcessInfo.processInfo.arguments)
        _rota = State(initialValue: estado.rota)
        _demonstracao = State(initialValue: estado.demonstracao)

        let configuracao = ModelConfiguration(isStoredInMemoryOnly: estado.demonstracao)
        contentor = try? ModelContainer(
            for: Conversa.self,
            Mensagem.self,
            Projeto.self,
            MemoriaDoUsuario.self,
            configurations: configuracao
        )

        print("rota efetiva: \(estado.rota.id)")
        if estado.demonstracao {
            print("demonstracao ligada: dados de captura em memoria")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let contentor {
                    TelaInicial(
                        rota: rota,
                        demonstracao: demonstracao,
                        rotaDoApp: rotaDoApp,
                        textoCompartilhado: textoCompartilhado,
                        conversa: conversaDeDemonstracao
                    )
                    .modelContainer(contentor)
                    .task {
                        AdaptadorDePerguntaRapida.registrar()
                        retomarRotaPendente()
                        if demonstracao {
                            prepararDemonstracao(em: contentor)
                        }
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

    @MainActor
    private func receberRota(_ userInfo: [AnyHashable: Any]?) {
        if let recebida = userInfo?[TratadorDeUrl.Chave.rota] as? RotaDoApp {
            rotaDoApp = recebida
        }
        let origem = userInfo?[TratadorDeUrl.Chave.origem] as? String
        if rotaDoApp == .novo, origem == TratadorDeUrl.origemDeCompartilhamento {
            textoCompartilhado = ArmazemCompartilhado.consumirTextoPendente()
        }
    }

    @MainActor
    private func retomarRotaPendente() {
        guard let pendente = ArmazemCompartilhado.consumirRotaPendente() else { return }
        rotaDoApp = pendente
        if pendente == .novo {
            textoCompartilhado = ArmazemCompartilhado.consumirTextoPendente()
        }
    }

    @MainActor
    private func prepararDemonstracao(em contentor: ModelContainer) {
        guard conversaDeDemonstracao == nil else { return }
        conversaDeDemonstracao = DadosDeDemonstracao.instalar(em: contentor.mainContext)
    }
}

// Tela mínima para o build fechar sem depender de Fontes/Conversa.
struct TelaInicial: View {
    let rota: RotaDeLancamento
    let demonstracao: Bool
    let rotaDoApp: RotaDoApp
    let textoCompartilhado: String?
    let conversa: Conversa?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(rota.titulo)
                        .font(.largeTitle.bold())

                    Text("rota efetiva: \(rota.id)")
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)

                    Text("rota recebida no app: \(rotaDoApp.rawValue)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let textoCompartilhado, !textoCompartilhado.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Texto recebido de outro app")
                                .font(.headline)
                            Text(textoCompartilhado)
                                .font(.body)
                        }
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }

                    if demonstracao, let conversa {
                        Text(conversa.titulo)
                            .font(.title3.bold())
                        ForEach(conversa.mensagensEmOrdem) { mensagem in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mensagem.papel == .usuario ? "Você" : "DSH")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Text(mensagem.conteudo)
                                    .font(.body)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Text("Nenhuma conversa carregada. Use -demonstracao 1 para ver os dados de captura.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("DSH")
        }
    }
}
