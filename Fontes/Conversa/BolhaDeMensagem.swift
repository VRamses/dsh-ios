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

    /// O detector de artefato varre a resposta inteira e o `body` de uma resposta
    /// ao vivo é reavaliado a cada fragmento do streaming; o cache dentro da
    /// bolha guarda o último texto detectado para a varredura não se repetir em
    /// reavaliações causadas por outro motivo. A folha aberta fica aqui porque o
    /// cartão é o único ponto que conhece o artefato.
    @State private var cacheDeArtefatos = CacheDeArtefatos()
    @State private var artefatoAberto: Artefato?

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
                if !artefatosDetectados.isEmpty {
                    VStack(alignment: .leading, spacing: Espaco.s) {
                        ForEach(artefatosDetectados) { artefato in
                            CartaoDeArtefato(artefato: artefato) {
                                artefatoAberto = artefato
                            }
                        }
                    }
                }
                if estaAoVivo && (raciocinio ?? "").isEmpty {
                    trabalhoEmCurso
                }
            }
            if !anexos.isEmpty {
                rotulosDosAnexos
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $artefatoAberto) { artefato in
            TelaDeArtefato(artefato: artefato)
        }
    }

    /// Artefatos da resposta, na ordem em que o modelo os escreveu. A leitura
    /// passa pelo cache, que só roda o detector quando o texto muda de verdade e
    /// nunca em texto vazio.
    private var artefatosDetectados: [Artefato] {
        cacheDeArtefatos.artefatos(de: texto)
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

/// Cache da bolha para o detector de artefato.
///
/// O `body` de uma resposta ao vivo é reavaliado a cada fragmento que chega, e o
/// detector varre a resposta inteira; sem o cache, toda reavaliação por outro
/// motivo (rolagem, mudança da lista, seleção) varreria o mesmo texto de novo.
/// O texto vazio nem chega ao detector. A instância vive no `@State` da bolha:
/// sendo classe, a mutação é por referência e não é escrita de estado, então o
/// cache não agenda um segundo desenho para o cartão aparecer.
private final class CacheDeArtefatos {
    private var textoDetectado: String?
    private var guardados: [Artefato] = []

    func artefatos(de texto: String) -> [Artefato] {
        if let anterior = textoDetectado, anterior == texto { return guardados }
        textoDetectado = texto
        guard !texto.isEmpty else {
            guardados = []
            return []
        }
        guardados = DetectorDeArtefato.detectar(em: texto)
        return guardados
    }
}
