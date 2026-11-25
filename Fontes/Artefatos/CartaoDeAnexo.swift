import SwiftUI

/// Cartão do anexo: identifica o arquivo, mostra tipo, tamanho e o começo do texto
/// já extraído. No transcrito ele entra sem `aoRemover`, porque anexo já enviado não
/// sai da conversa; a ação de remover existe no cartão para quem ainda vai enviar.
struct CartaoDeAnexo: View {
    var anexo: Anexo
    var aoRemover: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: Espaco.s) {
            ZStack {
                RoundedRectangle(cornerRadius: Raio.s, style: .continuous)
                    .fill(Cores.acentoSuave)
                Image(systemName: simbolo)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Cores.acento)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(anexo.nome)
                    .font(Tipografia.legenda())
                    .foregroundStyle(Cores.texto)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(detalhe)
                    .font(Tipografia.legenda())
                    .foregroundStyle(Cores.textoFraco)
                    .lineLimit(1)

                if !previa.isEmpty {
                    Text(previa)
                        .font(Tipografia.legenda())
                        .foregroundStyle(Cores.textoFraco)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            if let aoRemover = aoRemover {
                Button(action: aoRemover) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Cores.textoFraco)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remover anexo")
            }
        }
        .padding(Espaco.m)
        .background(
            RoundedRectangle(cornerRadius: Raio.m, style: .continuous)
                .fill(Cores.superficie)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Raio.m, style: .continuous)
                .stroke(Cores.borda, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var simbolo: String {
        switch anexo.tipo {
        case .imagem:
            return "photo"
        case .pdf:
            return "doc.richtext"
        case .texto:
            return "text.alignleft"
        case .codigo:
            return "chevron.left.forwardslash.chevron.right"
        }
    }

    private var rotuloDoTipo: String {
        switch anexo.tipo {
        case .imagem:
            return "Imagem"
        case .pdf:
            return "PDF"
        case .texto:
            return "Texto"
        case .codigo:
            return "Código"
        }
    }

    private var detalhe: String {
        let tamanho = tamanhoLegivel
        return tamanho.isEmpty ? rotuloDoTipo : "\(rotuloDoTipo) • \(tamanho)"
    }

    private var tamanhoLegivel: String {
        guard anexo.tamanhoEmBytes > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(anexo.tamanhoEmBytes), countStyle: .file)
    }

    private var previa: String {
        let achado = anexo.texto
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard achado.count > 160 else { return achado }
        return String(achado.prefix(160)) + "..."
    }
}
