import Foundation
import SwiftUI
import UIKit

/// A tela de Ajustes: onde o app deixa de ser uma casca e ganha chave.
///
/// Tudo o que ela grava sai daqui para dois lugares, e só para eles: o cofre
/// (Keychain, serviço `dev.ramses.dsh.cofre`) guarda as três chaves secretas, e
/// `Preferencias` guarda o que não é segredo (motor, endereço da ponte, modelo,
/// temperatura, teto de tokens e voz automática). Nenhuma chave é escrita em
/// log, `print` ou `UserDefaults`.
///
/// A tela é uma `Form` de propósito: os controles nativos já vêm com alvo de
/// toque de 44 pontos, teclado certo e suporte ao Texto Dinâmico, e o
/// `scrollContentBackground(.hidden)` com `Cores.fundo` por baixo mantém a
/// paleta do app em vez do cinza padrão do sistema.
struct TelaDeAjustes: View {
    @Environment(\.dismiss) private var fechar
    @ObservedObject private var preferencias = Preferencias.compartilhada
    @ObservedObject private var instancias = Instancias.compartilhada

    // Só o que está sendo digitado fica aqui. O valor já salvo nunca volta para
    // a tela: dela saem os 4 últimos caracteres, o suficiente para reconhecer
    // qual chave está no cofre sem desenhá-la inteira.
    @State private var chaveDeepSeek = ""
    @State private var chaveDaBusca = ""
    @State private var tokenDaPonte = ""
    @State private var finalDaChaveDeepSeek: String?
    @State private var finalDaChaveDaBusca: String?
    @State private var finalDoToken: String?
    @State private var avisoDeepSeek: String?
    @State private var avisoDaBusca: String?
    @State private var avisoDaPonte: String?
    @State private var testando = false
    @State private var resultadoDoTeste: ResultadoDoTeste?
    @State private var importando = false
    @State private var resultadoDaImportacao: ResultadoDoTeste?
    @State private var testandoDeepSeek = false
    @State private var diagnosticoDeepSeek: String?
    @State private var pareando = false
    @State private var lendoQR = false
    @State private var instanciaAEesquecer: InstanciaDoDsh?

    /// Nomes das chaves como estão no cofre do DSH na máquina da ponte. A
    /// DeepSeek é a única que existe hoje; as de busca entram aqui porque o
    /// custo de pedir a mais é zero e a resposta já diz quais faltaram.
    private static let nomesParaImportar = ["DEEPSEEK_API_KEY", "TAVILY_API_KEY", "BRAVE_API_KEY"]

    var body: some View {
        NavigationStack {
            Form {
                secaoDoMotor
                secaoDaDeepSeek
                secaoDosComputadores
                secaoDaPonte
                secaoDoModelo
                secaoDaBusca
                secaoDaVoz
                secaoSobre
            }
            .scrollContentBackground(.hidden)
            .background(Cores.fundo)
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        fechar()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Cores.texto)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Fechar ajustes")
                }
            }
        }
        .environment(\.locale, Locale(identifier: "pt_BR"))
        .sheet(isPresented: $lendoQR) {
            FolhaDeLeituraDeQR(
                aoLer: { texto in aceitarLeitura(texto) },
                aoFechar: { lendoQR = false }
            )
        }
        .confirmationDialog(
            "Esquecer \(instanciaAEesquecer?.rotulo ?? "este computador")?",
            isPresented: Binding(
                get: { instanciaAEesquecer != nil },
                set: { if !$0 { instanciaAEesquecer = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Esquecer", role: .destructive) {
                guard let instancia = instanciaAEesquecer else { return }
                instanciaAEesquecer = nil
                instancias.remover(instancia.id)
                finalDoToken = finalDe(ChaveDoCofre.tokenDaPonte)
                resultadoDoTeste = nil
                avisoDaPonte = "Esqueci \(instancia.rotulo). O endereço e o token dele saíram deste iPhone."
            }
            Button("Cancelar", role: .cancel) {
                instanciaAEesquecer = nil
            }
        } message: {
            Text("O endereço sai da lista e o token sai do cofre. Para voltar, é preciso parear de novo.")
        }
        .task {
            await lerCofre()
            instancias.sincronizarComPreferencias(
                endereco: preferencias.enderecoDaPonte,
                temToken: finalDoToken != nil
            )
            await aplicarPareamento()
        }
    }

    // MARK: - 1. Motor

    private var secaoDoMotor: some View {
        Section {
            linhaDoMotorEmUso

            Picker("Motor", selection: $preferencias.usaPonte) {
                Text("Ponte do DSH").tag(true)
                Text("DeepSeek direto").tag(false)
            }
            .pickerStyle(.segmented)
            .tint(Cores.acento)
            .listRowBackground(Cores.superficie)
            .accessibilityLabel("Motor da conversa")
            .accessibilityHint("Escolhe entre a ponte do DSH no computador e a API da DeepSeek.")

            textoDeApoio("Pela ponte, a conversa roda nas sessões do DSH no computador e ganha as ferramentas de MCP dele (Droz, Miro, Jira, Zendesk). No DeepSeek direto só existem as ferramentas locais: busca web, agenda e lembretes.")
        } header: {
            cabecalho("Motor")
        }
    }

    // MARK: - Estado do motor

    /// O motor de verdade é o seletor mais a sessão aberta em Sessões do DSH: a
    /// ponte só responde com sessão, e sem ela o app cai calado na DeepSeek
    /// direta. Como o seletor sozinho não muda nada visível, esta linha diz qual
    /// dos dois está respondendo agora e, quando falta a sessão, leva até ela.
    private var linhaDoMotorEmUso: some View {
        HStack(alignment: .top, spacing: Espaco.s) {
            Image(systemName: iconeDoMotor)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(corDoMotor)
                .frame(minHeight: 44, alignment: .center)
            VStack(alignment: .leading, spacing: Espaco.xs) {
                Text(textoDoMotor)
                    .font(Tipografia.legenda())
                    .foregroundStyle(Cores.texto)
                    .fixedSize(horizontal: false, vertical: true)
                if pendenteDeSessao {
                    Button {
                        pedirSessoes()
                    } label: {
                        Text("Abrir Sessões do DSH")
                            .font(Tipografia.legenda())
                            .foregroundStyle(Cores.acento)
                            .frame(minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Abrir as sessões do DSH para escolher uma")
                    .accessibilityHint("Fecha Ajustes e abre a lista de sessões do computador.")
                }
            }
            Spacer(minLength: 0)
        }
        .listRowBackground(Cores.superficie)
        .accessibilityElement(children: .contain)
    }

    /// A ponte está marcada mas não há sessão aberta nesta execução, que é o
    /// caso em que o app responde pela DeepSeek direta sem avisar.
    private var pendenteDeSessao: Bool {
        preferencias.usaPonte && (preferencias.sessaoAbertaAgora ?? "").isEmpty
    }

    private var textoDoMotor: String {
        if !preferencias.usaPonte {
            return "Respondendo pela DeepSeek direta, com a chave deste iPhone."
        }
        if pendenteDeSessao {
            return "Ponte marcada, nenhuma sessão aberta: a conversa responde pela DeepSeek direta até você escolher uma sessão."
        }
        let titulo = preferencias.tituloDaSessaoDaPonte
        return titulo.isEmpty
            ? "Respondendo pela ponte do DSH, na sessão aberta agora."
            : "Respondendo pela ponte do DSH, na sessão \(titulo)."
    }

    private var iconeDoMotor: String {
        if !preferencias.usaPonte { return "bolt.horizontal.circle" }
        return pendenteDeSessao ? "exclamationmark.circle" : "antenna.radiowaves.left.and.right"
    }

    private var corDoMotor: Color {
        if pendenteDeSessao { return Cores.acento }
        return preferencias.usaPonte ? Cores.sucesso : Cores.textoFraco
    }

    @MainActor
    private func pedirSessoes() {
        PendenciaDeTela.abrirSessoes = true
        fechar()
    }

    // MARK: - 2. DeepSeek

    private var secaoDaDeepSeek: some View {
        Section {
            if let finalDaChaveDeepSeek {
                textoDeApoio("Chave salva no cofre, terminando em \(finalDaChaveDeepSeek).")
            } else {
                textoDeApoio("Nenhuma chave salva. Sem ela, o motor DeepSeek direto não responde.")
            }

            SecureField("Cole a chave da DeepSeek", text: $chaveDeepSeek)
                .font(Tipografia.codigo(13))
                .foregroundStyle(Cores.texto)
                .tint(Cores.acento)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)
                .privacySensitive()
                .listRowBackground(Cores.superficie)
                .accessibilityLabel("Chave da API da DeepSeek")

            linhaDeBotoes(
                salvar: "Salvar chave",
                apagar: "Apagar chave",
                apagarHabilitado: finalDaChaveDeepSeek != nil,
                aoSalvar: salvarChaveDeepSeek,
                aoApagar: apagarChaveDeepSeek
            )

            if let avisoDeepSeek {
                linhaDeAviso(avisoDeepSeek)
            }

            Button {
                Task { await testarChaveDeepSeek() }
            } label: {
                HStack(spacing: Espaco.s) {
                    Image(systemName: "bolt.horizontal.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Cores.acento)
                    Text(testandoDeepSeek ? "Testando a chave..." : "Testar a chave")
                        .font(Tipografia.corpo())
                        .foregroundStyle(Cores.texto)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(testandoDeepSeek)
            .listRowBackground(Cores.superficie)
            .accessibilityLabel("Testar a chave da DeepSeek")
            .accessibilityHint("Faz um pedido curto à API da DeepSeek e mostra o código HTTP e o começo da resposta.")

            if let diagnosticoDeepSeek {
                textoDeApoio(diagnosticoDeepSeek)
            }

            textoDeApoio("A chave fica no Keychain deste iPhone e é lida na hora de cada pedido. O app não imprime a chave em log.")
        } header: {
            cabecalho("DeepSeek")
        }
    }

    // MARK: - 3. Computadores

    /// A lista de computadores conhecidos, com o que está em uso marcado.
    ///
    /// Parear não sobrescreve mais nada: cada leitura de QR acrescenta um
    /// computador (ou atualiza o que já tinha o mesmo endereço) e o token de
    /// cada um fica numa conta própria do cofre. Tocar numa linha troca o
    /// computador em uso e testa a conexão na hora, para a troca não ser uma
    /// promessa silenciosa.
    private var secaoDosComputadores: some View {
        Section {
            if instancias.lista.isEmpty {
                textoDeApoio("Nenhum computador salvo ainda. Ler o QR do computador é o caminho mais curto.")
            } else {
                ForEach(instancias.lista) { instancia in
                    linhaDoComputador(instancia)
                }
            }

            Button {
                lendoQR = true
            } label: {
                HStack(spacing: Espaco.s) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Cores.acento)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pareando ? "Pareando..." : "Adicionar pela câmera")
                            .font(Tipografia.corpo())
                            .foregroundStyle(Cores.texto)
                        Text("Lê o QR de pareamento e põe o computador em uso.")
                            .font(Tipografia.legenda())
                            .foregroundStyle(Cores.textoFraco)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(pareando)
            .listRowBackground(Cores.superficie)
            .accessibilityLabel("Adicionar computador pela câmera")
            .accessibilityHint("Abre a câmera para ler o QR que o DSH do computador mostra em Ajustes.")
        } header: {
            cabecalho("Computadores")
        }
    }

    @ViewBuilder
    private func linhaDoComputador(_ instancia: InstanciaDoDsh) -> some View {
        let ativo = instancias.ativa == instancia.id
        let temToken = instancias.token(de: instancia.id) != nil

        Button {
            guard !ativo else { return }
            instancias.ativar(instancia.id)
            finalDoToken = finalDe(ChaveDoCofre.tokenDaPonte)
            resultadoDoTeste = nil
            avisoDaPonte = "Agora o app fala com \(instancia.rotulo)."
            Task { await testarPonte() }
        } label: {
            HStack(alignment: .top, spacing: Espaco.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(instancia.rotulo)
                        .font(Tipografia.corpo())
                        .foregroundStyle(Cores.texto)
                    Text(instancia.endereco)
                        .font(Tipografia.legenda())
                        .foregroundStyle(Cores.textoFraco)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !temToken {
                        Text("Sem token: pareie de novo para usar este computador.")
                            .font(Tipografia.legenda())
                            .foregroundStyle(Cores.perigo)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if ativo {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Cores.acento)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Cores.superficie)
        .accessibilityLabel("\(instancia.rotulo), \(instancia.endereco)\(ativo ? ", em uso" : "")")
        .accessibilityHint(ativo ? "Já é o computador em uso." : "Põe este computador em uso.")
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                instanciaAEesquecer = instancia
            } label: {
                Text("Esquecer")
            }
        }
    }

    // MARK: - 4. Ponte do DSH

    private var secaoDaPonte: some View {
        Section {
            textoDeApoio("O endereço é o do tailnet que publica a ponte, no formato https://maquina.tailnet.ts.net:8443, e o token é o do ponte.json da máquina que roda a ponte.")

            TextField("https://maquina.tailnet.ts.net:8443", text: $preferencias.enderecoDaPonte)
                .font(Tipografia.codigo(13))
                .foregroundStyle(Cores.texto)
                .tint(Cores.acento)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .listRowBackground(Cores.superficie)
                .accessibilityLabel("Endereço da ponte")
                .accessibilityHint("Endereço https da ponte do DSH no computador.")

            if let finalDoToken {
                textoDeApoio("Token salvo no cofre, terminando em \(finalDoToken).")
            } else {
                textoDeApoio("Nenhum token salvo. A ponte responde 401 sem ele.")
            }

            SecureField("Cole o token da ponte", text: $tokenDaPonte)
                .font(Tipografia.codigo(13))
                .foregroundStyle(Cores.texto)
                .tint(Cores.acento)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)
                .privacySensitive()
                .listRowBackground(Cores.superficie)
                .accessibilityLabel("Token da ponte")

            linhaDeBotoes(
                salvar: "Salvar token",
                apagar: "Apagar token",
                apagarHabilitado: finalDoToken != nil,
                aoSalvar: salvarTokenDaPonte,
                aoApagar: apagarTokenDaPonte
            )

            if let avisoDaPonte {
                linhaDeAviso(avisoDaPonte)
            }

            Button {
                Task { await testarPonte() }
            } label: {
                HStack(spacing: Espaco.s) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Cores.acento)
                    Text(testando ? "Testando..." : "Testar conexão")
                        .font(Tipografia.corpo())
                        .foregroundStyle(Cores.texto)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(testando)
            .listRowBackground(Cores.superficie)
            .accessibilityLabel("Testar conexão com a ponte")
            .accessibilityHint("Faz um pedido de saúde na ponte usando o endereço acima e o token salvo.")

            if let resultadoDoTeste {
                linhaDoResultado(resultadoDoTeste)
            }

            textoDeApoio("O teste usa o endereço acima e o token salvo no cofre. Salve o token antes de testar.")

            Button {
                Task { await importarChavesDoComputador() }
            } label: {
                HStack(spacing: Espaco.s) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Cores.acento)
                    Text(importando ? "Importando..." : "Importar chaves do computador")
                        .font(Tipografia.corpo())
                        .foregroundStyle(Cores.texto)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(importando)
            .listRowBackground(Cores.superficie)
            .accessibilityLabel("Importar chaves do computador")
            .accessibilityHint("Pede à ponte as chaves que já estão no cofre do DSH e grava as que existirem no cofre deste iPhone.")

            if let resultadoDaImportacao {
                linhaDoResultado(resultadoDaImportacao)
            }

            textoDeApoio("A importação usa o endereço e o token acima, e só funciona com a ponte ligada no computador. Ela traz a chave da DeepSeek e, se houver, a de busca web, direto para o Keychain deste iPhone.")
        } header: {
            cabecalho("Ponte do DSH")
        }
    }

    // MARK: - 5. Modelo

    private var secaoDoModelo: some View {
        Section {
            Picker("Modelo", selection: $preferencias.modelo) {
                Text("deepseek-chat").tag("deepseek-chat")
                Text("deepseek-reasoner").tag("deepseek-reasoner")
            }
            .pickerStyle(.segmented)
            .tint(Cores.acento)
            .listRowBackground(Cores.superficie)
            .accessibilityLabel("Modelo da DeepSeek")

            textoDeApoio("O deepseek-reasoner pensa antes de responder, é mais lento e ignora temperatura e ferramentas.")

            Stepper(value: $preferencias.temperatura, in: 0...2, step: 0.1) {
                HStack(spacing: Espaco.s) {
                    Text("Temperatura")
                        .font(Tipografia.corpo())
                        .foregroundStyle(Cores.texto)
                    Spacer(minLength: 0)
                    Text(String(format: "%.1f", preferencias.temperatura))
                        .font(Tipografia.codigo(13))
                        .foregroundStyle(Cores.textoFraco)
                }
            }
            .tint(Cores.acento)
            .listRowBackground(Cores.superficie)
            .accessibilityLabel("Temperatura")
            .accessibilityValue(String(format: "%.1f", preferencias.temperatura))

            Stepper(value: $preferencias.maxTokens, in: 256...8192, step: 256) {
                HStack(spacing: Espaco.s) {
                    Text("Teto de tokens")
                        .font(Tipografia.corpo())
                        .foregroundStyle(Cores.texto)
                    Spacer(minLength: 0)
                    Text("\(preferencias.maxTokens)")
                        .font(Tipografia.codigo(13))
                        .foregroundStyle(Cores.textoFraco)
                }
            }
            .tint(Cores.acento)
            .listRowBackground(Cores.superficie)
            .accessibilityLabel("Teto de tokens da resposta")
            .accessibilityValue("\(preferencias.maxTokens) tokens")

            textoDeApoio("Temperatura alta deixa a resposta mais solta, baixa deixa mais previsível. O teto de tokens limita só o tamanho da resposta.")
        } header: {
            cabecalho("Modelo")
        }
    }

    // MARK: - 6. Busca web

    private var secaoDaBusca: some View {
        Section {
            textoDeApoio("A ferramenta de busca do assistente usa a Tavily (chaves começam com tvly-) ou a Brave. Sem esta chave, a busca responde pedindo a chave em Ajustes.")

            if let finalDaChaveDaBusca {
                textoDeApoio("Chave salva no cofre, terminando em \(finalDaChaveDaBusca).")
            }

            SecureField("Cole a chave da Tavily ou da Brave", text: $chaveDaBusca)
                .font(Tipografia.codigo(13))
                .foregroundStyle(Cores.texto)
                .tint(Cores.acento)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)
                .privacySensitive()
                .listRowBackground(Cores.superficie)
                .accessibilityLabel("Chave de busca web")

            linhaDeBotoes(
                salvar: "Salvar chave",
                apagar: "Apagar chave",
                apagarHabilitado: finalDaChaveDaBusca != nil,
                aoSalvar: salvarChaveDaBusca,
                aoApagar: apagarChaveDaBusca
            )

            if let avisoDaBusca {
                linhaDeAviso(avisoDaBusca)
            }

            textoDeApoio("A chave é lida a cada busca, então salvar aqui já vale para a próxima pergunta.")
        } header: {
            cabecalho("Busca web")
        }
    }

    // MARK: - 7. Voz

    private var secaoDaVoz: some View {
        Section {
            Toggle(isOn: $preferencias.vozAutomatica) {
                Text("Abrir a voz automaticamente")
                    .font(Tipografia.corpo())
                    .foregroundStyle(Cores.texto)
            }
            .tint(Cores.acento)
            .listRowBackground(Cores.superficie)
            .accessibilityLabel("Abrir a voz automaticamente")
            .accessibilityHint("Guarda a preferência de entrar no modo de voz ao abrir uma conversa nova.")

            textoDeApoio("Ligado, a tela de voz começa a ouvir assim que abre, desde que a permissão de fala já esteja concedida. Desligado, o microfone só liga no toque. O padrão é desligado, para o microfone nunca abrir sem você pedir.")
        } header: {
            cabecalho("Voz")
        }
    }

    // MARK: - 8. Sobre

    private var secaoSobre: some View {
        Section {
            HStack(spacing: Espaco.s) {
                Text("DSH")
                    .font(Tipografia.corpo())
                    .foregroundStyle(Cores.texto)
                Spacer(minLength: 0)
                Text(versaoDoApp)
                    .font(Tipografia.codigo(13))
                    .foregroundStyle(Cores.textoFraco)
            }
            .frame(minHeight: 44)
            .listRowBackground(Cores.superficie)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("DSH, versão \(versaoDoApp)")

            textoDeApoio("Na conta gratuita da Apple não existe App Group: o widget e o compartilhamento de outro app ficam limitados por isso e podem não aparecer. Não há promessa de App Store nem de notificação: este é um app assinado para uso próprio.")
        } header: {
            cabecalho("Sobre")
        }
    }

    // MARK: - Leitura e escrita do cofre

    @MainActor
    private func lerCofre() async {
        finalDaChaveDeepSeek = finalDe(ChaveDoCofre.apiKeyDeepSeek)
        finalDaChaveDaBusca = finalDe(ChaveDoCofre.chaveBuscaWeb)
        finalDoToken = finalDe(ChaveDoCofre.tokenDaPonte)
    }

    private func finalDe(_ chave: String) -> String? {
        guard let valor = try? CofreDeChaves.ler(chave), !valor.isEmpty else { return nil }
        return String(valor.suffix(4))
    }

    @MainActor
    private func salvarChaveDeepSeek() {
        let limpo = chaveDeepSeek.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpo.isEmpty else {
            avisoDeepSeek = "Cole a chave antes de salvar."
            return
        }
        guard limpo.hasPrefix("sk-") else {
            avisoDeepSeek = "A chave da DeepSeek começa com sk-. Confira antes de salvar."
            return
        }
        do {
            try CofreDeChaves.guardar(limpo, para: ChaveDoCofre.apiKeyDeepSeek)
            chaveDeepSeek = ""
            finalDaChaveDeepSeek = String(limpo.suffix(4))
            avisoDeepSeek = "Chave da DeepSeek salva no cofre deste iPhone."
        } catch {
            avisoDeepSeek = error.localizedDescription
        }
    }

    @MainActor
    private func apagarChaveDeepSeek() {
        do {
            try CofreDeChaves.apagar(ChaveDoCofre.apiKeyDeepSeek)
            finalDaChaveDeepSeek = nil
            avisoDeepSeek = "Chave da DeepSeek apagada do cofre."
        } catch {
            avisoDeepSeek = error.localizedDescription
        }
    }

    @MainActor
    private func salvarTokenDaPonte() {
        let limpo = tokenDaPonte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpo.isEmpty else {
            avisoDaPonte = "Cole o token antes de salvar."
            return
        }
        do {
            try CofreDeChaves.guardar(limpo, para: ChaveDoCofre.tokenDaPonte)
            instancias.tokenDaAtivaMudou(limpo)
            tokenDaPonte = ""
            finalDoToken = String(limpo.suffix(4))
            avisoDaPonte = "Token da ponte salvo no cofre deste iPhone."
        } catch {
            avisoDaPonte = error.localizedDescription
        }
    }

    @MainActor
    private func apagarTokenDaPonte() {
        do {
            try CofreDeChaves.apagar(ChaveDoCofre.tokenDaPonte)
            instancias.tokenDaAtivaMudou(nil)
            finalDoToken = nil
            resultadoDoTeste = nil
            avisoDaPonte = "Token da ponte apagado do cofre."
        } catch {
            avisoDaPonte = error.localizedDescription
        }
    }

    @MainActor
    private func salvarChaveDaBusca() {
        let limpo = chaveDaBusca.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpo.isEmpty else {
            avisoDaBusca = "Cole a chave antes de salvar."
            return
        }
        do {
            try CofreDeChaves.guardar(limpo, para: ChaveDoCofre.chaveBuscaWeb)
            chaveDaBusca = ""
            finalDaChaveDaBusca = String(limpo.suffix(4))
            avisoDaBusca = "Chave de busca salva no cofre deste iPhone."
        } catch {
            avisoDaBusca = error.localizedDescription
        }
    }

    @MainActor
    private func apagarChaveDaBusca() {
        do {
            try CofreDeChaves.apagar(ChaveDoCofre.chaveBuscaWeb)
            finalDaChaveDaBusca = nil
            avisoDaBusca = "Chave de busca apagada do cofre."
        } catch {
            avisoDaBusca = error.localizedDescription
        }
    }

    // MARK: - Teste da chave da DeepSeek

    /// Pedido de dezesseis tokens, sem streaming: mostra o código HTTP e o
    /// começo do corpo. É o que separa chave errada (401), modelo errado (400)
    /// e telefone sem rede quando a conversa não responde.
    @MainActor
    private func testarChaveDeepSeek() async {
        testandoDeepSeek = true
        diagnosticoDeepSeek = nil
        defer { testandoDeepSeek = false }

        let chave = (try? CofreDeChaves.ler(ChaveDoCofre.apiKeyDeepSeek)) ?? nil
        diagnosticoDeepSeek = await ServicoDeepSeek.diagnosticar(
            chave: chave ?? "",
            modelo: preferencias.modelo
        )
    }

    // MARK: - Pareamento por QR

    /// Texto que veio da câmera do próprio app. Devolve `false` quando o QR não
    /// é de pareamento, e aí a folha continua aberta e recomeça a câmera, em vez
    /// de fechar sem explicar nada.
    @MainActor
    private func aceitarLeitura(_ texto: String) -> Bool {
        PendenciaDePareamento.recolher(de: texto)
        guard PendenciaDePareamento.atual != nil else { return false }
        lendoQR = false
        Task { await aplicarPareamento() }
        return true
    }

    /// Aplica o pedido que chegou num QR: grava o endereço, troca o código de
    /// uso único pelo token, guarda o token no cofre e liga o motor da ponte. O
    /// token nunca viajou no QR e não aparece na tela.
    @MainActor
    private func aplicarPareamento() async {
        guard let pedido = PendenciaDePareamento.atual else { return }
        PendenciaDePareamento.atual = nil

        pareando = true
        avisoDaPonte = nil
        resultadoDoTeste = nil
        defer { pareando = false }

        do {
            let trocado = try await ServicoPonte.trocarCodigo(pedido.codigo, endereco: pedido.endereco)
            try CofreDeChaves.guardar(trocado.token, para: ChaveDoCofre.tokenDaPonte)
            finalDoToken = String(trocado.token.suffix(4))
            preferencias.usaPonte = true
            // O computador entra na lista com o nome que ele mesmo informou: a
            // ponte devolve o rótulo e o nome da máquina, e é isso que a lista
            // mostra em vez de um endereço cru.
            let nome = trocado.maquina ?? trocado.rotulo
            let instancia = try instancias.registrarPareamento(
                endereco: pedido.endereco,
                nome: nome,
                token: trocado.token
            )
            avisoDaPonte = "Pareado com \(instancia.rotulo): token salvo no cofre e motor da ponte ligado."
            await testarPonte()
        } catch {
            avisoDaPonte = "Não consegui trocar o código do QR: \(error.localizedDescription)"
        }
    }

    // MARK: - Teste da ponte

    /// O teste é o `saude()` do `ServicoPonte`, que já existe: GET `/v1/saude`
    /// com o Bearer e devolve `ok`, versão, rótulo, máquina e o detalhe do DSH.
    /// Não há endpoint novo aqui, e nenhuma chave vai para o log: só o texto do
    /// resultado aparece na linha abaixo do botão.
    @MainActor
    private func testarPonte() async {
        testando = true
        resultadoDoTeste = nil
        defer { testando = false }

        guard let ponte = ServicoPonte.aPartirDasPreferencias() else {
            resultadoDoTeste = .falha("Salve o token da ponte antes de testar.")
            return
        }

        do {
            let saude = try await ponte.saude()
            if saude.ok {
                var partes: [String] = []
                if let rotulo = saude.rotulo, !rotulo.isEmpty { partes.append(rotulo) }
                if let maquina = saude.maquina, !maquina.isEmpty { partes.append(maquina) }
                if let versao = saude.versao, !versao.isEmpty { partes.append("versão \(versao)") }
                let detalhe = partes.isEmpty ? "A ponte respondeu e o DSH está pronto." : "Ponte pronta: " + partes.joined(separator: ", ") + "."
                resultadoDoTeste = .sucesso(detalhe)
            } else {
                resultadoDoTeste = .falha(saude.detalhe ?? "A ponte respondeu que o DSH não está pronto.")
            }
        } catch {
            resultadoDoTeste = .falha(error.localizedDescription)
        }
    }

    // MARK: - Importação das chaves

    /// Copia para o cofre deste iPhone o que já está no cofre do computador.
    ///
    /// A ordem importa: só grava depois de a ponte responder, e grava chave por
    /// chave, para uma falha no meio não deixar a tela dizendo que importou o
    /// que não importou. A mensagem final diz o que entrou e o que faltou no
    /// computador, sem nunca imprimir o valor de nenhuma chave.
    @MainActor
    private func importarChavesDoComputador() async {
        importando = true
        resultadoDaImportacao = nil
        defer { importando = false }

        guard let ponte = ServicoPonte.aPartirDasPreferencias() else {
            resultadoDaImportacao = .falha("Salve o endereço e o token da ponte antes de importar.")
            return
        }

        do {
            let resposta = try await ponte.importarChaves(nomes: Self.nomesParaImportar)
            var entraram: [String] = []

            if let valor = resposta.chaves["DEEPSEEK_API_KEY"] {
                try CofreDeChaves.guardar(valor, para: ChaveDoCofre.apiKeyDeepSeek)
                finalDaChaveDeepSeek = String(valor.suffix(4))
                avisoDeepSeek = "Chave da DeepSeek importada do computador."
                entraram.append("DeepSeek")
            }

            if let valor = resposta.chaves["TAVILY_API_KEY"] ?? resposta.chaves["BRAVE_API_KEY"] {
                try CofreDeChaves.guardar(valor, para: ChaveDoCofre.chaveBuscaWeb)
                finalDaChaveDaBusca = String(valor.suffix(4))
                avisoDaBusca = "Chave de busca importada do computador."
                entraram.append("busca web")
            }

            if entraram.isEmpty {
                resultadoDaImportacao = .falha("O computador não tem nenhuma dessas chaves no cofre.")
            } else {
                var texto = "Importado do computador: " + entraram.joined(separator: " e ") + "."
                if !resposta.faltando.isEmpty {
                    texto += " Ficou de fora: " + resposta.faltando.joined(separator: ", ") + "."
                }
                resultadoDaImportacao = .sucesso(texto)
            }
        } catch {
            resultadoDaImportacao = .falha(error.localizedDescription)
        }
    }

    // MARK: - Peças

    private var versaoDoApp: String {
        let info = Bundle.main.infoDictionary
        let curta = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(curta) (\(build))"
    }

    private func cabecalho(_ titulo: String) -> some View {
        Text(titulo)
            .font(Tipografia.rotulo())
            .foregroundStyle(Cores.textoFraco)
            .textCase(nil)
    }

    private func textoDeApoio(_ texto: String) -> some View {
        Text(texto)
            .font(Tipografia.legenda())
            .foregroundStyle(Cores.textoFraco)
            .fixedSize(horizontal: false, vertical: true)
            .listRowBackground(Cores.superficie)
    }

    private func linhaDeAviso(_ texto: String) -> some View {
        HStack(alignment: .top, spacing: Espaco.xs) {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Cores.textoFraco)
            Text(texto)
                .font(Tipografia.legenda())
                .foregroundStyle(Cores.textoFraco)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Cores.superficie)
        .accessibilityElement(children: .combine)
    }

    /// Os dois verbos do cofre, como ação de linha e não como botão cheio.
    ///
    /// A primeira versão desenhava pílula com `Cores.superficieElevada` por
    /// dentro, e no tema claro ela é branca: a pílula sumia dentro do cartão
    /// branco e sobrava texto solto no meio do nada. Texto tingido é o que o
    /// iOS usa para ação de linha em ajustes ("Redefinir", "Apagar"), e o
    /// contraste do acento (5,9:1) e do perigo (6,0:1) no claro segue acima de
    /// AA. A altura de 44 pontos e o `contentShape` mantêm o alvo de toque.
    private func linhaDeBotoes(
        salvar: String,
        apagar: String,
        apagarHabilitado: Bool,
        aoSalvar: @escaping @MainActor () -> Void,
        aoApagar: @escaping @MainActor () -> Void
    ) -> some View {
        HStack(spacing: Espaco.xl) {
            Button(action: { aoSalvar() }) {
                Text(salvar)
                    .font(Tipografia.corpo())
                    .foregroundStyle(Cores.acento)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(salvar) no cofre")

            Button(action: { aoApagar() }) {
                Text(apagar)
                    .font(Tipografia.corpo())
                    .foregroundStyle(Cores.perigo)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!apagarHabilitado)
            .opacity(apagarHabilitado ? 1 : 0.45)
            .accessibilityLabel("\(apagar) do cofre")

            Spacer(minLength: 0)
        }
        .listRowBackground(Cores.superficie)
    }

    private func linhaDoResultado(_ resultado: ResultadoDoTeste) -> some View {
        HStack(alignment: .top, spacing: Espaco.xs) {
            Image(systemName: resultado.icone)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(resultado.cor)
            Text(resultado.texto)
                .font(Tipografia.legenda())
                .foregroundStyle(resultado.cor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Cores.superficie)
        .accessibilityElement(children: .combine)
    }
}

private enum ResultadoDoTeste {
    case sucesso(String)
    case falha(String)

    var texto: String {
        switch self {
        case .sucesso(let texto): return texto
        case .falha(let texto): return texto
        }
    }

    var cor: Color {
        switch self {
        case .sucesso: return Cores.sucesso
        case .falha: return Cores.perigo
        }
    }

    var icone: String {
        switch self {
        case .sucesso: return "checkmark.circle"
        case .falha: return "exclamationmark.triangle"
        }
    }
}

/// A câmera do pareamento, aberta de dentro de Ajustes.
///
/// A tela é preta porque a prévia da câmera é o conteúdo: moldura branca fina
/// para o QR entrar, uma frase dizendo o que apontar e um botão de fechar. O
/// resto do app fica de fora enquanto ela está aberta.
private struct FolhaDeLeituraDeQR: View {
    /// Recebe o texto lido e devolve `true` quando ele serviu. Quando devolve
    /// `false`, a folha mostra o motivo e recomeça a câmera.
    var aoLer: (String) -> Bool
    var aoFechar: () -> Void

    @State private var erro: String?
    @State private var tentativa = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if LeitorDeQR.disponivel {
                LeitorDeQR(
                    aoLer: { texto in
                        if aoLer(texto) {
                            aoFechar()
                        } else {
                            erro = "Esse QR não é de pareamento do DSH. Use o que o DSH do computador mostra em Ajustes."
                            tentativa += 1
                        }
                    },
                    aoFalhar: { motivo in erro = motivo }
                )
                // Cada tentativa é um leitor novo: depois da primeira leitura a
                // câmera para, e trocar o `id` é o que a liga de novo.
                .id(tentativa)
                .ignoresSafeArea()
            }

            VStack(spacing: Espaco.xl) {
                cabecalho
                Spacer(minLength: 0)
                if LeitorDeQR.disponivel {
                    moldura
                }
                Spacer(minLength: 0)
                if let erro {
                    HStack(alignment: .top, spacing: Espaco.xs) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 12, weight: .semibold))
                        Text(erro)
                            .font(Tipografia.legenda())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(.white)
                    .padding(Espaco.m)
                    .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: Raio.m, style: .continuous))
                } else {
                    Text("Aponte para o QR que o DSH do computador mostra em Ajustes.")
                        .font(Tipografia.legenda())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(Espaco.m)
                        .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: Raio.m, style: .continuous))
                }
            }
            .padding(Espaco.l)
        }
        .preferredColorScheme(.dark)
    }

    private var cabecalho: some View {
        HStack(spacing: Espaco.s) {
            Text("Ler QR do computador")
                .font(Tipografia.titulo(20))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            Button(action: { aoFechar() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.5), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fechar o leitor de QR")
        }
    }

    /// Só a moldura, sem mira animada nem escurecimento em volta: o QR precisa
    /// aparecer inteiro, e a câmera já escurece o que está fora do foco.
    private var moldura: some View {
        RoundedRectangle(cornerRadius: Raio.g, style: .continuous)
            .stroke(Color.white.opacity(0.85), lineWidth: 2)
            .frame(width: 232, height: 232)
            .accessibilityHidden(true)
    }
}
