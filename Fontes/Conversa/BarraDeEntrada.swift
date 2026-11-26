import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

/// A barra de entrada flutuante: campo de texto, seletor de modelo, foto, anexo e o
/// botão que vira parar.
///
/// A ação principal mora embaixo do polegar direito. Enquanto a resposta corre,
/// o mesmo botão troca de forma e de rótulo em vez de aparecer outro: um alvo só,
/// que muda de intenção. Anexo vira etiqueta acima do campo, com nome e tipo, e a
/// falha de leitura aparece ali mesmo, sem alerta.
///
/// Foto tem botão próprio, separado do clipe: o clipe abre o seletor de arquivos, que
/// no iPhone não enxerga a galeria de fotos. O menu da câmera oferece tirar a foto
/// agora ou escolher uma da galeria, e as duas entram pelo mesmo processador.
struct BarraDeEntrada: View {
    @Binding var texto: String
    @Binding var anexos: [Anexo]

    var estaRespondendo: Bool
    var modeloAtual: String
    var sessaoAtual: String?

    var aoEnviar: @MainActor () -> Void
    var aoParar: @MainActor () -> Void
    var aoEscolherModelo: @MainActor (String) -> Void
    var aoEscolherSessao: @MainActor () -> Void

    @State private var escolhendoArquivo = false
    @State private var escolhendoGaleria = false
    @State private var tirandoFoto = false
    @State private var fotoEscolhida: PhotosPickerItem?
    @State private var processando = false
    @State private var falhaNoAnexo: String?

    private var podeEnviar: Bool {
        !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !anexos.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Espaco.s) {
            if !anexos.isEmpty {
                etiquetas
            }

            TextField("Pergunte ou peça algo", text: $texto, axis: .vertical)
                .font(Tipografia.corpo())
                .foregroundStyle(Cores.texto)
                .tint(Cores.acento)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .accessibilityLabel("Mensagem")

            if let falhaNoAnexo {
                Text(falhaNoAnexo)
                    .font(Tipografia.legenda())
                    .foregroundStyle(Cores.perigo)
            }

            HStack(spacing: Espaco.s) {
                seletorDeModelo
                botaoDeFoto
                botaoDeAnexo
                Spacer(minLength: Espaco.s)
                if processando {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Cores.acento)
                        .accessibilityLabel("Lendo o anexo")
                }
                botaoPrincipal
            }
        }
        .padding(.horizontal, Espaco.l)
        .padding(.vertical, Espaco.m)
        .background(Cores.superficieDeEntrada)
        .clipShape(RoundedRectangle(cornerRadius: Raio.l, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Raio.l, style: .continuous)
                .strokeBorder(Cores.bordaDeEntrada, lineWidth: 1)
        )
        .fileImporter(
            isPresented: $escolhendoArquivo,
            allowedContentTypes: [.pdf, .image, .text, .sourceCode],
            allowsMultipleSelection: true
        ) { resultado in
            switch resultado {
            case .success(let urls):
                Task { await anexar(urls) }
            case .failure(let erro):
                falhaNoAnexo = "Não consegui abrir esse arquivo: \(erro.localizedDescription)"
            }
        }
        // A galeria vem pelo PhotosPicker, que roda fora do processo do app: não pede
        // permissão de biblioteca e devolve só a foto escolhida.
        .photosPicker(isPresented: $escolhendoGaleria, selection: $fotoEscolhida, matching: .images)
        .onChange(of: fotoEscolhida) { _, nova in
            guard let nova else { return }
            Task { await anexarDaGaleria(nova) }
        }
        .fullScreenCover(isPresented: $tirandoFoto) {
            CapturaDeFoto { imagem in
                tirandoFoto = false
                guard let imagem else { return }
                Task { await anexarFoto(imagem) }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Seletor de modelo

    private var seletorDeModelo: some View {
        Menu {
            Button {
                aoEscolherModelo("deepseek-chat")
            } label: {
                itemDeMenu("DeepSeek chat", marcado: sessaoAtual == nil && modeloAtual == "deepseek-chat")
            }
            Button {
                aoEscolherModelo("deepseek-reasoner")
            } label: {
                itemDeMenu("DeepSeek raciocínio", marcado: sessaoAtual == nil && modeloAtual == "deepseek-reasoner")
            }
            Divider()
            Button(action: { aoEscolherSessao() }) {
                itemDeMenu("Escolher sessão do DSH", marcado: sessaoAtual != nil)
            }
        } label: {
            HStack(spacing: Espaco.xs) {
                Text(rotuloDoModelo)
                    .font(Tipografia.codigo(12))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(Cores.textoFraco)
            .padding(.horizontal, Espaco.m)
            .frame(height: 32)
            .background(Cores.superficieElevada)
            .clipShape(RoundedRectangle(cornerRadius: Raio.s, style: .continuous))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Modelo: \(rotuloDoModelo)")
        .accessibilityHint("Troca o modelo ou escolhe uma sessão do DSH.")
    }

    private var rotuloDoModelo: String {
        if sessaoAtual != nil { return "Sessão DSH" }
        return modeloAtual.contains("reasoner") ? "DeepSeek raciocínio" : "DeepSeek chat"
    }

    @ViewBuilder
    private func itemDeMenu(_ titulo: String, marcado: Bool) -> some View {
        HStack(spacing: Espaco.s) {
            Text(titulo)
            if marcado {
                Image(systemName: "checkmark")
            }
        }
    }

    // MARK: - Foto

    /// Menu em vez de dois botões: a barra já tem seletor de modelo, clipe e enviar, e
    /// um toque aqui resolve as duas origens sem espremer mais alvos na linha.
    private var botaoDeFoto: some View {
        Menu {
            if CapturaDeFoto.disponivel {
                Button {
                    tirandoFoto = true
                } label: {
                    Label("Tirar foto", systemImage: "camera")
                }
            }
            Button {
                escolhendoGaleria = true
            } label: {
                Label("Escolher da galeria", systemImage: "photo.on.rectangle")
            }
        } label: {
            Image(systemName: "camera")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Cores.textoFraco)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Enviar foto")
        .accessibilityHint(
            CapturaDeFoto.disponivel
                ? "Tira uma foto agora ou escolhe uma da galeria."
                : "Escolhe uma foto da galeria. A câmera não existe neste aparelho."
        )
    }

    @MainActor
    private func anexarFoto(_ imagem: UIImage) async {
        processando = true
        falhaNoAnexo = nil
        defer { processando = false }
        do {
            anexos.append(try await ProcessadorDeDocumentos.deImagem(imagem, nome: nomeDaFoto("Camera")))
        } catch {
            falhaNoAnexo = "Não consegui usar essa foto: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func anexarDaGaleria(_ item: PhotosPickerItem) async {
        fotoEscolhida = nil
        processando = true
        falhaNoAnexo = nil
        defer { processando = false }
        do {
            guard let dados = try await item.loadTransferable(type: Data.self),
                  let imagem = UIImage(data: dados) else {
                falhaNoAnexo = "Não consegui abrir a foto escolhida."
                return
            }
            anexos.append(try await ProcessadorDeDocumentos.deImagem(imagem, nome: nomeDaFoto("Galeria")))
        } catch {
            falhaNoAnexo = "Não consegui usar essa foto: \(error.localizedDescription)"
        }
    }

    /// Nome com origem e hora: três fotos seguidas no mesmo pedido ficam distinguíveis
    /// na etiqueta e no cartão da conversa.
    private func nomeDaFoto(_ origem: String) -> String {
        let formato = DateFormatter()
        formato.locale = Locale(identifier: "pt_BR")
        formato.dateFormat = "dd-MM-yyyy HH.mm.ss"
        return "Foto \(origem) \(formato.string(from: Date())).jpg"
    }

    // MARK: - Anexo

    private var botaoDeAnexo: some View {
        Button {
            escolhendoArquivo = true
        } label: {
            Image(systemName: "paperclip")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Cores.textoFraco)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Anexar arquivo")
        .accessibilityHint("Abre o seletor de PDF, imagem, texto ou código.")
    }

    private var etiquetas: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Espaco.s) {
                ForEach(anexos) { anexo in
                    HStack(spacing: Espaco.xs) {
                        Image(systemName: icone(de: anexo.tipo))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Cores.textoFraco)
                        Text(anexo.nome)
                            .font(Tipografia.legenda())
                            .foregroundStyle(Cores.texto)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 160, alignment: .leading)
                        Button {
                            remover(anexo)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Cores.textoFraco)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, -Espaco.m)
                        .accessibilityLabel("Remover \(anexo.nome)")
                    }
                    .padding(.leading, Espaco.m)
                    .frame(height: 36)
                    .background(Cores.superficieElevada)
                    .clipShape(RoundedRectangle(cornerRadius: Raio.s, style: .continuous))
                }
            }
        }
        .frame(height: 36)
        .accessibilityElement(children: .contain)
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

    private func remover(_ anexo: Anexo) {
        anexos.removeAll { $0.id == anexo.id }
    }

    @MainActor
    private func anexar(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        processando = true
        falhaNoAnexo = nil
        defer { processando = false }

        for url in urls {
            let acessivel = url.startAccessingSecurityScopedResource()
            defer {
                if acessivel { url.stopAccessingSecurityScopedResource() }
            }
            let tipo = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? UTType.data
            do {
                if tipo.conforms(to: .pdf) {
                    anexos.append(try await ProcessadorDeDocumentos.dePdf(url: url))
                } else if tipo.conforms(to: .image) {
                    guard let dados = try? Data(contentsOf: url), let imagem = UIImage(data: dados) else {
                        falhaNoAnexo = "Não consegui abrir a imagem \(url.lastPathComponent)."
                        continue
                    }
                    anexos.append(try await ProcessadorDeDocumentos.deImagem(imagem))
                } else {
                    anexos.append(try await ProcessadorDeDocumentos.deTexto(url: url))
                }
            } catch {
                falhaNoAnexo = "Não consegui ler \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Enviar e parar

    private var botaoPrincipal: some View {
        Button {
            if estaRespondendo {
                aoParar()
            } else {
                aoEnviar()
            }
        } label: {
            ZStack {
                formaDoBotao
                    .frame(width: 40, height: 40)
                Image(systemName: estaRespondendo ? "stop.fill" : "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(corDoGlifo)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!estaRespondendo && !podeEnviar)
        .accessibilityLabel(estaRespondendo ? "Parar resposta" : "Enviar mensagem")
        .accessibilityHint(estaRespondendo ? "Cancela a resposta em andamento e guarda o que já chegou." : "")
    }

    @ViewBuilder
    private var formaDoBotao: some View {
        if estaRespondendo {
            RoundedRectangle(cornerRadius: Raio.s, style: .continuous)
                .fill(Cores.acento)
        } else {
            Circle()
                .fill(podeEnviar ? Cores.acento : Cores.superficieElevada)
        }
    }

    private var corDoGlifo: Color {
        if estaRespondendo { return Cores.fundo }
        return podeEnviar ? Cores.fundo : Cores.textoFraco
    }
}
