import SwiftUI
import UIKit

/// Bloco de código da resposta: linguagem declarada no topo, botão de copiar à
/// direita e quebra de linha com recuo pendente.
///
/// A linha que não cabe continua na linha seguinte alinhada ao recuo original
/// mais quatro espacos, então nada sai cortado pela borda do iPhone e a
/// indentação do HTML ou do Python continua legível. O corpo fica em fonte
/// monoespaçada do sistema, no menor papel da tipografia, e o cartão usa a
/// superfície elevada para separar do texto corrido. O botão mede 44 pontos de
/// alvo e diz o resultado em voz alta para o VoiceOver.
struct BlocoDeCodigo: View {
    var linguagem: String
    var codigo: String

    @State private var copiado = false
    @State private var larguraDoTexto: CGFloat = 0

    private static let tamanhoBase: CGFloat = 13
    private static let recuoPendente = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cabecalho
            corpo
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Cores.superficieElevada)
        .clipShape(RoundedRectangle(cornerRadius: Raio.m, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Raio.m, style: .continuous)
                .strokeBorder(Cores.borda.opacity(0.55), lineWidth: 1)
        )
    }

    // MARK: - Cabeçalho

    private var cabecalho: some View {
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
    }

    // MARK: - Corpo

    private var corpo: some View {
        Text(textoQuebrado)
            .font(Tipografia.codigo(Self.tamanhoBase))
            .foregroundStyle(Cores.texto)
            .lineSpacing(2)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GeometryReader { medida in
                    Color.clear
                        .onAppear { larguraDoTexto = medida.size.width }
                        .onChange(of: medida.size.width) { _, nova in
                            larguraDoTexto = nova
                        }
                }
            )
            .padding(.horizontal, Espaco.m)
            .padding(.top, Espaco.xs)
            .padding(.bottom, Espaco.m)
    }

    /// Código com as linhas longas já quebradas na largura medida. Enquanto a
    /// largura não chegou, mostra o texto cru: o `Text` ainda quebra sozinho e
    /// nada fica escondido, só perde o recuo pendente por um quadro.
    private var textoQuebrado: String {
        guard larguraDoTexto > 40 else { return codigo }
        let atributos: [NSAttributedString.Key: Any] = [.font: fonteDeMedida]
        let avanco = ("M" as NSString).size(withAttributes: atributos).width
        guard avanco > 0 else { return codigo }
        let colunas = max(12, Int(larguraDoTexto / avanco))
        var saida: [String] = []
        for linha in codigo.components(separatedBy: "\n") {
            let semTabulacao = linha.replacingOccurrences(of: "\t", with: "    ")
            saida.append(contentsOf: quebrar(semTabulacao, colunas: colunas))
        }
        return saida.joined(separator: "\n")
    }

    /// Fonte monoespaçada no mesmo papel do `Tipografia.codigo(13)`, já na
    /// escala do Texto Dinâmico, para a conta de colunas bater com o desenho.
    private var fonteDeMedida: UIFont {
        let tamanho = UIFont.preferredFont(forTextStyle: .footnote).pointSize
        return UIFont.monospacedSystemFont(ofSize: tamanho, weight: .regular)
    }

    /// Quebra uma linha lógica em pedaços que cabem em `colunas` caracteres. O
    /// primeiro pedaço sai sem prefixo e os seguintes saem com o recuo original
    /// mais quatro espaços, que é o recuo pendente.
    private func quebrar(_ linha: String, colunas: Int) -> [String] {
        guard linha.count > colunas else { return [linha] }
        let recuoOriginal = linha.prefix { $0 == " " }.count
        let recuo = min(recuoOriginal, max(0, colunas / 2))
        let prefixo = String(repeating: " ", count: recuo + Self.recuoPendente)
        var restante = Substring(linha)
        var pedacos: [String] = []
        var primeiro = true
        while restante.count > colunas {
            let disponivel = primeiro ? colunas : max(8, colunas - prefixo.count)
            let corte = pontoDeCorte(em: restante, limite: disponivel)
            let pedaco = String(restante.prefix(corte))
            pedacos.append(primeiro ? pedaco : prefixo + pedaco)
            primeiro = false
            restante = restante.dropFirst(corte)
            while restante.first == " " {
                restante = restante.dropFirst()
            }
        }
        if !restante.isEmpty || primeiro {
            let ultimo = String(restante)
            pedacos.append(primeiro ? ultimo : prefixo + ultimo)
        }
        return pedacos
    }

    /// Maior corte que cabe em `limite`, voltando até o último espaço quando ele
    /// não deixa a linha curta demais, para não partir palavra no meio à toa.
    private func pontoDeCorte(em texto: Substring, limite: Int) -> Int {
        guard limite < texto.count else { return texto.count }
        let recorte = texto.prefix(limite)
        if let espaco = recorte.lastIndex(of: " ") {
            let distancia = texto.distance(from: texto.startIndex, to: espaco)
            if distancia >= 8 { return distancia }
        }
        return limite
    }

    // MARK: - Copiar

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
