import Foundation
import Security

enum ErroDoCofre: LocalizedError {
    case valorInvalido
    case falha(OSStatus)

    var errorDescription: String? {
        switch self {
        case .valorInvalido:
            return "O valor gravado no cofre não é texto UTF-8 válido."
        case .falha(let codigo):
            return "O Keychain recusou a operação do cofre (código \(codigo))."
        }
    }
}

enum ChaveDoCofre {
    static let apiKeyDeepSeek = "deepseek.apiKey"
    static let tokenDaPonte = "ponte.token"
}

enum CofreDeChaves {
    static let servico = "dev.ramses.dsh.cofre"

    private static func consultaBase(_ chave: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servico,
            kSecAttrAccount as String: chave,
        ]
    }

    static func guardar(_ valor: String, para chave: String) throws {
        guard let dados = valor.data(using: .utf8) else { throw ErroDoCofre.valorInvalido }
        SecItemDelete(consultaBase(chave) as CFDictionary)
        var atributos = consultaBase(chave)
        atributos[kSecValueData as String] = dados
        atributos[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let estado = SecItemAdd(atributos as CFDictionary, nil)
        guard estado == errSecSuccess else { throw ErroDoCofre.falha(estado) }
    }

    static func ler(_ chave: String) throws -> String? {
        var consulta = consultaBase(chave)
        consulta[kSecReturnData as String] = true
        consulta[kSecMatchLimit as String] = kSecMatchLimitOne
        var resultado: CFTypeRef?
        let estado = SecItemCopyMatching(consulta as CFDictionary, &resultado)
        if estado == errSecItemNotFound { return nil }
        guard estado == errSecSuccess else { throw ErroDoCofre.falha(estado) }
        guard let dados = resultado as? Data else { throw ErroDoCofre.valorInvalido }
        return String(data: dados, encoding: .utf8)
    }

    static func existe(_ chave: String) -> Bool {
        (try? ler(chave))?.isEmpty == false
    }

    static func apagar(_ chave: String) throws {
        let estado = SecItemDelete(consultaBase(chave) as CFDictionary)
        guard estado == errSecSuccess || estado == errSecItemNotFound else {
            throw ErroDoCofre.falha(estado)
        }
    }
}
