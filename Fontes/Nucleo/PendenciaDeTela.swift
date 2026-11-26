import Foundation

/// Pedidos de navegação que uma folha deixa para a tela de trás.
///
/// Ajustes fecha e a conversa abre a lista de sessões do DSH: são duas telas com
/// donos diferentes, e o pedido passa por aqui em vez de virar uma cadeia de
/// fechamentos e reaberturas. Quem consome é `TelaPrincipal`, no `onChange` que
/// já roda quando Ajustes fecha, e o pedido é zerado ao ser atendido para não
/// reabrir sozinho na próxima vez.
@MainActor
enum PendenciaDeTela {
    /// Marcado por Ajustes quando o motor é a ponte mas falta escolher sessão.
    static var abrirSessoes = false
}
