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

O motor se escolhe em Ajustes, no menu lateral, e a escolha é lida de novo quando a folha
fecha. A ponte só entra em uso quando existe uma sessão do DSH escolhida nesta execução, porque
sem sessão não há para onde mandar a pergunta; a própria tela de Ajustes diz isso.

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

O artefato `ipa` traz dois pacotes: `DSH-livre.ipa`, que é o que se instala com conta Apple
gratuita, e `DSH.ipa`, o pacote completo com as duas extensões, que só assina em conta paga. O
artefato `simulador` traz as capturas de tela de cada rota
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

O job `ipa` produz dois pacotes, e a escolha entre eles não é preferência:

| pacote | conteúdo | serve para |
|---|---|---|
| `DSH-livre.ipa` | só o app principal, sem `PlugIns` | conta Apple gratuita, no Sideloadly ou no AltStore |
| `DSH.ipa` | app principal mais `DSHWidget.appex` e `DSHCompartilhar.appex` | conta Apple paga, onde os três assinam |

O pacote com extensão pede três perfis separados, um por bundle, e o App Group que só a conta
paga libera; com conta gratuita o Sideloadly recusa o arquivo ou instala um app que fecha na
abertura. Por isso o `DSH-livre.ipa` sai da `DSH.app` já compilada, com a pasta `PlugIns`
removida antes de zipar. O código do app principal não depende do App Group para nada
essencial: as leituras do armazém compartilhado checam `nil` e simplesmente não entregam o
texto vindo da extensão de compartilhamento, que é o único recurso perdido nessa escolha.

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

O que só você pode fazer, porque envolve o seu aparelho e a sua senha: plugar o cabo, tocar
"Confiar" no iPhone, digitar a senha da conta Apple e o código de dois fatores, e autorizar o
perfil de desenvolvedor no aparelho. Nenhum agente faz isso de fora, e a senha da conta Apple
não deve ser entregue a ninguém.

O que o PC precisa ter, no Windows:

| programa | para quê | observação |
|---|---|---|
| iTunes fora da Microsoft Store, ou o app Apple Devices | driver do iPhone e bibliotecas que o AltServer usa | o que já está instalado nesta máquina é só o `Apple Mobile Device Support` que veio com o iCloud, e ele serve para o Sideloadly, não para o AltServer |
| Sideloadly | assinar e instalar uma vez, pelo cabo | caminho mais curto para o primeiro app no aparelho |
| AltServer mais AltStore | renovar a assinatura sozinho a cada 7 dias, pela rede local | exige o iTunes instalado e o AltServer aberto no PC |

Caminho A, Sideloadly (recomendado para a primeira instalação):

1. Baixe o artefato `ipa` da rodada verde e pegue `DSH-livre.ipa`.
2. Instale o Sideloadly no PC e abra. Ele instala os drivers que faltarem.
3. Ligue o iPhone por cabo, toque em "Confiar" no aparelho e informe a senha do aparelho.
4. No iPhone, abra Ajustes, Privacidade e Segurança, Modo de Desenvolvedor e ligue. O iOS 16
   ou mais novo exige isso para abrir app assinado fora da App Store, e o aparelho reinicia.
5. Arraste `DSH-livre.ipa` para a janela do Sideloadly, preencha a conta Apple, e mande
   instalar. Se a conta tiver dois fatores, o programa pede o código na hora.
6. No iPhone, em Ajustes, Geral, VPN e Gerenciamento de Dispositivo, toque no perfil com o seu
   Apple ID e escolha "Confiar". Sem esse passo o app fecha no instante em que abre.
7. Abra o app DSH, vá em Ajustes e cole: a chave da API da DeepSeek e, se for usar a ponte, o
   endereço do tailnet mais o token da ponte.
8. Depois que a ponte estiver configurada e respondendo no botão "Testar conexão", o botão
   "Importar chaves do computador" traz a chave da DeepSeek do cofre do PC para o cofre do
   iPhone, sem digitar nada. Ele usa o mesmo token da ponte e o endpoint
   `POST /v1/credenciais/llm/exportar`; a tela informa quais nomes faltaram do lado do PC.

Duas coisas que a primeira instalação ensinou, e que valem para a próxima:

- O IPA tem de ter `Payload/` como pasta raiz do zip. Foi o que faltava no `DSH-livre.ipa`: o
  pacote saía com `PayloadLivre/` na raiz e o Sideloadly recusava com
  `Guru Meditation ... Can't listdir a file`. O workflow agora monta as duas pastas e confere a
  primeira entrada de cada pacote com `unzip -l`.
- Para carregar o IPA na janela do Sideloadly, o caminho que funciona é passar o arquivo como
  argumento na linha de comando. Arrastar, colar com `Ctrl+V` e clicar no ícone não carregaram.

### A segunda instalação, no SUPERCOLLIDER, em 25/11/2026

Esta é a instalação que levou ao aparelho o build com o botão "Importar chaves do computador".
Os números abaixo foram medidos na máquina que fez o serviço, o SUPERCOLLIDER, e não no notebook.

| o que | como foi medido | resultado |
|---|---|---|
| pacote instalado | baixar o artefato `ipa` da rodada `45608662574` (commit `e71b7b8`) | `DSH-livre.ipa` com 774.574 bytes e sha256 `BCFF9158718BDF4E7DE0ED4E975B87DD34B427B6DDC50F154F1BEE081E92AE51` |
| raiz e conteúdo do pacote | listar as entradas do `.ipa` antes de instalar | 15 entradas, a primeira é `Payload/`, e nenhuma tem `PlugIns` |
| botão novo dentro do binário | procurar as strings `Importar chaves` e `importarChaves` no `Payload/DSH.app/DSH` | presentes, então não é o pacote anterior |
| assinatura e instalação | Sideloadly v0.72 em `%LOCALAPPDATA%\Sideloadly\sideloadly.exe`, IPA passado por argumento | `Done.` em 100% às 09:43 |
| registro da instalação | tabela `installations` do `installations.db` do Sideloadly | linha nova com `final_bundle_id` `dev.ramses.dsh.AWX55ZH3FU`, `known_ttl` 7 e `refresh_at_hours` 96, `last_error` vazio e `failures_count` 0 |
| aparelho | usbmuxd na porta 27015 e a lista do Sideloadly | iPhone `00008140-001A71A10189801C`, iOS 27.3, por USB |

Duas coisas que esta instalação ensinou:

- A atualização é no lugar, não uma segunda cópia: o aparelho já tinha `dev.ramses.dsh.AWX55ZH3FU`
  da mesma conta, então o Sideloadly assinou de novo com o mesmo identificador e o cofre do
  iPhone (a chave da DeepSeek e o token da ponte) sobreviveu.
- A sessão da conta Apple salva no Sideloadly tinha 6 dias e não serviu: ele abriu a janela
  "Apple ID Authentication" pedindo a senha normal da conta, e recusa senha de app. Depois do
  login, a assinatura consumiu 3 App IDs dos 7 que estavam livres, e o contador ficou em 4.

Caminho B, AltStore (para quem quer renovação automática):

1. Instale o iTunes pelo site da Apple (o da Microsoft Store não serve) e o AltServer no PC.
   O AltServer 1.8.4 pede também o iCloud for Windows, do site da Apple.
2. Ligue o iPhone por cabo, desbloqueie, e toque em "Confiar neste computador" no aparelho.
3. Abra o iTunes uma vez e entre com a conta Apple, para o aparelho aparecer e o "Sincronizar
   por Wi-Fi" ficar disponível, que é o que deixa a renovação acontecer sem cabo.
4. Rode o AltServer como administrador, clique no ícone dele na bandeja, escolha "Install
   AltStore" e o seu aparelho.
5. Informe a conta Apple. Conta com dois fatores pede **senha de app**, gerada em
   appleid.apple.com, e não a senha normal da conta.
6. Autorize o perfil de desenvolvedor como no passo 6 do caminho A, e ligue o Modo de
   Desenvolvedor como no passo 4.
7. Leve o `DSH-livre.ipa` para o aparelho. Não existe AirDrop no Windows; os caminhos que
   funcionam são mandar o arquivo para você mesmo por e-mail ou mensageiro, o iCloud Drive, ou
   servir o arquivo pelo PC na mesma rede Wi-Fi e baixar pelo Safari (um
   `python -m http.server` na pasta do IPA resolve, e o Safari salva em Arquivos).
8. No iPhone, abra o AltStore, aba My Apps, toque em "+" e escolha o `DSH-livre.ipa` baixado.
9. Deixe o AltServer aberto no PC e o iPhone na mesma rede de vez em quando: ele renova a
   assinatura antes dos 7 dias vencerem.

O que o pacote livre perde em relação ao completo: o widget mostrar a última conversa e o
compartilhamento de texto de outro app para o DSH. O ícone do widget continua abrindo as rotas
do app, porque isso é link, não dado compartilhado.

## 6. O que conferir quando algo não abre

| sintoma | causa provável | o que fazer |
|---|---|---|
| app fecha ao abrir | perfil de desenvolvedor não autorizado, ou assinatura vencida | autorizar o perfil nos Ajustes, ou reassinar |
| Sideloadly recusa o arquivo ou o app fecha na abertura com conta gratuita | foi instalado o `DSH.ipa` completo, que tem extensão e App Group | instalar o `DSH-livre.ipa`, que sai na mesma rodada |
| Sideloadly para em 0% com `Can't listdir a file` | o zip do IPA não tem `Payload/` como pasta raiz | gerar o pacote pelo workflow atual, que confere a raiz |
| "Importar chaves do computador" responde que o computador não tem as chaves | o cofre do PC não tem aquele nome, ou a ponte está com a escrita desligada | conferir o cofre da máquina e o `permitirEscrita` do `ponte.json` |
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
  Conversa, Artefatos, Ajustes, Voz, Ferramentas, Plataforma, Widget, Extensao).
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

## 9. Prova de que a ponte responde

O caminho do motor da ponte não é promessa: ele foi medido neste notebook, contra o servidor
que está no ar. O app chama exatamente estas rotas, com `Authorization: Bearer <token>`.

| o que foi testado | como | resultado |
|---|---|---|
| endereço padrão do app (`Preferencias.enderecoDaPontePadrao`) | GET `https://desktop-nvl84h2.tail056d02.ts.net:8443/v1/saude` | HTTP 200, `ok: true`, `rotulo: NOTEBOOK`, `maquina: DESKTOP-NVL84H2`, `dsh.aberto: true` |
| contrato que `ServicoPonte.saude()` lê | mesmos campos `ok`, `rotulo`, `maquina`, `dsh.erro` | todos presentes na resposta |
| listagem usada pela tela de sessões | GET `/v1/sessoes` | HTTP 200 com 37 sessões, cada uma com `id`, `titulo`, `rodando`, `turnos` |
| exposição do servidor | `tailscale serve status` | `https://desktop-nvl84h2.tail056d02.ts.net:8443` encaminha para `http://127.0.0.1:43130`, restrito ao tailnet |
| token e limites | `ponte/ponte.json` | `limiteTexto: 8192`, `prefixo: [ponte NOTEBOOK]`, escrita liberada, 120 requisições por minuto |

Duas consequências práticas:

1. O endereço que vem preenchido de fábrica no app é o do notebook, então quem instala e tem
   Tailscale no iPhone só precisa colar o token. Se a ponte for de outra máquina, o endereço
   muda em Ajustes.
2. O Tailscale precisa estar ativo **no iPhone e no computador**, na mesma tailnet. Sem isso o
   endereço não resolve, e é esse o erro que aparece na conversa.

## 10. O que a última rodada do CI prova

A rodada `45554933068` rodou sobre o commit `6b2803e` e terminou com os dois jobs em `success`,
passo por passo. Os números abaixo saíram do artefato baixado e aberto aqui, não do log do
Actions.

| o que | como foi medido | resultado |
|---|---|---|
| job `simulador` | compilar, instalar no iPhone 16 do simulador e capturar as cinco rotas | `success`, 5 capturas de 1206x2622 |
| widget e extensão de compartilhar | passo próprio, `xcodebuild -target DSHWidget` e `-target DSHCompartilhar` | `success`, os dois alvos compilam |
| job `ipa` | compilar para aparelho sem assinatura e empacotar os dois pacotes | `success`, `DSH.ipa` com 821.846 bytes e `DSH-livre.ipa` com 764.148 bytes |
| pacote livre | listar as entradas do `.ipa` com `zipfile` | 15 entradas e **zero** com `PlugIns`: o pacote é só `Payload/DSH.app` |
| pacote completo | mesma listagem | `DSHWidget.appex` e `DSHCompartilhar.appex` dentro de `Payload/DSH.app/PlugIns/` |
| binário | `Payload/DSH.app/DSH` dentro do IPA | 3.108.192 bytes |
| catálogo de ícones | `Payload/DSH.app/Assets.car` | 32.735 bytes, ou seja, o catálogo compilou e não saiu vazio |
| ícones derivados | PNGs dentro do pacote | `AppIcon60x60@2x.png` com 2.861 bytes e `AppIcon76x76@2x~ipad.png` com 3.500 bytes |
| `Info.plist` do pacote | lido com `plistlib` | `dev.ramses.dsh`, versão `1.0.0` (build `1`), `MinimumOSVersion` 18.0, `DTXcode` 1640, `DTPlatformVersion` 18.5, `Info.plist` com 3.213 bytes |
| ícone ligado ao alvo | `CFBundleIconName` e `CFBundlePrimaryIcon` | `AppIcon`, com `CFBundleIconFiles = [AppIcon60x60]` |

O que cada captura mostra, com o tamanho do arquivo:

| captura | bytes | o que está na tela |
|---|---|---|
| `conversa.png` | 292.172 | o fim de uma resposta, com o bloco de código e dois cartões de artefato: "Relógio de parede" (HTML) e "Relógio em SVG" (SVG) |
| `artefato.png` | 655.115 | o visualizador do artefato HTML rodando o relógio dentro do `WKWebView`, com o ponteiro na hora do relógio do simulador, e o seletor entre Visualização e Código |
| `ajustes.png` | 303.492 | a folha de Ajustes, com o seletor de motor, o cofre da DeepSeek, o endereço e o token da ponte, e as ações de salvar e apagar |
| `dsh.png` | 153.901 | a folha de sessões aberta pela rota `dsh`, no estado sem ponte configurada, que é o estado de fábrica do simulador |
| `voz.png` | 642.677 | a tela de voz no estado ocioso, "Microfone desligado", que é o padrão com a voz automática desligada |

As cinco capturas estão versionadas em `docs/capturas/`, tiradas desta rodada, para não
depender de baixar artefato do Actions para olhar a tela:

![Conversa com os dois cartões de artefato](capturas/conversa.png)

![Visualizador do artefato HTML rodando o relógio](capturas/artefato.png)

![Ajustes com o motor, o cofre e a ponte](capturas/ajustes.png)

O que a rodada **não** prova, para não dar a ela mais peso do que tem:

- nada foi instalado em iPhone físico, e o IPA não é assinado: a rodada mostra que o código
  compila, empacota e roda no simulador, não que o aparelho aceita o arquivo;
- nenhuma captura exercita toque: o app é aberto nas rotas e fotografado, sem digitar, rolar ou
  tocar em botão. Salvar chave, testar conexão e enviar pela ponte continuam verificados só por
  leitura de código;
- a voz capturada é a tela, não o resultado de um reconhecimento: o microfone do simulador é
  permissão dada pelo `simctl`, sem áudio real. O que `voz.png` prova é só o estado ocioso, que
  é o esperado com a preferência de voz automática desligada, o padrão de fábrica;
- o cartão de anexo não aparece em captura nenhuma, porque a conversa de demonstração não tem
  anexo: a troca na bolha está provada pela compilação e pela leitura do código;
- o widget e a extensão de compartilhar compilam, mas não são executados: o simulador roda só o
  app principal, e o App Group que liga os três exige conta paga do programa de desenvolvedor;
- o `DSH-livre.ipa` foi medido por dentro, com `zipfile`, e instalado no aparelho em 25/11/2026
  pelo Sideloadly com conta gratuita: a prova de que ele roda é a mensagem que o app mandou para
  a sessão do DSH pela ponte, registrada na auditoria da ponte às 11:48 UTC daquele dia;
- as capturas são do modo claro do simulador; o modo escuro não é fotografado.

## 11. O que fica aberto

O que está abaixo é conhecido e não escondido. Nenhum item impede usar o app no dia a dia, mas
cada um é uma promessa que o app ainda não cumpre.

| o que | estado | por que não foi feito |
|---|---|---|
| validar a chave da DeepSeek em Ajustes | só confere o prefixo `sk-` | a API não tem rota de validação de chave, e inventar uma custaria uma chamada paga a cada toque |
| bloco de código muito longo | cresce sem limite dentro da bolha | cortar com "mostrar mais" mexe no `TextoRico`, e a conversa de demonstração já usa o limite como prova de rolagem |
| primeiro quadro da resposta ao vivo | o recuo pendente aparece a partir do segundo quadro | o streaming chega em pedaços e o primeiro é renderizado antes de haver linha completa |
| criar sessão pela ponte | `POST /v1/sessoes` e `/mensagem` foram verificados só por leitura de código | a rodada do CI não tem tailnet, então não há como exercitar a ponte de dentro do simulador |
| folha do artefato durante a resposta | pode fechar sozinha quando o texto ao vivo vira mensagem gravada | a bolha ao vivo é substituída no fim do stream, e com ela o estado que segurava a folha |
| widget e compartilhamento no iPhone | exigem conta paga do programa de desenvolvedor | os dois alvos usam App Group, que a conta gratuita não libera; com conta gratuita, o pacote que instala é o `DSH-livre.ipa`, sem as extensões |
| remover anexo no transcrito | a bolha desenha o cartão sem a ação de remover | anexo já enviado não sai da conversa, e o parâmetro `aoRemover` do cartão fica reservado à barra de entrada, que ainda usa as etiquetas dela |
| instalação em iPhone físico | reinstalada em 25/11/2026 às 09:43 pelo Sideloadly com conta gratuita, agora com o build que tem o botão de importar chaves, e o app conversa com o DSH pela ponte | a assinatura vence em 02/12/2026; renovar exige o Sideloadly com o PC e o iPhone na mesma rede |
| importar a chave de busca web | o cofre do PC não tem `TAVILY_API_KEY` nem `BRAVE_API_KEY` | criar uma chave gratuita na Tavily, gravar no cofre do PC e usar o botão de importar, ou colar direto em Ajustes |


