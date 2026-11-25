import SwiftUI

// Cores, Espaco, Raio e Tipografia vivem em Fontes/Desenho e são a fonte dos tokens.
// Escutar usa o acento do app e falar usa texto, o mesmo par de contraste do botão
// de enviar: o glifo é Cores.fundo, nunca branco fixo.
private enum PaletaDaVoz {
    static let escutando = Cores.acento
    static let pensando = Cores.acento
    static let falando = Cores.texto
    static let ocioso = Cores.textoFraco
}

private enum EstadoDaVoz: Equatable {
    case escutando
    case pensando
    case falando
    case ocioso
}

private func corPara(_ estado: EstadoDaVoz) -> Color {
    switch estado {
    case .escutando:
        return PaletaDaVoz.escutando
    case .pensando:
        return PaletaDaVoz.pensando
    case .falando:
        return PaletaDaVoz.falando
    case .ocioso:
        return PaletaDaVoz.ocioso
    }
}

// O nível do microfone já chega suavizado; aqui só se acrescenta o respiro dos
// estados que não têm áudio para reagir (pensando, falando, parado).
private func nivelDeDesenho(base: CGFloat, estado: EstadoDaVoz, pulso: CGFloat) -> CGFloat {
    switch estado {
    case .escutando:
        return min(max(base, 0), 1)
    case .falando:
        return 0.35 + 0.18 * pulso
    case .pensando:
        return 0.22 + 0.12 * pulso
    case .ocioso:
        return 0.06 + 0.04 * pulso
    }
}

private struct EsferaDaVoz: View {
    var nivel: CGFloat
    var pulso: CGFloat
    var cor: Color
    var estado: EstadoDaVoz
    var instante: Date

    var body: some View {
        Canvas { contexto, tamanho in
            let centro = CGPoint(x: tamanho.width / 2, y: tamanho.height / 2)
            let menor = min(tamanho.width, tamanho.height)

            for camada in 0..<4 {
                let indice = CGFloat(camada)
                let fracao = 0.18 + indice * 0.07
                let raio = menor * fracao * (1 + nivel * 0.28)
                    + menor * 0.015 * pulso * (1 - indice * 0.15)
                let caixa = CGRect(
                    x: centro.x - raio,
                    y: centro.y - raio,
                    width: raio * 2,
                    height: raio * 2
                )
                let opacidade = max(0.10, 0.62 - Double(indice) * 0.13 + Double(nivel) * 0.12)
                contexto.stroke(
                    Path(ellipseIn: caixa),
                    with: .color(cor.opacity(opacidade)),
                    lineWidth: 2.2 - indice * 0.35
                )
            }

            let raioNucleo = menor * (0.075 + nivel * 0.05)
            let nucleo = CGRect(
                x: centro.x - raioNucleo,
                y: centro.y - raioNucleo,
                width: raioNucleo * 2,
                height: raioNucleo * 2
            )
            contexto.fill(
                Path(ellipseIn: nucleo),
                with: .radialGradient(
                    Gradient(colors: [cor.opacity(0.95), cor.opacity(0.10)]),
                    center: centro,
                    startRadius: 0,
                    endRadius: raioNucleo
                )
            )

            // Ponto em órbita: o estado pensando precisa de movimento próprio,
            // porque não há áudio nenhum entrando nem saindo nesse momento.
            if estado == .pensando {
                let angulo = instante.timeIntervalSinceReferenceDate * 1.8
                let raioDaOrbita = menor * 0.44
                let ponto = CGPoint(
                    x: centro.x + CGFloat(cos(angulo)) * raioDaOrbita,
                    y: centro.y + CGFloat(sin(angulo)) * raioDaOrbita
                )
                contexto.fill(
                    Path(ellipseIn: CGRect(x: ponto.x - 6, y: ponto.y - 6, width: 12, height: 12)),
                    with: .color(cor.opacity(0.85))
                )
            }
        }
    }
}

struct TelaDeVoz: View {
    @ObservedObject var voz: GerenciadorDeVoz
    var pensando: Bool = false
    var enviar: (String) -> Void
    var fechar: () -> Void

    /// A preferência é a única entrada da decisão de escutar sozinha: ela mora no
    /// objeto compartilhado para não existir uma segunda cópia que possa divergir.
    @ObservedObject private var preferencias = Preferencias.compartilhada

    /// A primavera só existe como animação de view; a esfera usa para crescer
    /// ao som da voz sem que os anéis internos voltem ao tamanho antigo de repente.
    @State private var nivelDaPrimavera: CGFloat = 0
    @State private var mostrarErro = false
    @State private var mensagemDeErro = ""
    /// Uma vez por aparição: onAppear pode repetir sem a tela sair, e nesse caso
    /// a escuta não deve ser religada por cima de uma parada manual do usuário.
    @State private var iniciouSozinha = false

    private var estado: EstadoDaVoz {
        if voz.falando {
            return .falando
        }
        if pensando {
            return .pensando
        }
        if voz.transcrevendo {
            return .escutando
        }
        return .ocioso
    }

    private var corDoEstado: Color {
        corPara(estado)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [corDoEstado.opacity(0.16), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            VStack(spacing: Espaco.xl) {
                cabecalho
                Spacer(minLength: Espaco.s)
                esfera
                textos
                transcricao
                Spacer(minLength: Espaco.s)
                botaoDoMicrofone
            }
            .padding(.horizontal, Espaco.xl)
            .padding(.vertical, Espaco.l)
        }
        .onAppear {
            voz.aoConcluirFrase = { texto in
                enviar(texto)
            }
            iniciarSozinhaSePuder()
        }
        .onDisappear {
            voz.aoConcluirFrase = nil
            voz.parar()
            iniciouSozinha = false
        }
        .onChange(of: voz.nivelDeAudio) { _, novo in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) {
                nivelDaPrimavera = novo
            }
        }
        .alert("Não consegui abrir o microfone", isPresented: $mostrarErro) {
            Button("Ok", role: .cancel) {}
        } message: {
            Text(mensagemDeErro)
        }
    }

    private var cabecalho: some View {
        HStack {
            Text("Voz")
                .foregroundStyle(Cores.texto)
                .font(Tipografia.titulo(17))
            Spacer()
            Button {
                voz.calar()
                voz.parar()
                fechar()
            } label: {
                Image(systemName: "xmark")
                    .font(Tipografia.titulo(17))
                    .frame(width: 40, height: 40)
                    .background(Cores.superficieElevada, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fechar a tela de voz")
        }
    }

    private var esfera: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { contexto in
            let pulso = CGFloat(
                0.5 + 0.5 * sin(contexto.date.timeIntervalSinceReferenceDate * 2.2)
            )
            let nivel = nivelDeDesenho(
                base: voz.nivelDeAudio,
                estado: estado,
                pulso: pulso
            )
            EsferaDaVoz(
                nivel: nivel,
                pulso: pulso,
                cor: corDoEstado,
                estado: estado,
                instante: contexto.date
            )
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 300, maxHeight: 300)
            .scaleEffect(1 + nivelDaPrimavera * 0.08)
            .accessibilityHidden(true)
        }
    }

    private var textos: some View {
        VStack(spacing: Espaco.s) {
            HStack(spacing: Espaco.s) {
                if estado == .pensando {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(tituloDoEstado)
                    .foregroundStyle(Cores.texto)
                    .font(Tipografia.titulo())
                    .multilineTextAlignment(.center)
            }
            Text(detalheDoEstado)
                .font(Tipografia.corpo())
                .foregroundStyle(Cores.textoFraco)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var transcricao: some View {
        if !voz.textoParcial.isEmpty {
            Text(voz.textoParcial)
                .foregroundStyle(Cores.texto)
                .font(Tipografia.corpo())
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, Espaco.l)
                .padding(.vertical, Espaco.m)
                .frame(maxWidth: 420)
                .background(
                    RoundedRectangle(cornerRadius: Raio.l, style: .continuous)
                        .fill(Cores.superficie)
                        .overlay(
                            RoundedRectangle(cornerRadius: Raio.l, style: .continuous)
                                .strokeBorder(Cores.borda.opacity(0.55), lineWidth: 1)
                        )
                )
                .accessibilityLabel("Transcrição: \(voz.textoParcial)")
        }
    }

    private var botaoDoMicrofone: some View {
        Button(action: acaoDoMicrofone) {
            Image(systemName: iconeDoMicrofone)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Cores.fundo)
                .frame(width: 76, height: 76)
                .background(corDoBotao, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rotuloDoMicrofone)
        .accessibilityHint(dicaDoMicrofone)
    }

    private var tituloDoEstado: String {
        switch estado {
        case .escutando:
            return "Escutando"
        case .pensando:
            return "Pensando"
        case .falando:
            return "Falando"
        case .ocioso:
            return "Microfone desligado"
        }
    }

    private var detalheDoEstado: String {
        switch estado {
        case .escutando:
            return "Fale normalmente. Envio quando você fizer uma pausa."
        case .pensando:
            return "Já enviei o que você disse e estou esperando a resposta."
        case .falando:
            return "Toque no microfone para me interromper."
        case .ocioso:
            return "Toque no microfone para começar."
        }
    }

    private var iconeDoMicrofone: String {
        switch estado {
        case .falando:
            return "speaker.slash.fill"
        case .escutando:
            return "stop.fill"
        case .pensando, .ocioso:
            return "mic.fill"
        }
    }

    private var corDoBotao: Color {
        estado == .falando ? PaletaDaVoz.falando : PaletaDaVoz.escutando
    }

    private var rotuloDoMicrofone: String {
        switch estado {
        case .falando:
            return "Interromper a fala"
        case .escutando:
            return "Parar de escutar e enviar"
        case .pensando, .ocioso:
            return "Começar a escutar"
        }
    }

    private var dicaDoMicrofone: String {
        switch estado {
        case .falando:
            return "Cala a resposta na hora e volta a escutar."
        case .escutando:
            return "Encerra a escuta e envia a transcrição em tela."
        case .pensando, .ocioso:
            return "Liga o microfone e começa a transcrever em português."
        }
    }

    private func acaoDoMicrofone() {
        switch estado {
        case .falando:
            voz.calar()
        case .escutando:
            // Toque manual no botão significa "terminei": envia mesmo com menos de
            // três palavras, ao contrário da pausa automática.
            let texto = voz.textoParcial.trimmingCharacters(in: .whitespacesAndNewlines)
            voz.parar()
            voz.textoParcial = ""
            if !texto.isEmpty {
                enviar(texto)
            }
        case .pensando, .ocioso:
            tentarIniciar()
        }
    }

    private func tentarIniciar() {
        do {
            try voz.iniciar()
        } catch {
            mensagemDeErro = error.localizedDescription
            mostrarErro = true
        }
    }

    /// A preferência é a única entrada da decisão. O guarda de permissão existe
    /// porque iniciar() pede a autorização do sistema quando ela ainda não foi
    /// decidida, e a tela não deve abrir pedido de permissão sozinha: sem a
    /// permissão já concedida, fica o estado ocioso e o botão manual de sempre.
    private func iniciarSozinhaSePuder() {
        guard preferencias.vozAutomatica else { return }
        guard !iniciouSozinha else { return }
        guard !voz.transcrevendo else { return }
        guard voz.permissaoDeFalaConcedida else { return }
        // Marca antes de tentar: se o motor falhar, o alerta não volta a cada onAppear.
        iniciouSozinha = true
        tentarIniciar()
    }
}

#Preview {
    TelaDeVoz(voz: GerenciadorDeVoz(), enviar: { _ in }, fechar: {})
}
