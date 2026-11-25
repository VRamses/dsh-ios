# DSH para iPhone

App nativo de iPhone (iOS 18 ou mais novo) para conversar com o DSH que roda neste notebook e
com a API da DeepSeek, com histórico local, artefatos interativos, voz, ferramentas e
integração com Atalhos.

Dois motores, escolhidos em Ajustes:

| motor | resposta vem de | o que ganha | o que depende |
|---|---|---|---|
| Ponte do DSH | a sua instalação do DSH, pela ponte do tailnet | as ferramentas de MCP (Droz, Miro, Jira, Zendesk) | notebook ligado, Tailscale ativo, token da ponte no Keychain do aparelho |
| DeepSeek direto | a API pública da DeepSeek | busca web, agenda e lembretes | internet, chave da API no Keychain do aparelho |

A ponte só entra em uso quando existe uma sessão do DSH escolhida em "Sessões do DSH", porque
sem sessão não há para onde mandar a pergunta.

## Estado

- Compila no GitHub Actions (`macos-15`, Xcode 16.4), sem Mac na mão. O passo a passo está em
  [docs/ENTREGA.md](docs/ENTREGA.md).
- A rodada compila o app, o widget e a extensão de compartilhar, roda no simulador e captura as
  cinco rotas. As capturas ficam em [docs/capturas](docs/capturas).
- A saída principal é um IPA **sem assinatura**: o iPhone não instala o arquivo sozinho, ele
  precisa ser assinado com a sua conta Apple antes. O `ipa` traz dois pacotes:
  `DSH-livre.ipa`, só o app principal, que é o que se instala com conta Apple gratuita, e
  `DSH.ipa`, com o widget e a extensão de compartilhar, que só assina em conta paga.
- Conta gratuita serve, com os limites que a entrega descreve (3 apps por semana, re-assinar a
  cada 7 dias, sem App Group), e o passo a passo de Sideloadly e de AltStore está em
  [docs/ENTREGA.md](docs/ENTREGA.md), seção 5.
- Nada foi testado em iPhone físico: o que está provado é compilação, empacotamento e execução
  no simulador.

## Como compilar

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project DSH.xcodeproj -target DSH -sdk iphonesimulator \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

No Windows não existe compilador Swift, e não dá para instalar um sem macOS. Quem compila é o
workflow `.github/workflows/ios.yml`, que só roda por disparo manual:

```powershell
gh workflow run ios.yml --repo VRamses/dsh-ios -f ipa=true
```

O primeiro passo do job exige o repositório público apenas para consumir os minutos gratuitos de
runner macOS desta conta; os scripts em `_tmp/dsh-ios` devolvem a visibilidade privada no fim.

## Documentos

- [docs/CONTRATO-SWIFT.md](docs/CONTRATO-SWIFT.md): contrato técnico dos tipos e das telas.
- [docs/ENTREGA.md](docs/ENTREGA.md): instalação, limites, o que a última rodada provou e o que
  continua aberto.
- [docs/REFERENCIAS.md](docs/REFERENCIAS.md): as referências visuais usadas na interface.
