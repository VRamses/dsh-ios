import SwiftUI

/// Cartão do raciocínio: aberto enquanto a máquina pensa, recolhido quando a
/// resposta chega.
///
/// O indicador vivo é uma lâmpada de 7 pontos que pulsa em âmbar enquanto chega
/// fragmento de raciocínio, com o tempo decorrido ao lado. Ao terminar, o cartão
/// fecha sozinho e o cabeçalho passa a dizer quanto tempo levou, para o
/// transcrito não ficar com três parágrafos de rascunho no caminho da leitura.
/// Histórico salvo abre fechado e sem tempo, porque o tempo não foi gravado.
struct PensamentoRetratil: View {
    var raciocinio: String
    var estaAoVivo: Bool

    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento
    @State private var aberto = true
    @State private var inicio = Date()
    @State private var fim: Date?
    @State private var medindo = false
    @State private var pulsando = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { aberto.toggle() }
            } label: {
                cabecalho
            }
            .buttonStyle(.plain)
            .accessibilityLabel(aberto ? "Ocultar raciocínio" : "Mostrar raciocínio")
            .accessibilityHint("O raciocínio é o rascunho interno, não a resposta.")

            if aberto {
                Text(raciocinio.isEmpty ? "Ainda não há nada escrito." : raciocinio)
                    .font(Tipografia.corpo())
                    .foregroundStyle(Cores.textoFraco)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.horizontal, Espaco.l)
                    .padding(.top, Espaco.xs)
                    .padding(.bottom, Espaco.m)
            }
        }
        .background(Cores.superficie)
        .clipShape(RoundedRectangle(cornerRadius: Raio.g, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Raio.g, style: .continuous)
                .strokeBorder(Cores.borda.opacity(0.55), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            if estaAoVivo {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Cores.acento)
                    .frame(width: 2)
                    .padding(.vertical, Espaco.m)
                    .padding(.leading, 1)
            }
        }
        .onAppear {
            if estaAoVivo {
                inicio = Date()
                medindo = true
                aberto = true
            }
            pulsar()
        }
        .onChange(of: estaAoVivo) { _, vivo in
            if vivo {
                inicio = Date()
                fim = nil
                medindo = true
                aberto = true
                pulsar()
            } else {
                if medindo { fim = Date() }
                withAnimation(.easeInOut(duration: 0.22)) { aberto = false }
                pulsando = false
            }
        }
    }

    // MARK: - Cabeçalho

    private var cabecalho: some View {
        HStack(spacing: Espaco.s) {
            if estaAoVivo {
                Circle()
                    .fill(Cores.acento)
                    .frame(width: 7, height: 7)
                    .opacity(pulsando ? 0.25 : 1)
            }
            grupoDoRotulo
            Spacer(minLength: Espaco.s)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Cores.textoFraco)
                .rotationEffect(.degrees(aberto ? 90 : 0))
        }
        .padding(.horizontal, Espaco.l)
        .padding(.vertical, Espaco.m)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var grupoDoRotulo: some View {
        if estaAoVivo {
            TimelineView(.periodic(from: inicio, by: 1)) { contexto in
                Text(rotuloVivo(ate: contexto.date))
                    .font(Tipografia.legenda())
                    .fontWeight(.medium)
                    .foregroundStyle(Cores.textoFraco)
            }
        } else {
            Text(rotuloFinal)
                .font(Tipografia.legenda())
                .fontWeight(.medium)
                .foregroundStyle(Cores.textoFraco)
        }
    }

    private func rotuloVivo(ate agora: Date) -> String {
        let segundos = max(0, Int(agora.timeIntervalSince(inicio)))
        guard segundos >= 1 else { return "Pensando" }
        return "Pensando há \(duracao(segundos))"
    }

    private var rotuloFinal: String {
        guard let fim, medindo else { return "Raciocínio" }
        let segundos = max(0, Int(fim.timeIntervalSince(inicio)))
        guard segundos >= 1 else { return "Pensou rapidamente" }
        return "Pensou por \(duracao(segundos))"
    }

    private func duracao(_ segundos: Int) -> String {
        if segundos < 60 { return "\(segundos) s" }
        let minutos = segundos / 60
        let resto = segundos % 60
        if resto == 0 { return "\(minutos) min" }
        return "\(minutos) min \(resto) s"
    }

    private func pulsar() {
        guard estaAoVivo, !reduzirMovimento else {
            pulsando = false
            return
        }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            pulsando = true
        }
    }
}
