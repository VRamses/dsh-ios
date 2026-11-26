import AVFoundation
import SwiftUI
import UIKit

/// Leitor de QR com a câmera de dentro do app.
///
/// Até aqui o pareamento dependia de outro app: o QR do computador era lido pela
/// câmera do sistema, que abria `dsh://ajustes?parear=...`, e o DSH só recebia o
/// pedido se já estivesse instalado e fosse escolhido na folha de compartilhar.
/// Com o leitor aqui dentro, Ajustes aponta a câmera para o QR do computador e o
/// texto lido entra na mesma função que já tratava o pedido vindo do URL.
///
/// O QR não carrega o token: carrega o endereço e um código de uso único que
/// vale cinco minutos. Quem troca o código pelo token é `aplicarPareamento()`,
/// em `TelaDeAjustes`, e o token vai direto para o cofre.
struct LeitorDeQR: UIViewControllerRepresentable {
    /// Recebe o texto do primeiro QR lido, uma vez só, na thread principal.
    var aoLer: (String) -> Void

    /// Recebe a razão de não haver imagem: permissão negada ou câmera ausente.
    var aoFalhar: (String) -> Void

    /// No simulador não existe câmera. A folha consulta isto antes de montar a
    /// prévia, para não abrir um retângulo preto que nunca devolve nada.
    static var disponivel: Bool {
        AVCaptureDevice.default(for: .video) != nil
    }

    func makeUIViewController(context: Context) -> ControladorDeCamera {
        let controlador = ControladorDeCamera()
        controlador.aoLer = aoLer
        controlador.aoFalhar = aoFalhar
        return controlador
    }

    func updateUIViewController(_ controlador: ControladorDeCamera, context: Context) {}

    /// A prévia da câmera é uma camada do `AVCaptureVideoPreviewLayer`, e não uma
    /// `View` do SwiftUI: sem esta ponte o SwiftUI não tem onde desenhar o vídeo.
    final class ControladorDeCamera: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var aoLer: ((String) -> Void)?
        var aoFalhar: ((String) -> Void)?

        private let sessao = AVCaptureSession()
        private let fila = DispatchQueue(label: "dev.ramses.dsh.leitor-de-qr")
        private var previa: AVCaptureVideoPreviewLayer?
        private var jaLeu = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            pedirPermissao()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previa?.frame = view.bounds
        }

        /// A folha saiu: a câmera para junto, para não ficar ligada atrás de
        /// outra tela consumindo bateria.
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            parar()
        }

        /// Para a captura sem esperar a fila: chamado ao fechar a folha e depois
        /// da primeira leitura, para a câmera não ficar ligada atrás da tela.
        func parar() {
            let sessao = self.sessao
            fila.async {
                if sessao.isRunning { sessao.stopRunning() }
            }
        }

        private func pedirPermissao() {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                montar()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] liberado in
                    guard let eu = self else { return }
                    DispatchQueue.main.async {
                        if liberado {
                            eu.montar()
                        } else {
                            eu.avisar("A câmera não foi liberada. Sem ela não dá para ler o QR do computador.")
                        }
                    }
                }
            default:
                avisar("A câmera está bloqueada para o DSH. Libere em Ajustes do iPhone, DSH, Câmera.")
            }
        }

        private func montar() {
            guard let aparelho = AVCaptureDevice.default(for: .video),
                  let entrada = try? AVCaptureDeviceInput(device: aparelho) else {
                avisar("Este iPhone não tem câmera disponível para ler o QR.")
                return
            }

            sessao.beginConfiguration()
            if sessao.canAddInput(entrada) {
                sessao.addInput(entrada)
            }
            let saida = AVCaptureMetadataOutput()
            if sessao.canAddOutput(saida) {
                sessao.addOutput(saida)
                // O delegado recebe na fila principal: quem trata a leitura mexe
                // em estado de tela.
                saida.setMetadataObjectsDelegate(self, queue: .main)
                if saida.availableMetadataObjectTypes.contains(.qr) {
                    saida.metadataObjectTypes = [.qr]
                }
            }
            sessao.commitConfiguration()

            let camada = AVCaptureVideoPreviewLayer(session: sessao)
            camada.videoGravity = .resizeAspectFill
            camada.frame = view.bounds
            view.layer.addSublayer(camada)
            previa = camada

            fila.async { [sessao] in
                if !sessao.isRunning { sessao.startRunning() }
            }
        }

        private func avisar(_ motivo: String) {
            DispatchQueue.main.async { [weak self] in
                self?.aoFalhar?(motivo)
            }
        }

        // MARK: - AVCaptureMetadataOutputObjectsDelegate

        func metadataOutput(
            _ saida: AVCaptureMetadataOutput,
            didOutput objetos: [AVMetadataObject],
            from conexao: AVCaptureConnection
        ) {
            guard !jaLeu else { return }
            for objeto in objetos {
                guard let codigo = objeto as? AVMetadataMachineReadableCodeObject,
                      codigo.type == .qr,
                      let texto = codigo.stringValue,
                      !texto.isEmpty else { continue }
                jaLeu = true
                parar()
                aoLer?(texto)
                return
            }
        }
    }
}
