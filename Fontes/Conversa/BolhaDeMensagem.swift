import SwiftUI

/// Um turno do transcrito.
///
/// A fala do usuário fica na margem direita, num cartão de acento suave: é o que
/// ele escreveu, e o app não precisa emoldurar a própria resposta do mesmo jeito.
/// A resposta do assistente ocupa a largura da página, sem balão, com o
/// raciocínio retrátil em cima e o texto em markdown embaixo. Sistema vira uma
/// linha central discreta.
struct BolhaDeMensagem: View {
    var papel: Papel
    var texto: String
    var raciocinio: String?
    var anexos: [Anexo]
    var estaAoVivo: Bool

    init(
        papel: Papel,
        texto: String,
        raciocinio: String? = nil,
        anexos: [Anexo] = [],
        estaAoVivo: Bool = false
    ) {
        self.papel = papel
        self.texto = texto
        self.raciocinio = raciocinio
        self.anexos = anexos
        self.estaAoVivo = estaAoVivo
    }

    init(mensagem: Mensagem) {
        self.papel = mensagem.papel
        self.texto = mensagem.conteudo
        self.raciocinio = mensagem.raciocinio
        self.anexos = mensagem.anexos
        self.estaAoVivo = false
    }

    var body: some View {
        switch papel {
        case .usuario: falaDoUsuario
        case .assistente: respostaDoAssistente
        case .sistema: avisoDoSistema
        }
    }

    // MARK: - Usuário

    private var falaDoUsuario: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: Espaco.xxl)
            VStack(alignment: .leading, spacing: Espaco.s) {
                if !anexos.isEmpty {
                    rotulosDosAnexos
                }
                if !texto.isEmpty {
                    TextoRico(texto)
                        .foregroundStyle(Cores.texto)
                }
            }
            .padding(.horizontal, Espaco.l)
            .padding(.vertical, Espaco.m)
            .background(Cores.acentoSuave)
            .clipShape(RoundedRectangle(cornerRadius: Raio.l, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Você escreveu")
        }
    }

    // MARK: - Assistente

    private var respostaDoAssistente: some View {
        VStack(alignment: .leading, spacing: Espaco.m) {
            if let raciocinio, !raciocinio.isEmpty || estaAoVivo {
                PensamentoRetratil(raciocinio: raciocinio, estaAoVivo: estaAoVivo)
            }
            if texto.isEmpty {
                if estaAoVivo { trabalhoEmCurso }
            } else {
                TextoRico(texto)
                    .foregroundStyle(Cores.texto)
                if estaAoVivo && (raciocinio ?? "").isEmpty {
                    trabalhoEmCurso
                }
            }
            if !anexos.isEmpty {
                rotulosDosAnexos
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Só aparece quando não há raciocínio a mostra: sem ele, o cartão do
    /// pensamento já é o indicador de que a máquina está trabalhando.
    private var trabalhoEmCurso: some View {
        HStack(spacing: Espaco.s) {
            ProgressView()
                .controlSize(.small)
                .tint(Cores.acento)
            Text("Escrevendo")
                .font(Tipografia.legenda())
                .foregroundStyle(Cores.textoFraco)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("O assistente está escrevendo")
    }

    // MARK: - Sistema

    private var avisoDoSistema: some View {
        Text(texto)
            .font(Tipografia.legenda())
            .foregroundStyle(Cores.textoFraco)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Espaco.s)
    }

    // MARK: - Anexos

    private var rotulosDosAnexos: some View {
        VStack(alignment: .leading, spacing: Espaco.xs) {
            ForEach(anexos) { anexo in
                HStack(spacing: Espaco.xs) {
                    Image(systemName: icone(de: anexo.tipo))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Cores.textoFraco)
                        .frame(width: 16)
                    Text(anexo.nome)
                        .font(Tipografia.legenda())
                        .foregroundStyle(Cores.textoFraco)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Anexo \(anexo.nome)")
            }
        }
    }

    private func icone(de tipo: Anexo.Tipo) -> String {
        switch tipo {
        case .imagem: return "photo"
        case .pdf: return "doc.richtext"
        case .texto: return "doc.text"
        case .codigo: return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }
}
