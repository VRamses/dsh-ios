import Foundation

// Tipos de ferramenta do item 4.6 do contrato.
//
// Eles moram em `Fontes/Nucleo/` e não em `Fontes/Ferramentas/` porque três
// camadas os usam: o provedor (que recebe a chamada do modelo no streaming),
// o view model (que despacha) e o executor (que roda). Com o tipo aqui, o
// executor não precisa ser importado por quem só transporta a chamada.
//
// O primeiro build no CI parou exatamente por falta destes dois tipos:
// `ProvedorDeConversa.swift` e `ServicoDeepSeek.swift` referenciavam
// `ChamadaDeFerramenta` sem declaração em lugar nenhum.

/// Uma chamada de ferramenta pedida pelo modelo, ainda não executada.
/// `argumentos` é o JSON cru devolvido pela API, para o executor decidir o que
/// fazer com argumento inválido em vez de o transporte falhar antes.
struct ChamadaDeFerramenta: Identifiable, Codable, Hashable {
    var id: String
    var nome: String
    var argumentos: String
}

/// Catálogo fechado das ferramentas que o app sabe executar.
/// O valor bruto é o nome que vai no JSON da API, então não pode ter acento.
enum FerramentaDisponivel: String, CaseIterable, Codable {
    case buscarNaWeb = "search_web"
    case gerenciarAgenda = "manage_ios_calendar_reminders"

    var nome: String { rawValue }

    var rotuloEmPortugues: String {
        switch self {
        case .buscarNaWeb: return "Buscar na web"
        case .gerenciarAgenda: return "Agenda e lembretes"
        }
    }
}
