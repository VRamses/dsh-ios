import Foundation

struct DefiniçãoDeFerramenta: Codable, Hashable {
    var nome: String
    var descricao: String
    var parametrosJSON: String

    init(nome: String, descricao: String, parametrosJSON: String) {
        self.nome = nome
        self.descricao = descricao
        self.parametrosJSON = parametrosJSON
    }

    var parametros: [String: Any]? {
        guard let dados = parametrosJSON.data(using: .utf8) else { return nil }
        guard let objeto = try? JSONSerialization.jsonObject(with: dados) else { return nil }
        return objeto as? [String: Any]
    }
}

typealias DefinicaoDeFerramenta = DefiniçãoDeFerramenta
