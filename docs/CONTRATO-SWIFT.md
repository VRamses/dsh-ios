# Contrato do app DSH para iPhone (Swift)

Repositório: `C:\Users\Ramsés\Documents\DSH\dsh-ios` (novo, privado, separado do painel-cockpit).
Produto: app nativo iPhone que conversa com a API da DeepSeek **e** com o DSH do Ramses pela ponte,
com o mesmo desenho de tela. Nenhuma biblioteca de terceiros: só frameworks da Apple.

Este documento é a única fonte de verdade do time. Quem divergir dele cria conflito de compilação.

## 1. Regras que valem para todo mundo

1. Nada de travessão em nenhum arquivo, nem em comentário nem em texto de tela. Use dois pontos, vírgula ou parêntese.
2. Arquivos UTF-8 sem BOM, acentuados. Saída de console em ASCII quando for script.
3. Identificadores, comentários e textos de interface em português. Nome de API da Apple fica como é (`URLSession`, `SwiftData`).
4. Comentário explica **por quê**, não o que o código faz. Sem comentário óbvio.
5. **Não existe compilador Swift nesta máquina.** O `swiftc`, o Xcode e o simulador só existem no runner macOS do GitHub Actions. Portanto: código conservador, API conhecida, nada de recurso obscuro, nada de mágica de tipo. O CI é o compilador, e cada rodada custa 10 a 20 minutos.
6. Ninguém edita arquivo de outro dono. A tabela do item 3 é a lei.
7. Não mexa em git, não faça commit, não faça push. Quem faz isso é o lead.
8. Modo de linguagem Swift 5 (`SWIFT_VERSION: 5.0`) com concorrência mínima. Não tente agradar o Swift 6 estrito: `@MainActor` em view model e `Sendable` só onde o contrato pede.
9. Sem pacote Swift, sem CocoaPods, sem SPM externo. `project.yml` sem `packages`.
10. Alvo mínimo iOS 18.0, só iPhone (família 1), retrato e paisagem no chat.

## 2. Estrutura de pastas (criada em conjunto, cada um na sua)

```
dsh-ios/
  project.yml                          -> swift-base
  .github/workflows/ios.yml            -> swift-base
  .gitignore                           -> lead (já existe)
  docs/CONTRATO-SWIFT.md               -> lead (este arquivo)
  docs/REFERENCIAS.md                  -> swift-chat
  Recursos/Info-App.plist              -> swift-base
  Recursos/Info-Widget.plist           -> swift-base
  Recursos/Info-Compartilhar.plist     -> swift-base
  Recursos/DSH.entitlements            -> swift-base
  Recursos/DSHWidget.entitlements      -> swift-base
  Recursos/DSHCompartilhar.entitlements-> swift-base
  Fontes/App/                          -> swift-base
  Fontes/Nucleo/                       -> swift-base
  Fontes/Provedores/                   -> swift-base
  Fontes/Compartilhado/                -> swift-base
  Fontes/Desenho/                      -> swift-chat
  Fontes/Conversa/                     -> swift-chat
  Fontes/Artefatos/                    -> swift-artefatos
  Fontes/Voz/                          -> swift-voz
  Fontes/Ferramentas/                  -> swift-voz
  Fontes/Plataforma/                   -> swift-plataforma
  Fontes/Widget/                       -> swift-plataforma
  Fontes/Extensao/                     -> swift-plataforma
```

Alvos Xcode: app `DSH`, extensão de widget `DSHWidget`, extensão de compartilhamento `DSHCompartilhar`.
O `project.yml` inclui pastas inteiras por caminho, então arquivo novo aparece sozinho no alvo certo.

## 3. Donos e arquivos

| dono | pasta | entrega |
|---|---|---|
| swift-base | `project.yml`, `.github/workflows/ios.yml`, `Recursos/`, `Fontes/App/`, `Fontes/Nucleo/`, `Fontes/Provedores/`, `Fontes/Compartilhado/` | projeto XcodeGen com três alvos, plists, entitlements, cofre de chaves, modelos SwiftData, loja de conversas, preferências, provedor DeepSeek (SSE), provedor da ponte DSH (SSE), entrada do app, dados de demonstração, workflow de build e IPA |
| swift-chat | `Fontes/Desenho/`, `Fontes/Conversa/` | tokens visuais, `ConversaViewModel`, bolha com markdown e código, pensamento retrátil, tela principal, menu lateral, barra de entrada, lista de sessões do DSH, `docs/REFERENCIAS.md` |
| swift-artefatos | `Fontes/Artefatos/` | `DetectorDeArtefato`, `TelaDeArtefato` (WKWebView isolado, abas Visualização e Código, exportar HTML), `ProcessadorDeDocumentos` (PDFKit, Vision OCR, rótulo de cena para foto sem texto, texto e código), `CartaoDeAnexo` |
| swift-voz | `Fontes/Voz/`, `Fontes/Ferramentas/` | `GerenciadorDeVoz` (Speech pt-BR, pausa para enviar, AVSpeechSynthesizer frase a frase, barge-in), `TelaDeVoz`, `FerramentasDoModelo` (search_web e gerenciar agenda/lembretes via EventKit) |
| swift-plataforma | `Fontes/Plataforma/`, `Fontes/Widget/`, `Fontes/Extensao/` | AppIntents (perguntar, resumir área de transferência), widget com deep links, `ShareViewController`, tratamento de `dsh://`, `CapturaDeFoto` (câmera do sistema, `UIImagePickerController`) |

## 4. Nomes de tipo compartilhados (assinaturas exatas)

Quem importa usa estes nomes. Não crie variação.

### 4.1 Núcleo de dados (swift-base)

```swift
enum Papel: String, Codable { case usuario, assistente, sistema }

@Model final class Conversa {
    var id: UUID
    var titulo: String
    var criadaEm: Date
    var atualizadaEm: Date
    var fixada: Bool
    var anonima: Bool
    var promptDeSistema: String?
    var projetoID: UUID?
    @Relationship(deleteRule: .cascade, inverse: \Mensagem.conversa) var mensagens: [Mensagem]
}

@Model final class Mensagem {
    var id: UUID
    var papelCru: String          // Papel.rawValue
    var conteudo: String
    var raciocinio: String?
    var criadaEm: Date
    var anexosCodificados: Data   // JSON de [Anexo]
    var conversa: Conversa?
    var papel: Papel { get set }  // computed sobre papelCru
}

@Model final class Projeto {
    var id: UUID
    var nome: String
    var instrucoes: String
    var documentosCodificados: Data
}

@Model final class MemoriaDoUsuario {
    var id: UUID
    var fato: String
    var criadaEm: Date
}

struct Anexo: Codable, Identifiable, Hashable {
    enum Tipo: String, Codable { case imagem, pdf, texto, codigo }
    var id: UUID
    var nome: String
    var tipo: Tipo
    var texto: String       // conteúdo extraído ou OCR
    var tamanhoEmBytes: Int
    var imagemBase64: String?   // só foto: JPEG de até 1600 px, para o motor que enxerga imagem
}
```

`Mensagem.conteudo` é o texto final; `raciocinio` é o `reasoning_content`. Regra: mensagem só é salva depois de o streaming terminar ou ser cancelado, e o texto parcial é o que vale.

### 4.2 Cofre e preferências (swift-base)

```swift
enum CofreDeChaves {
    static func guardar(_ valor: String, para chave: String) throws
    static func ler(_ chave: String) throws -> String?
    static func apagar(_ chave: String) throws
}
enum ChaveDoCofre {
    static let apiKeyDeepSeek = "deepseek.apiKey"
    static let tokenDaPonte = "ponte.token"
    static let chaveBuscaWeb = "busca.apiKey"
}
@MainActor final class Preferencias: ObservableObject {
    @Published var modelo: String            // "deepseek-chat" ou "deepseek-reasoner"
    @Published var temperatura: Double       // 0...2, padrão 1.0
    @Published var maxTokens: Int            // padrão 4096
    @Published var enderecoDaPonte: String   // https://desktop-nvl84h2.tail056d02.ts.net:8443
    @Published var usaPonte: Bool            // provedor principal da conversa
    @Published var vozAutomatica: Bool
    static let compartilhada: Preferencias  // instância única, persistida em UserDefaults
}
```

### 4.3 Provedores (swift-base)

```swift
enum OrigemDaConversa: Equatable {
    case deepSeek(modelo: String)
    case ponte(sessaoID: String)
}

struct MensagemDoPedido {
    var papel: Papel
    var texto: String
    var anexos: [Anexo]
}

struct PedidoDeConversa {
    var mensagens: [MensagemDoPedido]
    var promptDeSistema: String?
    var temperatura: Double
    var maxTokens: Int
    var ferramentas: [DefinicaoDeFerramenta]   // vazio quando não há function calling
}

enum FragmentoDaResposta {
    case raciocinio(String)
    case texto(String)
    case chamadaDeFerramenta(ChamadaDeFerramenta)
    case uso(entrada: Int, saida: Int)
    case fim(motivo: String?)
}

protocol ProvedorDeConversa {
    func responder(_ pedido: PedidoDeConversa) -> AsyncThrowingStream<FragmentoDaResposta, Error>
    func cancelar() async
}

enum ErroDaConversa: LocalizedError {
    case semChave, semToken, enderecoInvalido, http(Int, String), rede(String), cancelado
    var errorDescription: String? { get }   // português, curto, sem travessão
}
```

Provedores concretos, ambos `final class ... : ProvedorDeConversa`:

- `ServicoDeepSeek`: `init(apiKey: String)`, `POST https://api.deepseek.com/chat/completions`, `stream: true`, `Authorization: Bearer`. Lê `choices[0].delta.content` e `choices[0].delta.reasoning_content`, além de `choices[0].delta.tool_calls`, `usage` no último quadro e `finish_reason`. Modelos `deepseek-chat` e `deepseek-reasoner` (o reasoner ignora `temperature` e `tools`, então `ServicoDeepSeek` remove esses campos nesse modelo).
- `ServicoPonte`: fala com a ponte do DSH (item 6). Não é chat de API: é espelho de uma sessão do DSH. Expõe também `listarSessoes() async throws -> [SessaoResumo]`, `criarSessao() async throws -> String`, `enviar(texto:modo:) async throws`, `cancelarSessao() async throws`, e `eventos() -> AsyncThrowingStream<EventoDaPonte, Error>`.

Ao abrir uma sessão da ponte, o app mostra o transcrito vindo do quadro `snapshot` do SSE e depois aplica os eventos em ordem. Enviar pelo app usa `POST /v1/sessoes/<id>/mensagem`; o prefixo de identificação é adicionado pelo servidor, o app não prefixa nada.

### 4.4 Desenho (swift-chat expõe, os outros só consomem os tokens)

```swift
enum Cores {
    static let fundo, superficie, superficieElevada, borda: Color
    static let texto, textoFraco, acento, acentoSuave, perigo, sucesso: Color
}
enum Espaco { static let xs, s, m, l, xl, xxl: CGFloat }   // 4, 8, 12, 16, 24, 32
enum Raio { static let s, m, l, g: CGFloat }               // 8, 12, 16, 22
enum Tipografia {
    static func titulo(_ tamanho: CGFloat = 22) -> Font
    static func corpo() -> Font
    static func legenda() -> Font
    static func codigo(_ tamanho: CGFloat = 13) -> Font
}
```

Componentes que só swift-chat cria e usa: `BolhaDeMensagem`, `PensamentoRetratil`, `BarraDeEntrada`, `MenuLateral`, `TelaSessoesDsh`, `TextoRico`, `BlocoDeCodigo`. Os outros usam só tokens mais SwiftUI padrão.

### 4.5 Artefatos (swift-artefatos expõe)

```swift
struct Artefato: Identifiable, Hashable {
    enum Tipo: String { case html, svg, grafico }
    var id: String
    var tipo: Tipo
    var titulo: String
    var linguagem: String
    var codigo: String
}
enum DetectorDeArtefato {
    static func detectar(em texto: String) -> [Artefato]
}
struct TelaDeArtefato: View { var artefato: Artefato }        // folha modal
enum ProcessadorDeDocumentos {
    static func dePdf(url: URL) async throws -> Anexo
    static func deImagem(_ imagem: UIImage, nome: String? = nil) async throws -> Anexo
    static func deTexto(url: URL) async throws -> Anexo
}
struct CartaoDeAnexo: View { var anexo: Anexo; var aoRemover: (() -> Void)? }
```

### 4.6 Voz e ferramentas (swift-voz expõe)

```swift
@MainActor final class GerenciadorDeVoz: ObservableObject {
    @Published var transcrevendo: Bool
    @Published var textoParcial: String
    @Published var nivelDeAudio: CGFloat      // 0...1 para a onda
    var aoConcluirFrase: ((String) -> Void)?
    func iniciar() throws
    func parar()
    func falar(_ texto: String)               // enfileira frase
    func calar()                              // barge-in
}
struct TelaDeVoz: View { }

struct DefiniçãoDeFerramenta { }  // ver 4.7
struct ChamadaDeFerramenta: Identifiable, Codable {
    var id: String
    var nome: String
    var argumentos: String     // JSON cru
}
enum FerramentaDisponivel: String, CaseIterable {
    case buscarNaWeb = "search_web"
    case gerenciarAgenda = "manage_ios_calendar_reminders"
}
@MainActor final class FerramentasDoModelo: ObservableObject {
    func definicoes() -> [DefinicaoDeFerramenta]
    func executar(_ chamada: ChamadaDeFerramenta) async throws -> String   // devolve JSON de resultado
}
```

### 4.7 Definição de ferramenta para a API (swift-base declara o tipo, swift-voz preenche)

```swift
struct DefiniçãoDeFerramenta: Codable, Hashable {   // nome sem acento por causa do JSON da API
    var nome: String
    var descricao: String
    var parametrosJSON: String    // JSON Schema cru, serializado no campo "parameters"
}
struct DefiniçãoDeFerramenta: { }   // NÃO criar dois tipos: o tipo correto é o acima
```

Correção do item 4.6: onde está `struct DefiniçãoDeFerramenta { }` leia-se o tipo do item 4.7, que mora em `Fontes/Nucleo/DefinicaoDeFerramenta.swift` (dono swift-base). swift-voz só usa.

### 4.8 Plataforma (swift-plataforma expõe)

```swift
enum RotaDoApp: String { case conversa, voz, camera, novo, ajustes, dsh }
enum DeepLinks { static let esquema = "dsh"; static let alternativo = "deepseekharness" }
enum IntencoesRegistradas { static var todas: [any AppIntent.Type] { } }
enum ArmazemCompartilhado {          // App Group group.dev.ramses.dsh
    static let identificadorDoGrupo = "group.dev.ramses.dsh"
    static func guardarRotaPendente(_ rota: RotaDoApp)
    static func consumirRotaPendente() -> RotaDoApp?
    static func guardarTextoParaConversa(_ texto: String)
    static func consumirTextoPendente() -> String?
}
```

`ArmazemCompartilhado` mora em `Fontes/Compartilhado/` e pertence a swift-base, porque app, widget e extensão usam. swift-plataforma só consome.

## 5. Entrada do app e captura para o CI (swift-base)

`Fontes/App/DSHApp.swift` com `@main struct DSHApp: App`, `ModelContainer` do SwiftData e `TelaPrincipal` do swift-chat.
Leitura de argumentos de lançamento para o CI fotografar telas determinísticas:

- `-rota conversa|voz|ajustes|dsh|artefato` abre direto naquela tela
- `-demonstracao 1` carrega `DadosDeDemonstracao` (conversa com pensamento longo, bloco de código, artefato HTML e anexos) sem rede
- imprime `rota efetiva: <id>` no stdout, como fazem os apps Kotlin do Ramses

`DadosDeDemonstracao` (em `Fontes/Nucleo/DadosDeDemonstracao.swift`) é a única fonte de dados de captura: conversa com 6 mensagens, raciocínio de 3 parágrafos, um bloco Swift e um HTML de relógio.

## 6. API da ponte do DSH (fatos medidos, não inventar campo)

Base: `https://desktop-nvl84h2.tail056d02.ts.net:8443`, cabeçalho `Authorization: Bearer <token>`, HTTPS obrigatório.

| método | rota | corpo ou retorno |
|---|---|---|
| GET | `/v1/saude` | `{ok, versao, sessaoDsh}` |
| GET | `/v1/sessoes?todas=1` | `{ok, sessoes:[SessaoResumo]}` |
| POST | `/v1/sessoes` | `{workspaceId?, agentPreset?, sessionId?}` devolve `{ok, sessionId, grupo, grupoTitulo, motivo}` |
| GET | `/v1/sessoes/<id>/pagina?throughSeq=N` | `{ok, pagina:{cursor, records, hasMore}}` |
| GET | `/v1/sessoes/<id>/eventos` | SSE: `aberto`, `snapshot`, tipo de evento, `erro`, com `: ping` a cada 15 s |
| POST | `/v1/sessoes/<id>/mensagem` | `{texto, modo:"queue"\|"steer"}` devolve `{ok, requestId, resposta}` |
| POST | `/v1/sessoes/<id>/cancelar` | `{ok}` |
| GET | `/v1/busca?termo=` | `{ok, resultados}` |
| GET/POST | `/v1/credenciais/llm` | leitura e troca de credencial de LLM |

`SessaoResumo`: `{id, curto, titulo, rodando, vazia, cwd, atualizadoEm, contexto, tokens, turnos, seq, aberta, arquivada, grupo, grupoId}`.
`Registro` da página/snapshot: `{seq, tipo, em, dados}`. Texto de mensagem do assistente em `dados.message.content[]` com partes `reasoning` e `text`.
Erro: HTTP 400, 401, 403, 409, 413, 429, 503 com corpo `{ok:false, erro}`.

## 7. API da DeepSeek (para o modo local)

- `POST https://api.deepseek.com/chat/completions`, `Authorization: Bearer <apiKey>`, `Content-Type: application/json`.
- Corpo: `{model, messages:[{role, content}], stream:true, temperature, max_tokens, tools?}`.
- SSE: linhas `data: {json}` e `data: [DONE]`. Em cada quadro, `choices[0].delta.content` e `choices[0].delta.reasoning_content`; último quadro pode trazer `usage` com `prompt_tokens` e `completion_tokens`; `choices[0].finish_reason`.
- `deepseek-reasoner`: não aceita `temperature`, `top_p`, `tools` nem prefixo de assistant. Ao trocar de modelo, o app descarta esses campos e mostra o pensamento no componente retrátil.

## 8. Desenho de tela (para swift-chat)

Regras duras:
- Carregue a skill `declutter` antes de desenhar e siga o que ela manda. Ela está no catálogo do DSH.
- Consulte o MCP devlibs por HTTP quando precisar de padrão de componente: `search_components` e `get_component` em `http://servidor.tail056d02.ts.net:8813/mcp`, com o Bearer que está no bloco `mcp-devlibs` do `cordis.patch.yml` do perfil. Use no máximo 6 consultas.
- Busque imagens dos apps de referência (ChatGPT, Claude, Gemini) e registre em `docs/REFERENCIAS.md` o que copiar e o que evitar, com URL. Não copie marca, cor de marca nem texto de outro app.

Cara do app: fundo escuro por padrão com opção de claro, tipografia do sistema, canto arredondado generoso, bolha do usuário alinhada à direita com acento suave, resposta sem bolha (texto direto na superfície, como Claude), pensamento em cartão retrátil com indicador pulsante, barra de entrada flutuante com seletor de modelo, botão de foto (tirar agora ou escolher da galeria), botão de anexo e botão de enviar que vira quadrado de parar durante o streaming.

## 9. Verificação (o CI é o compilador)

`.github/workflows/ios.yml` (dono swift-base) tem dois jobs, disparo manual:

1. `simulador`: `xcodegen generate`, `xcodebuild -target DSH -sdk iphonesimulator -configuration Debug build`, instala no simulador, lança com `-rota` e `-demonstracao 1` para cada rota, salva PNG em `build/simulador/`. Roda também `xcodebuild test` se houver teste.
2. `ipa`: build `-sdk iphoneos -configuration Release CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`, empacota `Payload/DSH.app` em `build/DSH.ipa` com `ditto -c -k --keepParent`.

Fatos que já custaram rodada vermelha no projeto irmão: `xcodegen` precisa estar instalado via Homebrew no runner (`brew install xcodegen`), o build do app é por `-target` e não por `-scheme` com destino genérico, e o empacotamento usa `ditto`, não `zip`.

## 10. O que não fazer

- Não reescrever o `project.yml` para incluir arquivo por arquivo: pastas inteiras.
- Não colocar chave, token ou senha no código, nem em `UserDefaults`: só no cofre.
- Não usar `NSAllowsArbitraryLoads`: a ponte é HTTPS e a API da DeepSeek é HTTPS.
- Não imprimir resposta inteira no console.
- Não criar terceiro provedor, terceiro modelo de dados, nem tela de onboarding antes do primeiro build verde.
- Não duplicar tipo já definido aqui: se faltar, peça ao lead.
