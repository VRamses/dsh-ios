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

    var body: some View {
        NavigationStack {
            Form {
                secaoDoMotor
                secaoDaDeepSeek
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
        .task { await lerCofre() }
    }

    // MARK: - 1. Motor

    private var secaoDoMotor: some View {
        Section {
            Picker("Motor", selection: $preferencias.usaPonte) {
                Text("Ponte do DSH").tag(true)
                Text("DeepSeek direto").tag(false)
            }
            .pickerStyle(.segmented)
            .tint(Cores.acento)
            .listRowBackground(Cores.superficie)
            .accessibilityLabel("Motor da conversa")
            .accessibilityHint("Escolhe entre a ponte do DSH no computador e a API da DeepSeek.")

            textoDeApoio("Pela ponte, a conversa usa as sessões do DSH no computador e ganha as ferramentas de MCP (Droz, Miro, Jira, Zendesk). No DeepSeek direto só existem as ferramentas locais: busca web, agenda e lembretes.")
        } header: {
            cabecalho("Motor")
        }
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

            textoDeApoio("A chave fica no Keychain deste iPhone e é lida na hora de cada pedido. O app não imprime a chave em log.")
        } header: {
            cabecalho("DeepSeek")
        }
    }

    // MARK: - 3. Ponte do DSH

    private var secaoDaPonte: some View {
        Section {
            textoDeApoio("O endereço é o do tailnet que publica a ponte, no formato https://maquina.tailnet.ts.net:8443. O token é o do ponte.json da máquina que roda a ponte.")

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
        } header: {
            cabecalho("Ponte do DSH")
        }
    }

    // MARK: - 4. Modelo

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

    // MARK: - 5. Busca web

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

    // MARK: - 6. Voz

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

            textoDeApoio("Nesta versão a tela de voz ainda não lê esta preferência: o valor fica salvo aqui para quando ela ler. O microfone e a transcrição já funcionam pela tela de voz.")
        } header: {
            cabecalho("Voz")
        }
    }

    // MARK: - 7. Sobre

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

    private func linhaDeBotoes(
        salvar: String,
        apagar: String,
        apagarHabilitado: Bool,
        aoSalvar: @escaping @MainActor () -> Void,
        aoApagar: @escaping @MainActor () -> Void
    ) -> some View {
        HStack(spacing: Espaco.s) {
            Button(action: { aoSalvar() }) {
                Text(salvar)
                    .font(Tipografia.rotulo())
                    .foregroundStyle(Cores.texto)
                    .padding(.horizontal, Espaco.m)
                    .frame(minHeight: 44)
                    .background(Cores.superficieElevada)
                    .clipShape(RoundedRectangle(cornerRadius: Raio.s, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(salvar) no cofre")

            Button(action: { aoApagar() }) {
                Text(apagar)
                    .font(Tipografia.rotulo())
                    .foregroundStyle(Cores.perigo)
                    .padding(.horizontal, Espaco.m)
                    .frame(minHeight: 44)
                    .background(Cores.superficieElevada)
                    .clipShape(RoundedRectangle(cornerRadius: Raio.s, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!apagarHabilitado)
            .opacity(apagarHabilitado ? 1 : 0.4)
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
