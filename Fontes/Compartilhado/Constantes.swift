import Foundation

enum RotaDoApp: String, CaseIterable, Identifiable {
    case conversa
    case voz
    case camera
    case novo
    case ajustes
    case dsh

    var id: String { rawValue }
}

enum DeepLinks {
    static let esquema = "dsh"
    static let alternativo = "deepseekharness"

    static var todosOsEsquemas: [String] { [esquema, alternativo] }

    static func rota(de url: URL) -> RotaDoApp? {
        // `host` é opcional e `path` não é, então o tipo do array é declarado:
        // sem isso o Swift tenta unificar `String?` com `Any` e não compila.
        let candidatos: [String?] = [url.host, url.path]
        for bruto in candidatos {
            let limpo = (bruto ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
            guard !limpo.isEmpty else { continue }
            if let rota = RotaDoApp(rawValue: limpo) { return rota }
            let primeiro = limpo.split(separator: "/").first.map(String.init) ?? limpo
            if let rota = RotaDoApp(rawValue: primeiro) { return rota }
        }
        return nil
    }
}
