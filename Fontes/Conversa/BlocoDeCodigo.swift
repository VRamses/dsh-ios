import SwiftUI
import UIKit

/// Bloco de código da resposta: linguagem declarada no topo, botão de copiar à
/// direita e rolagem horizontal para a linha não quebrar.
///
/// O corpo fica em fonte monoespaçada do sistema, no menor papel da tipografia,
/// e o cartão usa a superfície elevada para separar do texto corrido. O botão
/// mede 44 pontos de alvo e diz o resultado em voz alta para o VoiceOver.
struct BlocoDeCodigo: View {
    var linguagem: String
    var codigo: String

    @State private var copiado = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Espaco.s) {
                Text(linguagem.isEmpty ? "código" : linguagem.lowercased())
                    .font(Tipografia.codigo(12))
                    .foregroundStyle(Cores.textoFraco)
                    .lineLimit(1)
                Spacer(minLength: Espaco.s)
                Button(action: { copiar() }) {
                    Image(systemName: copiado ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(copiado ? Cores.sucesso : Cores.textoFraco)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(copiado ? "Código copiado" : "Copiar código")
                .accessibilityHint("Copia o bloco inteiro para a área de transferência.")
            }
            .padding(.leading, Espaco.m)
            .padding(.trailing, Espaco.xs)
            .padding(.top, Espaco.xs)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(codigo)
                    .font(Tipografia.codigo(13))
                    .foregroundStyle(Cores.texto)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .padding(.horizontal, Espaco.m)
                    .padding(.top, Espaco.xs)
                    .padding(.bottom, Espaco.m)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Cores.superficieElevada)
        .clipShape(RoundedRectangle(cornerRadius: Raio.m, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Raio.m, style: .continuous)
                .strokeBorder(Cores.borda.opacity(0.55), lineWidth: 1)
        )
    }

    @MainActor
    private func copiar() {
        UIPasteboard.general.string = codigo
        withAnimation(.easeInOut(duration: 0.18)) { copiado = true }
        UIAccessibility.post(notification: .announcement, argument: "Código copiado")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.easeInOut(duration: 0.18)) { copiado = false }
        }
    }
}
