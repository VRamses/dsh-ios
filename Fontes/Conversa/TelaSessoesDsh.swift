import SwiftUI

/// Folha das sessões abertas na ponte do DSH.
///
/// Não é um segundo app dentro do app: é uma lista para escolher em qual sessão
/// do computador esta conversa vai continuar. Mostra estado real (rodando,
/// vazia, turnos) e o tempo desde a última atualização, e cada linha diz o que
/// vai acontecer ao abrir. Sem ponte configurada, a tela diz o que falta em vez
/// de fingir lista vazia.
struct TelaSessoesDsh: View {
    @ObservedObject var modelo: ConversaViewModel
    var aoAbrir: @MainActor (SessaoResumo) -> Void

    @Environment(\.dismiss) private var fechar

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                botaoDeSessaoNova
                Group {
                    if modelo.carregandoSessoes && modelo.sessoes.isEmpty {
                        carregando
                    } else if let erro = modelo.erroDeSessoes, modelo.sessoes.isEmpty {
                        falha(erro)
                    } else if modelo.sessoes.isEmpty {
                        vazio
                    } else {
                        lista
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(Cores.fundo)
            .navigationTitle("Sessões do DSH")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fechar") { fechar() }
                        .tint(Cores.acento)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await modelo.carregarSessoes() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .tint(Cores.acento)
                    .accessibilityLabel("Atualizar sessões")
                }
            }
        }
        .task {
            await modelo.carregarSessoes()
        }
    }

    // MARK: - Estados

    /// Cria uma sessão nova no DSH. É o caminho que faltava: o app listava as
    /// sessões abertas no computador e não oferecia como começar uma do zero.
    private var botaoDeSessaoNova: some View {
        Button {
            Task {
                if let nova = await modelo.criarSessaoNoDsh() {
                    aoAbrir(nova)
                    fechar()
                }
            }
        } label: {
            HStack(spacing: Espaco.s) {
                if modelo.criandoSessao {
                    ProgressView()
                        .tint(Cores.fundo)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(modelo.criandoSessao ? "Criando sessão" : "Nova sessão no DSH")
                    .font(Tipografia.corpo())
            }
            .foregroundStyle(Cores.fundo)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Cores.acento)
            .clipShape(RoundedRectangle(cornerRadius: Raio.s, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(modelo.criandoSessao)
        .padding(.horizontal, Espaco.l)
        .padding(.top, Espaco.l)
        .accessibilityLabel("Criar sessão nova no DSH")
    }

    private var carregando: some View {
        VStack(spacing: Espaco.m) {
            ProgressView()
                .tint(Cores.acento)
            Text("Buscando sessões no computador")
                .font(Tipografia.legenda())
                .foregroundStyle(Cores.textoFraco)
        }
        .padding(Espaco.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Buscando sessões no computador")
    }

    private func falha(_ mensagem: String) -> some View {
        VStack(alignment: .leading, spacing: Espaco.m) {
            Text("Não deu para falar com a ponte")
                .font(Tipografia.titulo(19))
                .foregroundStyle(Cores.texto)
            Text(mensagem)
                .font(Tipografia.corpo())
                .foregroundStyle(Cores.textoFraco)
                .fixedSize(horizontal: false, vertical: true)
            Text("Confira o endereço e o token da ponte em Ajustes, e se o DSH está aberto no computador.")
                .font(Tipografia.legenda())
                .foregroundStyle(Cores.textoFraco)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await modelo.carregarSessoes() }
            } label: {
                Text("Tentar de novo")
                    .font(Tipografia.corpo())
                    .foregroundStyle(Cores.fundo)
                    .padding(.horizontal, Espaco.l)
                    .frame(height: 44)
                    .background(Cores.acento)
                    .clipShape(RoundedRectangle(cornerRadius: Raio.s, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tentar de novo")
        }
        .padding(Espaco.xl)
    }

    private var vazio: some View {
        VStack(alignment: .leading, spacing: Espaco.m) {
            Text("Nenhuma sessão aberta")
                .font(Tipografia.titulo(19))
                .foregroundStyle(Cores.texto)
            Text("Toque em Nova sessão no DSH para começar uma conversa por aqui, ou abra uma conversa no computador e ela aparece nesta lista para você continuar no iPhone.")
                .font(Tipografia.corpo())
                .foregroundStyle(Cores.textoFraco)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Espaco.xl)
    }

    // MARK: - Lista

    private var lista: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Espaco.s) {
                ForEach(modelo.sessoes, id: \.id) { sessao in
                    linha(de: sessao)
                }
            }
            .padding(Espaco.l)
        }
    }

    private func linha(de sessao: SessaoResumo) -> some View {
        Button {
            aoAbrir(sessao)
            fechar()
        } label: {
            HStack(alignment: .top, spacing: Espaco.m) {
                VStack(alignment: .leading, spacing: Espaco.xs) {
                    Text(sessao.titulo)
                        .font(Tipografia.corpo())
                        .foregroundStyle(Cores.texto)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: Espaco.s) {
                        if sessao.rodando {
                            Circle()
                                .fill(Cores.acento)
                                .frame(width: 6, height: 6)
                            Text("respondendo agora")
                                .font(Tipografia.legenda())
                                .foregroundStyle(Cores.textoFraco)
                        } else if let quando = quando(sessao.atualizadoEm) {
                            Text("atualizada \(quando)")
                                .font(Tipografia.legenda())
                                .foregroundStyle(Cores.textoFraco)
                        }
                        if sessao.vazia {
                            Text("vazia")
                                .font(Tipografia.legenda())
                                .foregroundStyle(Cores.textoFraco)
                        }
                    }
                    Text("\(sessao.turnos) turnos · \(sessao.curto)")
                        .font(Tipografia.codigo(11))
                        .foregroundStyle(Cores.textoFraco)
                        .lineLimit(1)
                }
                Spacer(minLength: Espaco.s)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Cores.textoFraco)
                    .padding(.top, Espaco.xs)
            }
            .padding(Espaco.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Cores.superficie)
            .clipShape(RoundedRectangle(cornerRadius: Raio.m, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Raio.m, style: .continuous)
                    .strokeBorder(Cores.borda.opacity(0.55), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(sessao.titulo), \(sessao.rodando ? "respondendo agora" : "\(sessao.turnos) turnos")")
        .accessibilityHint("Continua esta conversa na sessão do computador.")
    }

    private func quando(_ milissegundos: Double?) -> String? {
        guard let milissegundos, milissegundos > 0 else { return nil }
        // O campo vem em milissegundos desde 1970. Se vier pequeno demais para
        // ser milissegundo, é segundo: trata os dois sem inventar data.
        let segundos = milissegundos > 100_000_000_000 ? milissegundos / 1000 : milissegundos
        let data = Date(timeIntervalSince1970: segundos)
        let formato = RelativeDateTimeFormatter()
        formato.locale = Locale(identifier: "pt_BR")
        formato.unitsStyle = .short
        return formato.localizedString(for: data, relativeTo: Date())
    }
}
