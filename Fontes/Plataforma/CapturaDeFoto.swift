import SwiftUI
import UIKit

/// A câmera do sistema. O SwiftUI não tem captura de foto, então o único caminho sem
/// biblioteca de terceiro é embrulhar o `UIImagePickerController`. Só modo foto entra
/// aqui: vídeo e escolha múltipla ficam fora do escopo da barra de entrada.
///
/// O componente não fecha a folha sozinho. Ele devolve a imagem, ou `nil` quando a
/// pessoa cancela, e quem apresentou decide o que fazer com o estado de apresentação.
struct CapturaDeFoto: UIViewControllerRepresentable {
    /// Chamado na thread principal com a foto tirada, ou com `nil` no cancelamento.
    var aoTerminar: (UIImage?) -> Void

    /// No simulador não existe câmera. A barra consulta isto antes de oferecer a opção,
    /// para não abrir uma folha preta que nunca devolve nada.
    static var disponivel: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let camera = UIImagePickerController()
        camera.sourceType = .camera
        camera.cameraCaptureMode = .photo
        camera.allowsEditing = false
        camera.delegate = context.coordinator
        return camera
    }

    func updateUIViewController(_ camera: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordenador {
        Coordenador(aoTerminar: aoTerminar)
    }

    final class Coordenador: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let aoTerminar: (UIImage?) -> Void

        init(aoTerminar: @escaping (UIImage?) -> Void) {
            self.aoTerminar = aoTerminar
        }

        func imagePickerController(
            _ seletor: UIImagePickerController,
            didFinishPickingMediaWithInfo informacoes: [UIImagePickerController.InfoKey: Any]
        ) {
            aoTerminar(informacoes[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ seletor: UIImagePickerController) {
            aoTerminar(nil)
        }
    }
}
