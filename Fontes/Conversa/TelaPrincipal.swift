import SwiftUI
import SwiftData
import Combine

/// A tela da conversa. É a única tela do app: transcrito no meio, gaveta de
/// conversas à esquerda, barra de entrada flutuante no pé.
///
/// O que ela monta: `@Query` traz as conversas salvas, a mensagem do usuário vai
/// para o SwiftData na hora e a resposta é escrita ao vivo pelo
/// `ConversaViewModel` enquanto os fragmentos chegam. O seletor de modelo e o
/// caminho da ponte vêm de `Preferencias`, lidas no `onAppear` porque essa
/// leitura é de tela, não de rede.
struct TelaPrincipal: View {
    @Environment(\.modelContext) private var contexto
    @Query(sort: \Conversa.atualizadaEm, order: .reverse) private var conversas: [Conversa]
    @StateObject private var modelo = ConversaViewModel()

    @State private var conversaAtual: Conversa?
    @State private var novaConversaPendente = false
    @State private var menuAberto = false
    @State private var sessoesAbertas = false
    @State private var rascunho = ""
    @State private var anexos: [Anexo] = []
    @State private var modeloEscolhido = "deepseek-chat"
    @State private var usandoPonte = false
    @State private var sessaoEscolhida: String?
    @State private var tituloDaSessao: String?
    @State private var configurou = false

    let conversaInicial: Conversa?
    let servicoPonte: ServicoPonte?

    init(conversaInicial: Conversa? = nil, servicoPonte: ServicoPonte? = nil) {
        self.conversaInicial = conversaInicial
        self.servicoPonte = servicoPonte
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .leading) {
                Cores.fundo.ignoresSafeArea()
                transcrito
                if menuAberto {
                    camadaDoMenu
                }
            }
            .navigationTitle(tituloDaConversa)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Cores.fundo, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { barraDeNavegacao }
            .safeAreaInset(edge: .bottom) { barraDeEntrada }
            .environment(\.locale, Locale(identifier: "pt_BR"))
            .sheet(isPresented: $sessoesAbertas) {
                TelaSessoesDsh(modelo: modelo, aoAbrir: abrirSessao)
                    .environment(\.locale, Locale(identifier: "pt_BR"))
            }
            .task { await configurar() }
        }
    }

    // MARK: - Transcrito

    private var transcrito: some View {
        ScrollViewReader { rolagem in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Espaco.xl) {
                    if mensagens.isEmpty && !modelo.estaRespondendo {
                        estadoVazio
                    }
                    ForEach(mensagens) { mensagem in
                        BolhaDeMensagem(mensagem: mensagem)
                            .id(mensagem.id)
                    }
                    if modelo.estaRespondendo {
                        BolhaDeMensagem(
                            papel: .assistente,
                            texto: modelo.textoAoVivo,
                            raciocinio: modelo.raciocinioAoVivo,
                            estaAoVivo: true
                        )
                        .id("aoVivo")
                    }
                    if let erro = modelo.erro {
                        faixaDeErro(erro)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("fim")
                }
                .padding(.horizontal, Espaco.l)
                .padding(.top, Espaco.l)
                .padding(.bottom, Espaco.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { rolar(rolagem, animado: false) }
            .onChange(of: modelo.textoAoVivo) { _, _ in rolar(rolagem) }
            .onChange(of: modelo.estaRespondendo) { _, _ in rolar(rolagem) }
            .onReceive(modelo.$conversa) { atual in
                // Quando o modelo cria a conversa nova, a tela para de fingir
                // uma conversa vazia e passa a mostrar a que acabou de nascer.
                if let atual, novaConversaPendente {
                    novaConversaPendente = false
                    conversaAtual = atual
                }
            }
        }
    }

    private var estadoVazio: some View {
        VStack(alignment: .leading, spacing: Espaco.m) {
            Text("Conversa nova")
                .font(Tipografia.titulo(22))
                .foregroundStyle(Cores.texto)
            Text("Escreva abaixo. A resposta vem da DeepSeek ou da sessão do DSH que você escolher no seletor de modelo, e fica guardada neste iPhone.")
                .font(Tipografia.corpo())
                .foregroundStyle(Cores.textoFraco)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Espaco.xl)
        .padding(.bottom, Espaco.l)
    }

    private func faixaDeErro(_ mensagem: String) -> some View {
        VStack(alignment: .leading, spacing: Espaco.s) {
            HStack(spacing: Espaco.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Cores.perigo)
                Text("Não deu para responder")
                    .font(Tipografia.legenda())
                    .fontWeight(.semibold)
                    .foregroundStyle(Cores.texto)
            }
            Text(mensagem)
                .font(Tipografia.legenda())
                .foregroundStyle(Cores.textoFraco)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                modelo.limparErro()
            } label: {
                Text("Entendi")
                    .font(Tipografia.legenda())
                    .fontWeight(.semibold)
                    .foregroundStyle(Cores.texto)
                    .padding(.horizontal, Espaco.m)
                    .frame(height: 32)
                    .background(Cores.superficieElevada)
                    .clipShape(RoundedRectangle(cornerRadius: Raio.s, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Entendi, fechar aviso de erro")
        }
        .padding(Espaco.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Cores.superficie)
        .clipShape(RoundedRectangle(cornerRadius: Raio.m, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Raio.m, style: .continuous)
                .strokeBorder(Cores.perigo.opacity(0.45), lineWidth: 1)
        )
    }

    // MARK: - Navegação e barra

    @ToolbarContentBuilder
    private var barraDeNavegacao: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { menuAberto = true }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 15, weight: .semibold))
            }
            .tint(Cores.texto)
            .accessibilityLabel("Abrir conversas")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                novaConversa()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .semibold))
            }
            .tint(Cores.texto)
            .accessibilityLabel("Nova conversa")
        }
    }

    private var barraDeEntrada: some View {
        BarraDeEntrada(
            texto: $rascunho,
            anexos: $anexos,
            estaRespondendo: modelo.estaRespondendo,
            modeloAtual: modeloEscolhido,
            sessaoAtual: usandoPonte ? (tituloDaSessao ?? "sessão do DSH") : nil,
            aoEnviar: enviar,
            aoParar: { modelo.cancelar() },
            aoEscolherModelo: escolherModelo,
            aoEscolherSessao: abrirSessoes
        )
        .padding(.horizontal, Espaco.l)
        .padding(.bottom, Espaco.s)
    }

    // MARK: - Gaveta

    private var camadaDoMenu: some View {
        ZStack(alignment: .leading) {
            Button {
                fecharMenu()
            } label: {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fechar conversas")

            MenuLateral(
                conversas: conversas,
                selecionada: conversaEfetiva?.id,
                aoSelecionar: selecionar,
                aoNova: novaConversa,
                aoFixar: fixar,
                aoApagar: apagar,
                aoAbrirSessoes: abrirSessoes,
                aoFechar: fecharMenu
            )
            .frame(width: 320)
            .frame(maxHeight: .infinity)
            .background(Cores.superficie)
            .transition(.move(edge: .leading))
        }
        .transition(.opacity)
    }

    // MARK: - Dados derivados

    private var conversaEfetiva: Conversa? {
        if novaConversaPendente { return nil }
        return conversaAtual ?? conversas.first
    }

    private var mensagens: [Mensagem] {
        (conversaEfetiva?.mensagens ?? []).sorted { $0.criadaEm < $1.criadaEm }
    }

    private var tituloDaConversa: String {
        let titulo = conversaEfetiva?.titulo ?? ""
        return titulo.isEmpty ? "Conversa" : titulo
    }

    // MARK: - Ações

    @MainActor
    private func configurar() async {
        let preferencias = Preferencias.compartilhada
        if !configurou {
            conversaAtual = conversaInicial
            modeloEscolhido = preferencias.modelo
            // A ponte só vale com uma sessão escolhida nesta execução: guardar
            // só o "usa ponte" faria a tela prometer um caminho que não existe.
            usandoPonte = false
            configurou = true
        }
        modelo.preparar(conversa: conversaEfetiva, contexto: contexto, ponte: servicoPonte)
        modelo.definirSessao(sessaoEscolhida)
        modelo.configurar(
            modelo: modeloEscolhido,
            temperatura: preferencias.temperatura,
            maxTokens: preferencias.maxTokens,
            usaPonte: usandoPonte && sessaoEscolhida != nil
        )
    }

    @MainActor
    private func enviar() {
        let conteudo = rascunho
        let anexosDoEnvio = anexos
        guard !conteudo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !anexosDoEnvio.isEmpty else {
            return
        }
        rascunho = ""
        anexos = []
        let alvo = novaConversaPendente ? nil : conversaEfetiva
        modelo.preparar(conversa: alvo, contexto: contexto, ponte: servicoPonte)
        modelo.enviar(conteudo, anexos: anexosDoEnvio)
    }

    @MainActor
    private func escolherModelo(_ pedido: String) {
        modeloEscolhido = pedido
        usandoPonte = false
        sessaoEscolhida = nil
        tituloDaSessao = nil
        let preferencias = Preferencias.compartilhada
        preferencias.modelo = pedido
        preferencias.usaPonte = false
        modelo.definirSessao(nil)
        modelo.configurar(
            modelo: pedido,
            temperatura: preferencias.temperatura,
            maxTokens: preferencias.maxTokens,
            usaPonte: false
        )
    }

    @MainActor
    private func abrirSessao(_ sessao: SessaoResumo) {
        sessaoEscolhida = sessao.id
        tituloDaSessao = sessao.titulo
        usandoPonte = true
        novaConversaPendente = false
        let preferencias = Preferencias.compartilhada
        preferencias.usaPonte = true
        if let nova = modelo.criarConversa(comTitulo: sessao.titulo) {
            conversaAtual = nova
        }
        modelo.definirSessao(sessao.id)
        modelo.configurar(
            modelo: modeloEscolhido,
            temperatura: preferencias.temperatura,
            maxTokens: preferencias.maxTokens,
            usaPonte: true
        )
    }

    @MainActor
    private func selecionar(_ conversa: Conversa) {
        novaConversaPendente = false
        conversaAtual = conversa
        modelo.abrir(conversa)
        fecharMenu()
    }

    @MainActor
    private func novaConversa() {
        conversaAtual = nil
        novaConversaPendente = true
        modelo.abrir(nil)
        rascunho = ""
        anexos = []
        fecharMenu()
    }

    @MainActor
    private func fixar(_ conversa: Conversa) {
        conversa.fixada.toggle()
        try? contexto.save()
    }

    @MainActor
    private func apagar(_ conversa: Conversa) {
        if conversaEfetiva?.id == conversa.id {
            conversaAtual = nil
            novaConversaPendente = true
            modelo.abrir(nil)
        }
        contexto.delete(conversa)
        try? contexto.save()
    }

    @MainActor
    private func abrirSessoes() {
        fecharMenu()
        sessoesAbertas = true
    }

    @MainActor
    private func fecharMenu() {
        withAnimation(.easeOut(duration: 0.2)) { menuAberto = false }
    }

    @MainActor
    private func rolar(_ rolagem: ScrollViewProxy, animado: Bool = true) {
        if animado {
            withAnimation(.easeOut(duration: 0.25)) {
                rolagem.scrollTo("fim", anchor: .bottom)
            }
        } else {
            rolagem.scrollTo("fim", anchor: .bottom)
        }
    }
}
