# Entrega: como o app chega no iPhone

Este documento responde a pergunta prática: como o app sai do código e vira ícone na tela
do iPhone, sem um Mac na mão. Ele também registra o que NÃO vai funcionar, para a expectativa
ficar certa desde o começo.

## 1. O que o app é

Aplicativo nativo em SwiftUI para iPhone (iOS 18 ou mais novo), com dois motores de conversa:

| motor | o que usa | o que depende |
|---|---|---|
| Ponte do DSH | a sua instância do DSH, pela `ponte` do tailnet | notebook ligado, Tailscale ativo, token da ponte no cofre do aparelho |
| DeepSeek direto | a API pública da DeepSeek, com a sua chave | internet, chave da API no cofre do aparelho |

O motor da ponte é o que mantém os seus MCPs (Droz, Miro, Jira, Zendesk) disponíveis, porque a
pergunta é respondida pela sua instalação do DSH, e não por um modelo solto. O motor direto
serve quando o notebook está desligado; nele não existe MCP nenhum, só o modelo.

## 2. Como o app compila

Não existe compilador Swift nesta máquina Windows e não dá para instalar um: compilar para iOS
exige o Xcode, que só roda em macOS. Por isso quem compila é o GitHub Actions, no runner
`macos-15` do repositório privado `VRamses/dsh-ios`.

O caminho é sempre este:

```powershell
# 1. manda o código
git -C "C:\Users\Ramsés\Documents\DSH\dsh-ios" push origin main

# 2. dispara a compilação (o workflow só roda por disparo manual)
gh workflow run ios.yml --repo VRamses/dsh-ios -f ipa=true

# 3. acompanha
gh run list --repo VRamses/dsh-ios --limit 3
gh run watch --repo VRamses/dsh-ios

# 4. baixa o resultado
gh run download --repo VRamses/dsh-ios --name ipa --dir "C:\Users\Ramsés\Downloads\dsh-ipa"
```

O artefato `ipa` traz `DSH.ipa`; o artefato `simulador` traz as capturas de tela de cada rota
(`conversa`, `voz`, `ajustes`, `dsh`, `artefato`) e o log de compilação. Quando a compilação
falha, o log com o erro do `xcodebuild` está no artefato `simulador`, em `build-compilacao.log`
ou no próprio resumo do job.

Custo: o runner macOS consome cota de minutos do GitHub Actions, e é o recurso mais caro da
conta. Cada rodada completa gasta de 8 a 15 minutos. Com o repositório privado, esses minutos
saem da cota paga; com o repositório público, macOS é gratuito, mas o código fica exposto.

## 3. O que é o IPA sem assinatura

O workflow compila com `CODE_SIGNING_ALLOWED=NO`, ou seja, gera o binário e empacota em
`Payload/DSH.app` dentro de um `.ipa`, sem assinatura da Apple. Nesse estado o iPhone não
instala o arquivo sozinho: ele precisa ser assinado com um certificado válido para o aparelho.
Quem faz essa assinatura é o programa de instalação no PC, usando a sua conta Apple.

Três caminhos, do mais simples ao mais trabalhoso:

| caminho | o que precisa | validade da assinatura | limitações |
|---|---|---|---|
| AltStore ou SideStore | conta Apple gratuita, um PC com o AltServer rodando na mesma rede de vez em quando | 7 dias, renovação automática pelo AltServer | até 3 apps por aparelho, 10 identificadores por semana |
| Sideloadly | conta Apple gratuita e cabo USB | 7 dias, renovação manual | mais simples de instalar, sem renovação automática |
| Conta de desenvolvedor paga | Apple Developer Program, US$ 99 por ano | 1 ano por perfil | libera App Group, widget, extensão de compartilhamento e TestFlight |

## 4. O limite que precisa ficar claro

Com conta Apple gratuita o iOS não habilita a capacidade de App Group, e sem App Group o widget
e a extensão de compartilhamento não conseguem entregar dados para o app. O app em si continua
funcionando: conversa, voz, artefatos e ajustes são todos dentro do processo principal. O que
quebra é justamente a ponte entre extensões:

- o widget abre as rotas por link, o que funciona sempre;
- o widget mostrar a última conversa e a extensão de compartilhamento mandar texto para o app
  dependem de App Group, então na conta gratuita isso não entrega.

Com conta paga, os três alvos (app, `DSHWidget` e `DSHCompartilhar`) assinam com o mesmo perfil
e o App Group `group.dev.ramses.dsh` passa a valer. O `project.yml` já está preparado para os
três; só falta o perfil pago na hora de assinar.

Outros limites, sem rodeio:

- não há distribuição pela App Store: o app usa API privada de uso pessoal, guarda token no
  cofre do aparelho e não tem política de privacidade publicada, o que a revisão da Apple exige;
- não há notificação push, porque push exige servidor da Apple com certificado de provedor;
- o motor da ponte só funciona no tailnet: fora dele, o app cai no motor direto da DeepSeek
  ou mostra erro de conexão, sem inventar resposta;
- a assinatura gratuita vence a cada 7 dias e o app para de abrir até ser reassinado. Isso é
  regra do iOS, não do projeto.

## 5. Primeira instalação, passo a passo

1. Baixe o artefato `ipa` e deixe `DSH.ipa` numa pasta conhecida.
2. Instale o Sideloadly no PC (ou o AltServer, se preferir renovação automática).
3. Conecte o iPhone por cabo, confie no computador e no perfil de desenvolvedor.
4. Arraste o `DSH.ipa` para o Sideloadly, informe a conta Apple e a senha, e mande instalar.
5. No iPhone, em Ajustes, Perfil e Gerenciamento de Dispositivo, autorize o perfil do
   desenvolvedor. Sem isso o app fecha na hora que abre.
6. Abra o app, vá em Ajustes e cole: a chave da API da DeepSeek e, se for usar a ponte, o
   endereço do tailnet mais o token da ponte.

## 6. O que conferir quando algo não abre

| sintoma | causa provável | o que fazer |
|---|---|---|
| app fecha ao abrir | perfil de desenvolvedor não autorizado, ou assinatura vencida | autorizar o perfil nos Ajustes, ou reassinar |
| erro de rede no motor da ponte | Tailscale fora, notebook desligado, endereço sem `https://` | conferir o tailnet e o endereço salvo nos Ajustes |
| motor direto responde 401 | chave da API errada ou revogada | colar a chave de novo em Ajustes |
| widget abre mas não mostra conversa | App Group indisponível na conta gratuita | comportamento esperado, ver item 4 |
| captura de tela em branco no artefato | a rota não existe ou o app não chegou a abrir | ler o `console.txt` e o log de compilação |

## 7. Estado do repositório

- `docs/CONTRATO-SWIFT.md`: contrato técnico do time, é a fonte de verdade dos tipos.
- `docs/REFERENCIAS.md`: as referências visuais usadas na interface.
- `docs/ENTREGA.md`: este documento.
- `project.yml`: geração do projeto Xcode com XcodeGen, três alvos.
- `.github/workflows/ios.yml`: a compilação no Actions, com os jobs `simulador` e `ipa`.
- `Fontes/`: o código, separado por assunto (App, Nucleo, Provedores, Compartilhado, Desenho,
  Conversa, Artefatos, Voz, Ferramentas, Plataforma, Widget, Extensao).
- `Recursos/`: os três `Info.plist`, os três `.entitlements` e o catálogo `Assets.xcassets`.

## 8. O ícone do app

O ícone é o sinal de prompt do terminal: um chevron e um cursor em âmbar (`0xE3A33C`, o mesmo
token `Cores.acento` do tema escuro) sobre o fundo `0x0E1013`. Ele é gerado por script, não é
arte de terceiro, para o app não carregar licença de imagem.

- Arquivo: `Recursos/Assets.xcassets/AppIcon.appiconset/icone-1024.png`, 1024x1024, sem alfa.
- Formato do catálogo: ícone único `universal` com `platform: ios`, que é como o Xcode 16
  aceita o tamanho 1024 desde o iOS 18; o Xcode deriva os outros tamanhos.
- Ligado ao alvo por `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` no `project.yml`. Sem essa
  linha o catálogo compila, vira `Assets.car` no pacote e o ícone continua vazio na tela do
  iPhone.
- O script que desenha o PNG é `Recursos/icone/gerar-icone.ps1` e roda em Windows PowerShell
  5.1 com `System.Drawing`, sem dependência externa. Ele é ASCII puro de propósito: o
  PowerShell 5.1 lê arquivo com acento como ANSI, e aí o caminho do usuário chega corrompido e
  a gravação falha com acesso negado. Para refazer:
  `powershell -NoProfile -ExecutionPolicy Bypass -File Recursos\icone\gerar-icone.ps1`.

