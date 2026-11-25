import Foundation

/// Página gerada pelo modelo, pronta para ser aberta em folha própria.
/// Tipo do contrato (item 4.5): quem cria é o detector, quem apresenta é a tela.
struct Artefato: Identifiable, Hashable {
    enum Tipo: String {
        case html
        case svg
        case grafico
    }

    var id: String
    var tipo: Tipo
    var titulo: String
    var linguagem: String
    var codigo: String
}
