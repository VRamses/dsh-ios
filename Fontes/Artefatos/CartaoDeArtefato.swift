import SwiftUI

/// Cartão da página gerada pelo modelo, abaixo do texto da resposta.
///
/// Ele é a única porta para a folha `TelaDeArtefato`: no transcrito o modelo
/// mostra o HTML como bloco de código, e sem este cartão o usuário não tem como
/// abrir a página pronta. O cartão inteiro é o botão, porque a linha do cartão é
/// alvo de toque maior que um botão pequeno no canto, e o VoiceOver recebe uma
/// ação só, com nome e dica próprios, em vez de ler quatro textos soltos.
struct CartaoDeArtefato: View {
    var artefato: Artefato
    var aoAbrir: () -> Void

    var body: some View {
        Button(action: aoAbrir) {
            HStack(spacing: Espaco.m) {
                ZStack {
                    RoundedRectangle(cornerRadius: Raio.s, style: .continuous)
                        .fill(Cores.acentoSuave)
                    Image(systemName: simbolo)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Cores.acento)
                }
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(artefato.titulo)
                        .font(Tipografia.titulo(17))
                        .foregroundStyle(Cores.texto)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(detalhe)
                        .font(Tipografia.legenda())
                        .foregroundStyle(Cores.textoFraco)
                        .lineLimit(1)
                }

                Spacer(minLength: Espaco.s)

                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Cores.textoFraco)
                    .accessibilityHidden(true)
            }
            .padding(Espaco.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Raio.m, style: .continuous)
                    .fill(Cores.superficieElevada)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Raio.m, style: .continuous)
                    .strokeBorder(Cores.borda.opacity(0.55), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Raio.m, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Abrir artefato: \(artefato.titulo)")
        .accessibilityHint("Abre a página pronta gerada pelo modelo.")
    }

    // MARK: - Rótulos

    private var simbolo: String {
        switch artefato.tipo {
        case .html: return "globe"
        case .svg: return "scribble.variable"
        case .grafico: return "chart.bar.xaxis"
        }
    }

    /// Tipo e linguagem no mesmo fio. A linguagem só entra quando acrescenta
    /// informação: em página HTML e desenho SVG ela é o próprio tipo, e mostrar
    /// "HTML • html" só gasta leitura; no gráfico ela diz a biblioteca usada
    /// (javascript, d3, canvas), que é o que interessa saber antes de abrir.
    private var detalhe: String {
        let tipo = rotuloDoTipo
        guard !artefato.linguagem.isEmpty,
              artefato.linguagem.lowercased() != tipo.lowercased() else { return tipo }
        return "\(tipo) • \(artefato.linguagem)"
    }

    private var rotuloDoTipo: String {
        switch artefato.tipo {
        case .html: return "HTML"
        case .svg: return "SVG"
        case .grafico: return "Gráfico"
        }
    }
}
