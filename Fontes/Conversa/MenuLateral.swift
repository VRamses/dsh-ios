import SwiftUI

/// Gaveta de conversas: busca no topo, fixadas primeiro, recentes depois e a
/// porta para as sessões do DSH no pé.
///
/// Não é uma tela de navegação com abas: é uma gaveta que cobre a conversa e
/// fecha com um toque fora. Cada linha tem data relativa e um menu com fixar e
/// apagar, e apagar pede confirmação porque não tem desfazer.
struct MenuLateral: View {
    var conversas: [Conversa]
    var selecionada: UUID?
    var aoSelecionar: @MainActor (Conversa) -> Void
    var aoNova: @MainActor () -> Void
    var aoFixar: @MainActor (Conversa) -> Void
    var aoApagar: @MainActor (Conversa) -> Void
    var aoAbrirSessoes: @MainActor () -> Void
    var aoAbrirAjustes: @MainActor () -> Void
    var aoFechar: @MainActor () -> Void

    @State private var busca = ""
    @State private var confirmando = false
    @State private var paraApagar: Conversa?

    private var filtradas: [Conversa] {
        let termo = busca.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !termo.isEmpty else { return conversas }
        return conversas.filter { $0.titulo.localizedCaseInsensitiveContains(termo) }
    }

    private var fixadas: [Conversa] {
        filtradas.filter { $0.fixada }
    }

    private var recentes: [Conversa] {
        filtradas.filter { !$0.fixada }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Espaco.l) {
            cabecalho
            campoDeBusca
            botaoDeNovaConversa
            rolagemDeConversas
            Divider()
            botaoDeAjustes
            botaoDeSessoes
        }
        .padding(Espaco.l)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Cores.superficie)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Conversas")
        .confirmationDialog(
            "Apagar esta conversa?",
            isPresented: $confirmando,
            presenting: paraApagar
        ) { conversa in
            Button("Apagar", role: .destructive) { aoApagar(conversa) }
            Button("Manter", role: .cancel) { paraApagar = nil }
        } message: { conversa in
            Text("As mensagens de \(conversa.titulo.isEmpty ? "sem título" : conversa.titulo) saem do iPhone e não voltam.")
        }
    }

    // MARK: - Partes

    private var cabecalho: some View {
        HStack(spacing: Espaco.s) {
            Text("Conversas")
                .font(Tipografia.titulo(22))
                .foregroundStyle(Cores.texto)
            Spacer(minLength: Espaco.s)
            Button(action: { aoFechar() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Cores.textoFraco)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fechar conversas")
        }
        .padding(.trailing, -Espaco.m)
    }

    private var campoDeBusca: some View {
        HStack(spacing: Espaco.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Cores.textoFraco)
            TextField("Buscar conversa", text: $busca)
                .font(Tipografia.corpo())
                .foregroundStyle(Cores.texto)
                .tint(Cores.acento)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel("Buscar conversa")
        }
        .padding(.horizontal, Espaco.m)
        .frame(height: 44)
        .background(Cores.superficieElevada)
        .clipShape(RoundedRectangle(cornerRadius: Raio.s, style: .continuous))
    }

    private var botaoDeNovaConversa: some View {
        Button(action: { aoNova() }) {
            HStack(spacing: Espaco.s) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14, weight: .semibold))
                Text("Nova conversa")
                    .font(Tipografia.corpo())
                Spacer(minLength: 0)
            }
            .foregroundStyle(Cores.texto)
            .padding(.horizontal, Espaco.m)
            .frame(height: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Cores.superficieElevada)
            .clipShape(RoundedRectangle(cornerRadius: Raio.s, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Nova conversa")
    }

    private var rolagemDeConversas: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Espaco.s) {
                if filtradas.isEmpty {
                    textoVazio
                } else {
                    if !fixadas.isEmpty {
                        secao("Fixadas")
                        ForEach(fixadas) { conversa in
                            linha(de: conversa)
                        }
                    }
                    if !recentes.isEmpty {
                        secao("Recentes")
                        ForEach(recentes) { conversa in
                            linha(de: conversa)
                        }
                    }
                }
            }
            .padding(.bottom, Espaco.s)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var textoVazio: some View {
        Text(conversas.isEmpty
             ? "Nenhuma conversa ainda. A primeira que você começar aparece aqui."
             : "Nenhuma conversa com esse termo.")
            .font(Tipografia.legenda())
            .foregroundStyle(Cores.textoFraco)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, Espaco.m)
    }

    private func secao(_ titulo: String) -> some View {
        Text(titulo)
            .font(Tipografia.rotulo())
            .foregroundStyle(Cores.textoFraco)
            .padding(.top, Espaco.s)
    }

    private func linha(de conversa: Conversa) -> some View {
        Button {
            aoSelecionar(conversa)
        } label: {
            HStack(alignment: .center, spacing: Espaco.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversa.titulo.isEmpty ? "Sem título" : conversa.titulo)
                        .font(Tipografia.corpo())
                        .foregroundStyle(Cores.texto)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(quando(conversa.atualizadaEm))
                        .font(Tipografia.legenda())
                        .foregroundStyle(Cores.textoFraco)
                }
                Spacer(minLength: Espaco.s)
                if conversa.fixada {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Cores.textoFraco)
                }
            }
            .padding(.horizontal, Espaco.m)
            .padding(.vertical, Espaco.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(conversa.id == selecionada ? Cores.acentoSuave : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Raio.s, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(conversa.titulo.isEmpty ? "Sem título" : conversa.titulo), \(quando(conversa.atualizadaEm))")
        .accessibilityAddTraits(conversa.id == selecionada ? .isSelected : [])
        .contextMenu {
            Button {
                aoFixar(conversa)
            } label: {
                Label(conversa.fixada ? "Desafixar" : "Fixar", systemImage: conversa.fixada ? "pin.slash" : "pin")
            }
            Button(role: .destructive) {
                paraApagar = conversa
                confirmando = true
            } label: {
                Label("Apagar", systemImage: "trash")
            }
        }
    }

    private var botaoDeAjustes: some View {
        Button(action: { aoAbrirAjustes() }) {
            HStack(spacing: Espaco.s) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Cores.textoFraco)
                Text("Ajustes")
                    .font(Tipografia.corpo())
                    .foregroundStyle(Cores.texto)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Cores.textoFraco)
            }
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ajustes")
        .accessibilityHint("Abre as chaves da DeepSeek, o endereço e o token da ponte.")
    }

    private var botaoDeSessoes: some View {
        Button(action: { aoAbrirSessoes() }) {
            HStack(spacing: Espaco.s) {
                Image(systemName: "server.rack")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Cores.textoFraco)
                Text("Sessões do DSH")
                    .font(Tipografia.corpo())
                    .foregroundStyle(Cores.texto)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Cores.textoFraco)
            }
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sessões do DSH")
        .accessibilityHint("Abre a lista de sessões abertas no computador.")
        .padding(.bottom, Espaco.s)
    }

    private func quando(_ data: Date) -> String {
        let formato = RelativeDateTimeFormatter()
        formato.locale = Locale(identifier: "pt_BR")
        formato.unitsStyle = .short
        return formato.localizedString(for: data, relativeTo: Date())
    }
}
