import Foundation
import SwiftData

enum Papel: String, Codable {
    case usuario
    case assistente
    case sistema
}

struct Anexo: Codable, Identifiable, Hashable {
    enum Tipo: String, Codable {
        case imagem
        case pdf
        case texto
        case codigo
    }

    var id: UUID
    var nome: String
    var tipo: Tipo
    var texto: String
    var tamanhoEmBytes: Int

    init(id: UUID = UUID(), nome: String, tipo: Tipo, texto: String = "", tamanhoEmBytes: Int = 0) {
        self.id = id
        self.nome = nome
        self.tipo = tipo
        self.texto = texto
        self.tamanhoEmBytes = tamanhoEmBytes
    }

    static func codificar(_ anexos: [Anexo]) -> Data {
        (try? JSONEncoder().encode(anexos)) ?? Data("[]".utf8)
    }

    static func decodificar(_ dados: Data) -> [Anexo] {
        guard !dados.isEmpty else { return [] }
        return (try? JSONDecoder().decode([Anexo].self, from: dados)) ?? []
    }
}

@Model
final class Conversa {
    var id: UUID
    var titulo: String
    var criadaEm: Date
    var atualizadaEm: Date
    var fixada: Bool
    var anonima: Bool
    var promptDeSistema: String?
    var projetoID: UUID?
    @Relationship(deleteRule: .cascade, inverse: \Mensagem.conversa)
    var mensagens: [Mensagem]

    init(
        id: UUID = UUID(),
        titulo: String = "Conversa nova",
        criadaEm: Date = Date(),
        atualizadaEm: Date = Date(),
        fixada: Bool = false,
        anonima: Bool = false,
        promptDeSistema: String? = nil,
        projetoID: UUID? = nil,
        mensagens: [Mensagem] = []
    ) {
        self.id = id
        self.titulo = titulo
        self.criadaEm = criadaEm
        self.atualizadaEm = atualizadaEm
        self.fixada = fixada
        self.anonima = anonima
        self.promptDeSistema = promptDeSistema
        self.projetoID = projetoID
        self.mensagens = mensagens
    }

    var mensagensEmOrdem: [Mensagem] {
        mensagens.sorted { $0.criadaEm < $1.criadaEm }
    }

    var ultimaMensagem: Mensagem? {
        mensagensEmOrdem.last
    }
}

@Model
final class Mensagem {
    var id: UUID
    var papelCru: String
    var conteudo: String
    var raciocinio: String?
    var criadaEm: Date
    var anexosCodificados: Data
    var conversa: Conversa?

    init(
        id: UUID = UUID(),
        papel: Papel = .usuario,
        conteudo: String,
        raciocinio: String? = nil,
        criadaEm: Date = Date(),
        anexos: [Anexo] = [],
        conversa: Conversa? = nil
    ) {
        self.id = id
        self.papelCru = papel.rawValue
        self.conteudo = conteudo
        self.raciocinio = raciocinio
        self.criadaEm = criadaEm
        self.anexosCodificados = Anexo.codificar(anexos)
        self.conversa = conversa
    }

    var papel: Papel {
        get { Papel(rawValue: papelCru) ?? .assistente }
        set { papelCru = newValue.rawValue }
    }

    var anexos: [Anexo] {
        get { Anexo.decodificar(anexosCodificados) }
        set { anexosCodificados = Anexo.codificar(newValue) }
    }
}

@Model
final class Projeto {
    var id: UUID
    var nome: String
    var instrucoes: String
    var documentosCodificados: Data

    init(
        id: UUID = UUID(),
        nome: String,
        instrucoes: String = "",
        documentosCodificados: Data = Data("[]".utf8)
    ) {
        self.id = id
        self.nome = nome
        self.instrucoes = instrucoes
        self.documentosCodificados = documentosCodificados
    }
}

@Model
final class MemoriaDoUsuario {
    var id: UUID
    var fato: String
    var criadaEm: Date

    init(
        id: UUID = UUID(),
        fato: String,
        criadaEm: Date = Date()
    ) {
        self.id = id
        self.fato = fato
        self.criadaEm = criadaEm
    }
}
