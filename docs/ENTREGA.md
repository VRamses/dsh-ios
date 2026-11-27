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

Anexo entra pela barra de entrada. O clipe abre o seletor de arquivos, que no iPhone é o app
Arquivos e não enxerga a galeria; por isso a foto tem botão próprio, com menu de duas opções: tirar
agora, pela câmera do sistema, ou escolher da galeria. Foto de documento passa por OCR, foto sem
texto ganha o que o classificador de cena reconhece, e, no motor DeepSeek direto, o JPEG da foto
segue dentro do pedido: o modelo vê a imagem em vez de só ler o que o OCR achou nela. Pela ponte,
que transporta texto, a foto chega apenas como texto reconhecido, e o próprio pedido diz isso ao
modelo para ele não responder como se tivesse visto.

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

### A terceira instalação, no SUPERCOLLIDER, em 25/11/2026

Esta é a instalação que levou ao aparelho o build da gaveta de largura toda, do botão
"Testar a chave" e do pareamento por QR.

| o que | como foi medido | resultado |
|---|---|---|
| rodada do CI | `gh run view 45659433505`, commit `b807bb3` | `success` nos dois jobs, 23 passos executados |
| pacote instalado | baixar o artefato `ipa` da rodada | `DSH-livre.ipa` com 781.831 bytes e sha256 `9F364737941004BF4C267E6402A594073625C915888BD123C7120FB1A3513BC7` |
| raiz e conteúdo do pacote | listar as entradas do `.ipa` com `zipfile` | 15 entradas, a primeira é `Payload/`, nenhuma com `PlugIns` |
| binário | `Payload/DSH.app/DSH` dentro do pacote | 3.181.480 bytes, com as strings `Testar a chave`, `pareamento/trocar`, `token salvo no cofre` e `Não consegui trocar o código` presentes |

Duas coisas que esta instalação ensinou:

- Build que morre em segundos, com zero passos, sem log e sem nome de runner não é erro de
  código: é conta sem minutos de Actions. O `dsh-ios` era privado no plano free, e cada minuto
  de macOS consome dez da cota mensal de 2.000; o mês passou disso em 25/11/2026 e o Actions
  recusou alocar runner em sete rodadas seguidas, inclusive numa rodada de prova que só rodava
  `sw_vers`. O repositório virou público no mesmo dia, porque repositório público não consome
  cota, e a rodada seguinte ficou verde em 9 minutos e 46 segundos.
- O pareamento por QR não carrega token: o QR leva `dsh://ajustes?parear=<código>&endereco=<url>`,
  o app troca o código de oito caracteres pelo token em `POST /v1/pareamento/trocar`, e o código
  vale uma vez só, por cinco minutos.

### A quarta instalação, no SUPERCOLLIDER, em 25/11/2026

Esta é a que leva ao aparelho o botão de foto na barra de entrada, com câmera e galeria, e a foto
enviada como imagem no motor DeepSeek direto.

| o que | como foi medido | resultado |
|---|---|---|
| rodada do CI | `gh run view 45736468022`, commit `c8d6863` | `success` nos dois jobs |
| pacote entregue | baixar o artefato `ipa` da rodada e conferir o arquivo | `DSH-livre.ipa` com 808.012 bytes e sha256 `019048F1464D4FE37DC0D1F1B4082D8190866778E121ED50B7CF2A4230B75B22` |
| conteúdo do pacote | listar as entradas com `zipfile` | 15 entradas, nenhuma com `PlugIns`, `dev.ramses.dsh`, versão `1.0.0` (build `1`), mínimo 18.0 |
| uso de câmera e galeria no `Info.plist` | ler o plist do pacote | `NSCameraUsageDescription` e `NSPhotoLibraryUsageDescription` presentes, então o iOS não derruba o app ao abrir a câmera |
| link de download | `curl -I` no endereço do tailnet, servido por `tailscale serve` | HTTP 200, `Content-Length: 808012`, tipo `application/x-itunes-ipa` |
| imagem no pedido | leitura do código de `ServicoDeepSeek.conteudo` | a mensagem com foto vira lista de blocos, com `image_url` em `data:image/jpeg;base64`, só nas duas últimas falas do usuário |
| imagem aceita pela API | pedido de prova direto na API, com um PNG em base64 | HTTP 200 nos dois nomes de modelo que a barra oferece, servidos por `deepseek-flash`, com descrição real da imagem na resposta |

Depois de instalar, o teste é este: abrir uma conversa no motor DeepSeek direto, tocar na câmera,
escolher da galeria uma foto com texto e pedir "o que está escrito aqui". Resposta que descreve o
que está na foto, e não só o texto, é a prova de que a imagem chegou. No motor da ponte o mesmo
pedido recebe só o texto reconhecido, e é assim que tem de ser.

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

### A quinta instalação, no SUPERCOLLIDER, em 25/11/2026

Esta é a rodada que faz o app parar de ficar calado: o commit final é o `9fcd9a4`, e os dois
anteriores que entram nela são o `e7202e8` e o `c303ebd`.

| o que | como foi medido | resultado |
|---|---|---|
| rodada do CI | `gh run view 45739833908`, commit `9fcd9a4` | `success` nos dois jobs |
| pacote entregue | baixar o artefato `ipa` da rodada e conferir o arquivo | `DSH-livre.ipa` com 809.510 bytes e sha256 `46710E20542EBE1CAD5DCC4AE58CE1A9FEC7D0CEC5808AE24C094C9694B8E1C8` |
| conteúdo do pacote | `_tmp\dsh-ios\medir-ipa.py`, com `zipfile` e `plistlib` | 15 entradas, nenhuma com `PlugIns`, `dev.ramses.dsh`, versão `1.0.0` (build `2`), mínimo 18.0, com `NSCameraUsageDescription` e `NSPhotoLibraryUsageDescription` |
| as quatro falas novas dentro do binário | procurar em UTF-8 no `Payload/DSH.app/DSH`, de 3.269.928 bytes | "não mandou nenhum pedaço de texto", "terminou a resposta sem mandar texto nenhum", "interrompida antes de chegar texto" e "Escolher sessão do DSH" presentes |
| link de download | `curl -I` no endereço do tailnet | HTTP 200, `Content-Length: 809510`, `application/x-itunes-ipa` |
| arquivo servido | `_tmp\share\DSH-livre-20261125-build2.ipa` | 809.510 bytes, ao lado do `DSH-livre-20261125-foto.ipa` de 808.012 bytes, que fica para voltar atrás se precisar |

Para saber qual app está no telefone, Ajustes mostra a versão no rodapé: esta rodada é
"1.0.0 (2)", e a anterior era "1.0.0 (1)".

### A sexta instalação, no SUPERCOLLIDER, em 26/11/2026

Esta é a rodada que ataca a resposta vazia do motor direto, com o commit `d04de27`.

| o que | como foi medido | resultado |
|---|---|---|
| rodada do CI | `gh run view 45755780355`, commit `d04de27` | `success` nos dois jobs, 8 minutos e 35 segundos entre disparo e fim |
| pacote entregue | artefato `ipa` da rodada, conferido com `zipfile` e `plistlib` | `DSH-livre.ipa` com 809.862 bytes e sha256 `259A1E797FC5C3607E949129EF0CD41F0D2911232CA1A862A96B0FEF892C56F2` |
| conteúdo do pacote | mesmo conferidor | 15 entradas, nenhuma com `PlugIns`, `dev.ramses.dsh`, versão `1.0.0` (build `3`), mínimo 18.0 |
| falas novas dentro do binário | procurar em UTF-8 no `Payload/DSH.app/DSH`, de 3.269.328 bytes | "a API recusou no meio do stream" e "primeiras linhas" presentes |
| os trechos curtos da mesma frase | mesma procura | "Chave com " e "Resposta: " não aparecem como texto contínuo, e isso não é build velho: os trechos longos da mesma frase aparecem, e literal curto o Swift guarda embutido na instrução em vez de gravar como texto |
| link de download | `curl -I` no endereço do tailnet | HTTP 200, `Content-Length: 809862`, `application/x-itunes-ipa` |
| onde o arquivo está | `C:\Users\victo\iCloudDrive\DSH-livre-20261126-build3.ipa` e `_tmp\share\DSH-livre-20261126-build3.ipa` | mesmo sha256 nos dois, para o aparelho pegar pelo iCloud Drive ou pelo Safari no tailnet |

#### Por que o 200 vinha sem nenhum pedaço de texto

O palpite da rodada anterior era de rede ou de chave. As três medições abaixo, feitas daqui
com o mesmo corpo de pedido que o app monta, trocam o palpite por causa:

| pedido | cabeçalho de compressão | resposta |
|---|---|---|
| corpo do app, chave do cofre | `accept-encoding: identity` | `200`, `content-type: text/event-stream`, **sem** `content-encoding`, corpo legível linha a linha |
| mesmo corpo, mesma chave | `accept-encoding: gzip, deflate, br` | `200`, `content-type: text/event-stream`, **`content-encoding: br`** |
| mesmo corpo, chave inválida | `accept-encoding: identity` | `401` com corpo JSON, `Your api key: ****0000 is invalid` |

Duas conclusões saem daí. A primeira: chave inválida devolve 401, então o 200 que o app
recebeu significa que o pedido dele **passou pela autenticação**, e o problema estava no
corpo. A segunda: a API passou a comprimir o stream quando o cliente aceita compressão, e o
iOS aceita por padrão; o app lê o stream linha por linha e conta os pedaços, e byte comprimido
não vira linha, então o pedido termina com 200 e contador em zero, que é exatamente a
mensagem que aparecia na tela. O build 3 pede `identity` nos dois pedidos, o de conversa e o
do teste da chave, e passa a mostrar as primeiras linhas cruas e o motivo quando o stream
fecha sem texto.

O 401 do teste da chave é outra história, e continua aberta: o texto que o aparelho recebeu
foi `Authentication Fails (governor)`, e chave errada responde `Your api key: ****0000 is
invalid`. São duas recusas diferentes, então não era a chave digitada errado. O teste do
build 3 passou a informar quantos caracteres a chave tem e os quatro últimos dígitos, para a
próxima medição separar chave com caractere invisível de barreira da conta.

Depois de instalar, o teste é este, na ordem: Ajustes tem de mostrar "1.0.0 (3)" no rodapé;
"Testar a chave" tem de dizer o tamanho da chave e os quatro últimos caracteres junto do
HTTP; e uma conversa com "teste" tem de responder, ou então mostrar faixa com o motivo ou
com as primeiras linhas cruas que a API mandou.

## 6. O que conferir quando algo não abre

| sintoma | causa provável | o que fazer |
|---|---|---|
| app fecha ao abrir | perfil de desenvolvedor não autorizado, ou assinatura vencida | autorizar o perfil nos Ajustes, ou reassinar |
| Sideloadly recusa o arquivo ou o app fecha na abertura com conta gratuita | foi instalado o `DSH.ipa` completo, que tem extensão e App Group | instalar o `DSH-livre.ipa`, que sai na mesma rodada |
| Sideloadly para em 0% com `Can't listdir a file` | o zip do IPA não tem `Payload/` como pasta raiz | gerar o pacote pelo workflow atual, que confere a raiz |
| "Importar chaves do computador" responde que o computador não tem as chaves | o cofre do PC não tem aquele nome, ou a ponte está com a escrita desligada | conferir o cofre da máquina e o `permitirEscrita` do `ponte.json` |
| erro de rede no motor da ponte | Tailscale fora, computador desligado, endereço sem `https://` | conferir o tailnet e o endereço salvo nos Ajustes |
| a conversa não responde nada e não aparece faixa de erro | a chave não chegou ao cofre, ou chegou uma resposta 200 sem texto | no build 3 a faixa sempre aparece, com o motivo ou com as primeiras linhas cruas que a API mandou |
| a faixa diz "a API recusou no meio do stream" | a API aceitou a conexão com 200 e recusou dentro do stream, e agora o texto dela aparece | ler a mensagem da faixa: ela é a recusa da própria API, sem tradução |
| a faixa diz "200 e não mandou nenhum pedaço de texto" mesmo no build 3 | o stream chegou, mas em formato que o leitor não reconheceu | as primeiras linhas cruas na faixa dizem qual formato chegou; guardar esse texto antes de qualquer outra mudança |
| a câmera lê o QR mas o app não abre os Ajustes | link sem o esquema `dsh://`, ou app instalado sem o `CFBundleURLSchemes` deste build | conferir se o QR começa com `dsh://ajustes?parear=` e instalar o build de 25/11/2026 ou mais novo |
| o QR dá código inválido | o código vale uma vez só, por cinco minutos, e o pareamento anterior já o consumiu | gerar outro QR no computador: `node _tmp\ponte\qr-pareamento.mjs` |
| motor direto responde 401 | chave errada, revogada, ou barreira da conta, que responde `Authentication Fails (governor)` em vez de `Your api key ... is invalid` | conferir o tamanho e os quatro últimos caracteres que o teste do build 3 informa, e colar a chave de novo em Ajustes |
| widget abre mas não mostra conversa | App Group indisponível na conta gratuita | comportamento esperado, ver item 4 |
| captura de tela em branco no artefato | a rota não existe ou o app não chegou a abrir | ler o `console.txt` e o log de compilação |

### O print sem resposta, de 25/11/2026 às 22:26

O print mostra duas falas do usuário ("Isso é um teste" e "Isso é um"), nenhuma
resposta, nenhuma faixa de erro, e a seta no canto da barra em vez do quadrado de
parar. Cada um desses sinais foi conferido no código e no que a máquina registrou:

| o que o print mostra | como foi lido | o que prova |
|---|---|---|
| seta, e não quadrado | `BarraDeEntrada.swift`, `botaoPrincipal`: o glifo é `stop.fill` quando `estaRespondendo` é verdadeiro e `arrow.up` quando é falso | o pedido já tinha terminado quando o print foi tirado |
| nenhuma linha "Escrevendo" e nenhum cartão de raciocínio | `BolhaDeMensagem.swift`: com a resposta ao vivo e texto vazio, a bolha mostra `trabalhoEmCurso` | não havia pedido em andamento |
| rótulo "DeepSeek raciocínio" na barra | `BarraDeEntrada.swift`, `rotuloDoModelo`: "Sessão DSH" quando há sessão escolhida | nenhuma sessão do DSH estava selecionada, então não era o motor da ponte por escolha |
| `ponte.log` das 22:24 às 22:35 | pareamento às 22:24:59 e 22:25:24, `GET /v1/saude` 200 às 22:25:32, e nenhum `POST /v1/sessoes/.../mensagem` perto das 22:26 | a mensagem do aparelho não passou pela ponte |
| os três `POST` de 22:32:00, 22:32:07 e 22:34:21 | foram para a sessão `48647d58`, "Rebobina": o transcrito dela (3.471 quadros, 6.397 linhas) não tem "Isso é um" em lugar nenhum | aqueles pedidos não eram os do aparelho |
| o mesmo pedido feito daqui | `deepseek-reasoner`, com `stream`, `max_tokens` 4096 e `stream_options` | HTTP 200, 81 linhas de SSE, texto e raciocínio presentes, servido por `deepseek-flash`: rota e nome de modelo estão certos |

Sobrou então o motor direto, e nele toda falha previsível aparecia: chave faltando,
chave recusada, rede fora e HTTP de erro desembocam em `ErroDaConversa`, que sempre
tem descrição em português e vira faixa na tela. As saídas caladas estavam todas no
próprio app, e a terceira delas é a que mais combina com o horário do print:

- a faixa era apagada toda vez que a tela da conversa reaparecia, porque
  `abrir(_:)` fazia `erro = nil` sem olhar se era a mesma conversa. O pareamento
  tinha acabado de acontecer (22:24 a 22:25); se o aviso apareceu quando a mensagem
  foi mandada e o usuário foi aos Ajustes conferir chave ou motor, a volta apagava o
  aviso e sobrava a pergunta sem resposta. O commit `c303ebd` mantém a falha
  visível ao voltar para a mesma conversa;
- um 200 que termina sem nenhum pedaço de texto: o commit `e7202e8` fez
  `ServicoDeepSeek` contar os pedaços e lançar erro se não veio nenhum, e
  `ServicoPonte` fazer o mesmo quando os eventos fecham sem texto;
- parada antes do primeiro pedaço: o `catch is CancellationError` era vazio e o
  salvamento era condicionado a `!resposta.isEmpty || !pensamento.isEmpty`, então
  parar cedo não deixava rastro. Agora o fim sem texto sempre vira faixa dizendo
  que nada foi guardado.

O `c303ebd` também trocou "nenhuma sessão da ponte está aberta" por uma frase que
diz onde resolver: o motor da ponte precisa de uma sessão do DSH escolhida no
seletor da barra de baixo, e essa é a falha que aparece para quem liga o motor da
ponte antes de escolher a sessão.

O que não dá para medir daqui: se o aparelho chegou a falar com a API naquele
minuto, porque o app não guarda registro do último pedido. O build 2 do
`project.yml` aparece em Ajustes como "1.0.0 (2)" e serve para saber qual app está
no telefone.

## 7. Estado do repositório

- `docs/CONTRATO-SWIFT.md`: contrato técnico do time, é a fonte de verdade dos tipos.
- `docs/REFERENCIAS.md`: as referências visuais usadas na interface.
- `docs/ENTREGA.md`: este documento.
- `project.yml`: geração do projeto Xcode com XcodeGen, três alvos.
- `.github/workflows/ios.yml`: a compilação no Actions, com os jobs `simulador` e `ipa`.
- `Fontes/`: o código, separado por assunto (App, Nucleo, Provedores, Compartilhado, Desenho,
  Conversa, Artefatos, Ajustes, Voz, Ferramentas, Plataforma, Widget, Extensao).
- `Recursos/`: os três `Info.plist`, os três `.entitlements` e o catálogo `Assets.xcassets`.
- Visibilidade: o repositório é **público** desde 25/11/2026. Era privado, e a cota mensal de
  2.000 minutos do plano free acabou no meio dos builds de macOS, que contam dez vezes; com o
  repositório público o Actions não consome cota. Antes de tornar público, o histórico inteiro
  (27 commits) foi varrido por `sk-`, `ghp_`, `AKIA`, chave privada e `Bearer` com 20 caracteres
  ou mais, e não há segredo vivo em nenhum deles. O que o repositório expõe são nomes de máquina
  do tailnet, que só respondem para quem está na tailnet.

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

## 10. O que a rodada do CI prova

A rodada `45554933068` rodou sobre o commit `6b2803e` e terminou com os dois jobs em `success`,
passo por passo. É a rodada que produziu as capturas e as medidas de pacote abaixo. A rodada mais
nova, `45736468022` sobre `c8d6863`, também fechou verde nos dois jobs e é a que trouxe a foto da
câmera e da galeria na barra de entrada; é dela que sai o `DSH-livre-20261125-foto.ipa`. Os números
abaixo saíram do artefato baixado e aberto aqui, não do log do Actions.

| o que | como foi medido | resultado |
|---|---|---|
| job `simulador` | compilar, instalar no iPhone 16 do simulador e capturar as cinco rotas | `success`, 5 capturas de 1206x2622 |
| widget e extensão de compartilhar | passo próprio, `xcodebuild -target DSHWidget` e `-target DSHCompartilhar` | `success`, os dois alvos compilam |
| job `ipa` | compilar para aparelho sem assinatura e empacotar os dois pacotes | `success`, `DSH.ipa` com 865.860 bytes e `DSH-livre.ipa` com 808.012 bytes |
| pacote livre | listar as entradas do `.ipa` com `zipfile` | 15 entradas e **zero** com `PlugIns`: o pacote é só `Payload/DSH.app` |
| pacote completo | mesma listagem | `DSHWidget.appex` e `DSHCompartilhar.appex` dentro de `Payload/DSH.app/PlugIns/` |
| binário | `Payload/DSH.app/DSH` dentro do IPA | 3.108.192 bytes |
| catálogo de ícones | `Payload/DSH.app/Assets.car` | 32.735 bytes, ou seja, o catálogo compilou e não saiu vazio |
| ícones derivados | PNGs dentro do pacote | `AppIcon60x60@2x.png` com 2.861 bytes e `AppIcon76x76@2x~ipad.png` com 3.500 bytes |
| `Info.plist` do pacote | lido com `plistlib` | `dev.ramses.dsh`, versão `1.0.0` (build `1`), `MinimumOSVersion` 18.0, com `NSCameraUsageDescription` e `NSPhotoLibraryUsageDescription` presentes |
| ícone ligado ao alvo | `CFBundleIconName` e `CFBundlePrimaryIcon` | `AppIcon`, com `CFBundleIconFiles = [AppIcon60x60]` |

O que cada captura mostra, com o tamanho do arquivo:

| captura | bytes | o que está na tela |
|---|---|---|
| `conversa.png` | 294.516 | o fim de uma resposta, com o bloco de código, dois cartões de artefato e, na barra de entrada, o seletor de modelo, **o ícone de câmera**, o clipe e o botão de enviar |
| `artefato.png` | 660.904 | o visualizador do artefato HTML rodando o relógio dentro do `WKWebView`, com o ponteiro na hora do relógio do simulador, e o seletor entre Visualização e Código |
| `ajustes.png` | 282.198 | a folha de Ajustes do build 5: a linha de estado do motor com o ícone de raio, o seletor de motor, o cofre da DeepSeek e, no começo da seção da ponte, a linha **Ler QR do computador** com o ícone de leitor |
| `dsh.png` | 166.372 | a folha de sessões aberta pela rota `dsh`, no estado sem ponte configurada, que é o estado de fábrica do simulador |
| `voz.png` | 645.380 | a tela de voz no estado ocioso, "Microfone desligado", que é o padrão com a voz automática desligada |

As cinco capturas foram trocadas nesta rodada pelas do build 5 e estão versionadas em
`docs/capturas/`, para não depender de baixar artefato do Actions para olhar a tela. As duas
linhas novas de Ajustes aparecem em `ajustes.png`; o leitor de QR aberto não aparece em captura
nenhuma, porque o simulador não tem câmera com imagem nem QR na frente dela.

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

### A sétima instalação, no SUPERCOLLIDER, em 26/11/2026

Esta é a rodada que faz o texto aparecer no iPhone e oferece sessão nova, com os commits
`e419473` (código) e `b441f55` (número do build).

| o que | como foi medido | resultado |
|---|---|---|
| rodada do CI | `gh run view 45759731050`, commit `b441f55` | `success` nos dois jobs |
| pacote entregue | artefato `ipa` da rodada, conferido com `zipfile` e `plistlib` | `DSH-livre.ipa` com 823.706 bytes e sha256 `65915399A4020CAB2753D355D1471EA8B0F7D184DD719B76B730EE27ABE2EADD` |
| conteúdo do pacote | mesmo conferidor | 15 entradas, nenhuma com `PlugIns`, `dev.ramses.dsh`, versão `1.0.0` (build `4`), mínimo 18.0 |
| código novo dentro do binário | procurar em UTF-8 no `Payload/DSH.app/DSH`, de 3.325.064 bytes | `x-api-key`, `Nova sess`, `caractere invis`, `descartou o cabe` e `chaveParaCabecalho` presentes, e esse código foi escrito nesta rodada |
| onde o arquivo está | `C:\Users\victo\iCloudDrive\DSH-livre-20261126-build4.ipa` e `_tmp\share\DSH-livre-20261126-build4.ipa` | mesmo sha256 nos dois |
| link pelo tailnet | `curl -I` em `/share/DSH-livre-20261126-build4.ipa` na porta 8443 | 401, porque a porta 43141 que servia esse arquivo não está de pé nesta rodada; o caminho que vale aqui é o iCloud Drive |

Ajustes passa a mostrar "1.0.0 (4)" no rodapé.

#### A ponte parou de mandar quadro que o app não lê

O app só entende registro com `tipo`, `em` e `dados`; a ponte mandava os quadros nativos do DSH
(`assistant-stream`, `event`, `snapshot`). O texto chegava ao telefone e era descartado, e como
o stream ficava aberto, a tela ficava em "escrevendo" para sempre. A rota
`/v1/sessoes/<id>/eventos` agora acumula texto e raciocínio e manda, a cada pedaço, um registro
`{"tipo":"assistant"|"raciocinio","em":<ms>,"dados":{"content":[...]}}`, no formato que
`ServicoPonte.coletar` lê, e encerra a resposta no fim do turno.

Prova com um turno real na ponte, sem o telefone, pelo script `_tmp\ponte\teste-turno.mjs`:

| ponto | o que chegou |
|---|---|
| abertura | `aberto` com o id da sessão |
| texto | `mensagem` com `{"type":"text","text":"ok"}` |
| fim | o stream fechou depois de dois quadros, que é o que faz o app gravar a mensagem e parar o indicador |

#### Por que o 401 no teste da chave era falta de cabeçalho

A mensagem que o telefone mostrava, `Authentication Fails (governor)`, não é mensagem de chave
inválida. A matriz abaixo foi medida daqui, contra `api.deepseek.com/chat/completions`, com a
mesma chave do cofre:

| variação do pedido | resposta |
|---|---|
| chave certa em `Authorization: Bearer` | 200 |
| mesma chave, mesmo valor, no cabeçalho `x-api-key` | 200 |
| sem cabeçalho de autenticação nenhum | 401 `Authentication Fails (governor)` |
| chave sem a palavra `Bearer` | 401 `auth header format should be Bearer sk-...` |
| chave com espaço no fim, depois de `Bearer` | 200 |
| quatro pedidos seguidos em menos de um segundo | 200 nos quatro, sem limite por rajada |

Ou seja: o pedido que sai do iPhone chega na API sem cabeçalho nenhum. O build 4 filtra a chave
para ASCII visível antes de montar o cabeçalho, diz no relatório quantos caracteres saíram e,
quando o `Authorization` falha, repete a chamada com a mesma chave em `x-api-key`. Como a API
aceita os dois, um 200 na segunda tentativa prova que o iOS descartou o cabeçalho no caminho.

#### Criar sessão nova, que não existia

`ServicoPonte.criarSessao()` existia desde o build 1 e não tinha uma única chamada no app: a
folha de sessões só listava o que estava aberto no computador, então quem não tinha sessão
aberta não tinha como começar conversa pelo iPhone. A folha ganhou o botão **Nova sessão no
DSH**, que chama a ponte, cria a sessão no grupo padrão e já abre a conversa nela.

A rota foi exercitada daqui antes do build: `POST /v1/sessoes` devolveu 200 com
`sessionId: session-f275c087-aeac-48ac-ade4-96af0cdbdb27`, no grupo `d0d03372-...` (Notebook),
e essa sessão aceitou prompt em seguida.

### A oitava instalação, no SUPERCOLLIDER, em 26/11/2026

Esta rodada responde a três perguntas que sobraram da sétima: o seletor de Motor não mudava nada
visível, o QR de pareamento só podia ser lido pela câmera do sistema, e a sessão escolhida sumia
quando o app era fechado. O commit do código e do número do build é `3ea4205`, e a rodada do CI
é a `45855692673`.

#### O seletor de Motor passou a dizer qual motor está respondendo

A causa de "não muda nada" não estava no seletor, e sim em quem o lia: `TelaPrincipal.configurar()`
decide `usandoPonte = preferencias.usaPonte && sessaoEscolhida != nil`. Sem sessão escolhida, marcar
Ponte não tem efeito nenhum, e a conversa segue na DeepSeek direta sem avisar. Ligar o seletor à
força não resolveria, porque a ponte responde por sessão e não tem para onde mandar sem uma.

A seção Motor ganhou uma linha de estado acima do seletor, desenhada a partir das duas condições
reais (`usaPonte` e a sessão aberta), com três casos:

| estado real | o que a linha mostra |
|---|---|
| DeepSeek direto | `Respondendo pela DeepSeek direta, com a chave deste iPhone.` e o ícone de raio em cinza |
| Ponte marcada, sem sessão | `Ponte marcada, nenhuma sessão aberta: a conversa responde pela DeepSeek direta até você escolher uma sessão.`, ícone de exclamação em âmbar, e o botão **Abrir Sessões do DSH**, que fecha Ajustes e abre a folha de sessões |
| Ponte com sessão | `Respondendo pela ponte do DSH, na sessão <título>.`, ícone de antena em verde |

O botão espera 400 ms antes de abrir a folha, que é o que impede as duas folhas de se atropelarem,
e a pendência passa por `PendenciaDeTela`, um sinalizador de uma linha em `Fontes/Nucleo` que a tela
de conversa consome no `onChange` de `ajustesAbertos`.

#### O QR passou a ser lido dentro de Ajustes

Antes, o único caminho era a câmera do sistema abrir `dsh://ajustes?parear=...`, e quem estava em
Ajustes tinha de sair do app para ler o código. Agora a seção da ponte começa com **Ler QR do
computador**, que abre uma folha com a câmera e lê o código ali mesmo.

`Fontes/Plataforma/LeitorDeQR.swift` embrulha o `AVCaptureSession` com saída de metadados `.qr`, do
mesmo jeito que `CapturaDeFoto.swift` embrulha o `UIImagePickerController`: nenhuma biblioteca de
terceiro entra no projeto por causa disso. A folha tem moldura de mira, quadro preto, fecha no X de
44 pt, para a sessão de captura quando sai da tela e, se o QR não for um pedido de pareamento
válido, mostra o motivo e reinicia a câmera em vez de ficar parada no mesmo quadro. O
`NSCameraUsageDescription` já existia desde o build 1.

O caminho de digitar continua na mesma seção, abaixo do botão, sem mudança de rota.

#### A sessão escolhida sobrevive ao fechamento do app

`Preferencias` ganhou `sessaoDaPonte` e `tituloDaSessaoDaPonte`, gravados no `UserDefaults` como as
outras preferências, para o app reabrir na mesma sessão em vez de voltar calado para a DeepSeek
direta. `sessaoAbertaAgora` é só de memória, de propósito: ele diz o que está valendo nesta execução,
e a linha de estado acima é o que informa quando a ponte está marcada e a sessão não está aberta.

#### A conta do que mudou

| o que | como foi medido | resultado |
|---|---|---|
| rodada do CI | `gh run view 45855692673`, commit `3ea4205` | `success` nos dois jobs |
| pacote entregue | artefato `ipa` da rodada, conferido com `zipfile` e `plistlib` | `DSH-livre.ipa` com 863.872 bytes e sha256 `E95C1985C510EDEA2CBCD3FCABDDEA2FC54068D564F4D7654779D22C052641D9` |
| conteúdo do pacote | mesmo conferidor | 15 entradas, nenhuma com `PlugIns`, `dev.ramses.dsh`, versão `1.0.0` (build `5`), mínimo 18.0 |
| código novo dentro do binário | procurar em UTF-8 no `Payload/DSH.app/DSH`, de 3.545.088 bytes | `LeitorDeQR`, `qrcode.viewfinder`, `Ler QR do computador`, `PendenciaDeTela`, `abrirSessoes`, `marcarSessaoAberta`, `sessaoDaPonte` e `Respondendo pela ponte` presentes |
| onde o arquivo está | `C:\Users\victo\iCloudDrive\DSH-livre-20261126-build5.ipa` e `_tmp\share\DSH-livre-20261126-build5.ipa` | mesmo sha256 nos dois |
| link pelo tailnet | `curl -I` em `https://supercollider.tail056d02.ts.net:8444/DSH-livre-20261126-build5.ipa` | 200 com `Content-Length: 863872` e `Content-Type: application/x-itunes-ipa`; a porta 8444 repassa para o `python -m http.server 43141`, que serve `_tmp\share` e precisa estar de pé para o link valer |

Ajustes passa a mostrar "1.0.0 (5)" no rodapé.

O que esta rodada **não** prova: nada foi instalado no aparelho ainda, e a câmera do simulador não
tem QR para ler. O que está provado é que o código compila, que ele está dentro do binário e que a
tela de Ajustes abre no simulador com a linha de estado e o botão novos.

### A nona instalação, no SUPERCOLLIDER, em 26/11/2026

O pedido desta rodada foi curto: "quero que conectar com outras instâncias seja mais fácil". O app
guardava um endereço e um token, e só eles: parear com o notebook apagava o SUPERCOLLIDER, e voltar
exigia digitar endereço e token de novo. Esta rodada transforma esses dois campos soltos numa lista
de computadores, e aproveita para pôr na bolha o que faltava de leitura da resposta: copiar, refazer
e o tamanho do contexto.

#### Vários computadores, com o token de cada um

`Fontes/Nucleo/Instancias.swift` guarda a lista em `UserDefaults` (`dsh.instancias`), o identificador
do computador em uso (`dsh.instanciaAtiva`) e o token de cada um numa conta própria do Keychain,
`ponte.token.<uuid>`. O endereço é público dentro do tailnet e por isso pode ficar em `UserDefaults`;
o token nunca sai do cofre.

A decisão que manteve o resto do app intacto: **a instância em uso continua sendo dona dos dois
campos antigos**. Trocar de computador copia o endereço para `Preferencias.enderecoDaPonte` e o token
para a conta `ponte.token`, que é exatamente o que `ServicoPonte.aPartirDasPreferencias()` lê. Nenhum
serviço, nenhuma tela de conversa e nenhuma chamada da ponte precisou saber que existe uma lista.

O espelho é delicado por um motivo: `Preferencias.enderecoDaPonte` ganhou um `didSet` que avisa a
lista, para endereço digitado em Ajustes virar o endereço do computador em uso em vez de um campo
solto. Sem cuidado, a própria troca de instância passaria por esse aviso e seria desfeita. Por isso
`Instancias.ativar` liga um sinalizador (`aplicandoAtivacao`) em volta da escrita, e o aviso ignora
o que vem de lá.

Três situações de quem já usava o app são consertadas na abertura de Ajustes, em
`sincronizarComPreferencias`: lista vazia com endereço e token salvos vira a primeira instância, com
o token migrado para a conta dela; instância ativa apontando para identificador que não existe mais
passa para a primeira da lista; lista vazia sem endereço não inventa nada.

#### A seção Computadores, em Ajustes

A seção nova fica entre DeepSeek e Ponte, com uma linha por computador: nome, endereço, marca de
visto no que está em uso e, quando falta token, o aviso em vermelho de que é preciso parear de novo.
Tocar na linha troca o computador e testa a conexão na hora, para a troca não ser uma promessa
silenciosa. Deslizar para a esquerda oferece **Esquecer**, com confirmação, porque a ação apaga o
token do cofre: voltar exige parear outra vez.

O botão **Adicionar pela câmera** é o antigo "Ler QR do computador", que saiu da seção da ponte e
passou a ser a ação de acrescentar computador, que é o que ele faz. A seção da ponte continua com o
caminho de digitar endereço e token, agora como edição do computador em uso.

O nome que aparece na linha não é chute: `/v1/pareamento/trocar` já devolvia `rotulo` e `maquina`, e
`ServicoPonte.trocarCodigo` passou a devolver os dois. `maquina` é o `COMPUTERNAME` do computador
(`SUPERCOLLIDER` no PC desta entrega), e é ele que a lista mostra.

#### Trocar de computador dentro de Sessões do DSH

Escolher sessão e escolher computador são a mesma decisão, e a folha de sessões listava as sessões de
um computador sem dizer qual. O cabeçalho da folha passou a mostrar o computador da lista e, quando
há mais de um, abre um menu para trocar ali mesmo: a troca põe a instância em uso, atualiza a ponte
do modelo e recarrega a lista de sessões.

#### Copiar, refazer e o gasto de contexto

A resposta do assistente ganhou uma linha de ações abaixo do texto, com altura de 44 pontos:

| ação | o que faz |
|---|---|
| copiar | põe a resposta no `UIPasteboard` e troca o ícone por um visto por 1,6 s |
| refazer | só na última resposta: apaga o que veio depois da última fala do usuário e manda a mesma pergunta de novo, sem gravar a pergunta outra vez |
| gasto | `Contexto 1.284 · 312 de saída`, quando a API mandou os números |

O refazer existe só na última porque refazer uma resposta do meio deixaria as seguintes falando de
uma conversa que não existe mais. O gasto vem do campo `usage` da DeepSeek: `prompt_tokens` da
última volta, que é o tamanho real do contexto, e `completion_tokens` somado nas até três voltas de
ferramenta. A ponte não manda esse número, então pela ponte a linha não aparece, em vez de aparecer
zerada.

#### A descrição da câmera dizia outra coisa

`NSCameraUsageDescription` falava só da foto anexada, e o leitor de QR usa a mesma permissão desde o
build 5. A frase passou a citar as duas coisas: a foto que vai para o assistente e o QR que liga este
iPhone ao DSH do computador.

#### A conta do que mudou

| o que | como foi medido | resultado |
|---|---|---|
| rodada do CI | `gh run view 45880010423`, commit `8f4db8e` | os dois jobs verdes, `Simulador e capturas` em 8 min 46 s |
| primeira tentativa desta rodada | `gh run view 45879769836`, commit `578d885` | vermelha: `error: cannot use mutating member on immutable value: 'partes' is a 'let' constant` em `BolhaDeMensagem.swift`; consertado com `var partes` no commit seguinte |
| pacote entregue | artefato `ipa` da rodada, conferido com `zipfile` e `plistlib` | 925.188 bytes, sha256 `8936DEA2F0FA5614BCCE295F0AD2F8C2595D0C549805706E77085956AA4D7BE8` |
| conteúdo do pacote | mesmo conferidor | 15 entradas, `dev.ramses.dsh`, versão `1.0.0` build `6`, mínimo 18.0, sem `PlugIns` |
| código novo dentro do binário | procurar em UTF-8 no `Payload/DSH.app/DSH` (3.770.368 bytes) | presentes: `Instancias`, `aplicandoAtivacao`, `linhaDoComputador`, `sincronizarComPreferencias`, `repetirUltimaResposta`, `tokensDeEntrada`. Textos curtos de interface não aparecem como UTF-8 contíguo no binário (`Esquecer` e `Contexto` deram ausente, `Adicionar pela câmera` deu presente), então essa busca serve para símbolo, não para frase de tela |
| onde o arquivo está | `C:\Users\victo\iCloudDrive\DSH-livre-20261126-build6.ipa` e `_tmp\share\DSH-livre-20261126-build6.ipa` | mesmo sha256 nos dois |
| link pelo tailnet | `curl -I` em `https://supercollider.tail056d02.ts.net:8444/DSH-livre-20261126-build6.ipa` | 200, `Content-Length: 925188`, `Content-Type: application/x-itunes-ipa`, servido pelo `python -m http.server 43141` que precisa estar de pé |
| telas no simulador | artefato `simulador` da mesma rodada, cinco PNG | a seção **Computadores** aparece com o computador da lista, o endereço truncado no meio e o aviso vermelho de token faltando; a resposta termina com copiar e, na última, refazer |

O pacote está com `CFBundleShortVersionString` 1.0.0 e `CFBundleVersion` 6, que é o par que a seção
Sobre de Ajustes imprime a partir do `Bundle.main`: "1.0.0 (6)".

O que esta rodada **não** prova: nada foi instalado no aparelho ainda; o QR não foi lido com a câmera
do iPhone, e a troca entre dois computadores não foi exercitada com os dois ligados. O que está
provado é que o código compila nos dois jobs, que ele está dentro do binário e que as telas abrem no
simulador.

### A décima instalação, no SUPERCOLLIDER, em 26/11/2026

Esta rodada ataca o erro que a tela mostrou às 17:41 de 26/11/2026, com o motor no DeepSeek direto:
"Falha de rede: a API respondeu 200 e não mandou nenhum pedaço de texto". O app estava no build 6, e
a frase saiu sem nenhum dos complementos que o build 3 já sabia escrever (motivo, primeiras linhas),
o que significa zero quadro reconhecido, não texto truncado.

| o que | como foi medido | resultado |
|---|---|---|
| mesmo corpo que o app monta, chave do cofre | `curl` com `Accept-Encoding: identity` | `200`, `text/event-stream`, **sem** `content-encoding`, 8 linhas e 4 com `data:` |
| mesmo corpo e mesma chave | `curl` com `Accept-Encoding: gzip, deflate, br` | `200`, `content-encoding: br`, 8 linhas e **nenhuma** com `data:` |
| corpo com `stream_options`, `temperature` e `max_tokens` | duas variantes acima | o corpo do app não muda a resposta: quem muda é o cabeçalho |
| leitura do stream no app | `Fontes/Provedores/ServicoDeepSeek.swift`, build 6 | `sessao.bytes(for:)` seguido de `bytes.lines`, com `Accept-Encoding: identity` escrito à mão na requisição |

A leitura dessas quatro linhas: o servidor comprime quando o cliente aceita compressão, e o
`URLSession` cuida desse cabeçalho por conta própria, então o `identity` escrito à mão não sobrevive
até a rede. Pior: `bytes(for:)` entrega o corpo como veio, sem descomprimir, mesmo quando foi o
próprio `URLSession` quem pediu a compressão. O app recebia brotli, o leitor de linhas não achava
nenhum `data:` e o contador de pedaços fechava em zero. A correção da rodada anterior, que só trocou
o cabeçalho, não podia funcionar por isso.

| o que mudou | onde | por quê |
|---|---|---|
| leitura por delegação do `URLSession` | `Fontes/Provedores/LeitorDeLinhas.swift`, novo | a delegação recebe `didReceive data` já descomprimido pelo sistema, que é o único jeito de ler SSE comprimido sem trazer biblioteca de brotli para dentro do app |
| o leitor entrega cabeçalho e linha | mesmo arquivo, `EventoDoCorpo` | a resposta fora do 200 é decidida com o código HTTP em mãos, e o corpo do erro é lido até o fim antes de virar exceção |
| erro com pistas | `ServicoDeepSeek.swift` | o 200 sem texto passou a dizer quantas linhas chegaram, o `Content-Type` e o `Content-Encoding`, que é o que separa corpo vazio de corpo comprimido na próxima vez |
| o `identity` saiu dos dois pedidos | conversa e teste da chave | deixar o `URLSession` negociar é o que garante a descompressão |

#### A conta do que mudou

| o que | como foi medido | resultado |
|---|---|---|
| rodada do CI | `gh run view 45894639199`, commit `29c443b` | `success` nos dois jobs; a rodada `45893140844`, do commit `cfee370`, ficou superseded por esta |
| pacote entregue | artefato `ipa` da rodada, conferido com `zipfile` e `plistlib` | `DSH-livre.ipa` com 930.735 bytes e sha256 `B37866ED53EB983BA844BDDF309229CBFDB7EE5894637B3D1AAB8147634611DD` |
| conteúdo do pacote | mesmo conferidor | 15 entradas, nenhuma com `PlugIns`, `dev.ramses.dsh`, versão `1.0.0` build `7`, mínimo 18.0 |
| binário | tamanho de `Payload/DSH.app/DSH` | 3.795.976 bytes, 20.608 a mais que o build 6, que é o leitor novo |
| onde o arquivo está | `C:\Users\victo\iCloudDrive\DSH-livre-20261126-build7.ipa` e `_tmp\share\DSH-livre-20261126-build7.ipa` | mesmo sha256 nos dois |
| link pelo tailnet | `curl -I` em `https://supercollider.tail056d02.ts.net:8444/DSH-livre-20261126-build7.ipa` | 200, `Content-Length: 930735`, `application/x-itunes-ipa` |

Depois de instalar, Ajustes tem de mostrar "1.0.0 (7)" no rodapé, e a conversa com o motor DeepSeek
direto tem de responder. Se voltar a falhar, a faixa agora carrega a contagem de linhas e a
codificação, e é essa linha que diz se o corpo veio vazio ou comprimido.

O que esta rodada **não** prova: nada foi instalado no aparelho ainda. A prova é de compilação nos
dois jobs, de conteúdo do pacote e da medição da API feita daqui com a mesma chave e o mesmo corpo.

### A décima primeira instalação, no SUPERCOLLIDER, em 26/11/2026

Esta rodada ataca a frase que a tela mostrou às 18:14 de 26/11/2026, já com o build 7 instalado e o
motor na ponte (o item SUPERCOLLIDER do seletor): "Não deu para responder. Falha de rede: a sessão
do DSH fechou os eventos sem devolver texto". A frase é do caminho da ponte, não do DeepSeek direto,
e nasce quando o stream de eventos termina sem nenhum pedaço de texto nem de raciocínio.

O log da ponte entregou o caso inteiro, com as duas tentativas do aparelho:

| quando | o que a ponte registrou |
|---|---|
| 21:14:42Z | `eventos -> session-94f30e75...: 123 quadros, 0 chars de texto, 1253 de raciocinio, fechou por fim do turno (end)` |
| 21:14:48Z | `eventos -> session-94f30e75...: 11 quadros, 0 chars de texto, 1000 de raciocinio, fechou por fim do turno (end)` |

Aquela sessão é esta conversa do computador, aberta e respondendo na hora do teste. O app tinha
adotado a sessão que já existia na lista e mandado a pergunta para dentro dela. Sessão ocupada
fecha o turno e o texto vai para a conversa que já estava rodando, então o iPhone recebia quadro de
raciocínio e nenhum de texto. Não era falha de rede nem de token: era a pergunta caindo na conversa
de outra pessoa.

| o que | como foi medido | resultado |
|---|---|---|
| a ponte responde numa sessão nova | `POST /v1/sessoes` seguido de mensagem e da leitura de `/eventos`, feito daqui com o token da ponte | sessão `session-265bee03...`, quadro `assistant` com o texto `pronto` em 2.035 ms, 2 quadros no total |
| a sessão nova não herda conversa | mesma leitura | o stream abre com `event: aberto` e fecha logo depois do `assistant`, sem quadro de ninguém |
| a ponte recusa código já usado | `POST /v1/pareamento/trocar` duas vezes com o mesmo código | primeira devolve o token da ponte, segunda responde 404 |

| o que mudou | onde | por quê |
|---|---|---|
| sessão criada sozinha no primeiro envio | `Fontes/Conversa/ConversaViewModel.swift`, `executarEnvio` | com o motor da ponte e sem sessão escolhida, o app chama `POST /v1/sessoes` e usa a sessão que voltou, em vez de parar e mandar o usuário escolher na lista |
| erro que ensina a saída | `Fontes/Provedores/ServicoPonte.swift` | o texto do stream vazio passou a dizer que a sessão pode estar respondendo no computador e que a saída é criar uma sessão nova pelo nome do modelo |
| versão | `project.yml` | `CURRENT_PROJECT_VERSION` de 7 para 8 |

#### A conta do que mudou

| o que | como foi medido | resultado |
|---|---|---|
| rodada do CI | `gh run view 45897097854`, commit `0634b19` | `success` nos dois jobs, "IPA sem assinatura" e "Simulador e capturas" |
| pacote entregue | artefato `ipa` da rodada, conferido com `zipfile` e `plistlib` | `DSH-livre.ipa` com 931.439 bytes e sha256 `CD14B28F46C61D4761ECDCE02D7E58071A2A5D2F7D08B4B2E60BF4D1FFBE9716` |
| conteúdo do pacote | mesmo conferidor | 15 entradas, nenhuma com `PlugIns`, `dev.ramses.dsh`, versão `1.0.0` build `8`, mínimo 18.0 |
| binário | `file_size` de `Payload/DSH.app/DSH` no `zipfile` | 3.796.544 bytes, 568 a mais que os 3.795.976 do build 7, que é o código novo |
| onde o arquivo está | `C:\Users\victo\iCloudDrive\DSH-livre-20261126-build8.ipa` e `_tmp\share\DSH-livre-20261126-build8.ipa` | mesmo sha256 nos dois |

Depois de instalar, Ajustes tem de mostrar "1.0.0 (8)" no rodapé. Com o motor na ponte, a primeira
mensagem cria uma sessão só do iPhone e ela responde; com o motor no DeepSeek direto, a resposta vem
pelo stream descomprimido do build 7.

O que esta rodada **não** prova: nada foi instalado no aparelho ainda. A prova é de compilação nos
dois jobs, do conteúdo do pacote e da resposta da ponte medida daqui com a mesma sessão nova que o
app passa a criar.

### A décima segunda instalação, no SUPERCOLLIDER, em 26/11/2026

Esta rodada fecha o mesmo defeito da instalação anterior, agora com a causa medida no log em vez de
suposta. Às 22:19 de 26/11/2026, no build 8, com a ponte escolhida e uma sessão já adotada, a tela
repetiu "Não deu para responder. Falha de rede: a sessão do DSH fechou os eventos sem devolver texto".

O log da ponte trouxe a linha do caso:

```
2026-11-27T01:19:40Z eventos -> session-94f30e75...: 105 quadros, 250 chars de texto, 716 de raciocinio, fechou por fim do turno (end)
```

Os 250 caracteres eram a resposta do turno **anterior**, não da pergunta feita às 22:19. A causa: o
`session/follow` do DSH entrega primeiro um retrato da sessão inteira e, logo depois, os quadros do
último turno já fechado. A ponte repassava tudo, o `turn/end` daquele turno antigo fechava o stream e
o iPhone ficava com texto de outra hora ou com nada. Sessão ocupada no computador piora o quadro,
porque a resposta do turno que está rodando chega antes da resposta da fila.

| o que mudou | onde | por quê |
|---|---|---|
| fronteira pelo pedido desta ponte | `ponte/servidor.mjs`, rota `/eventos` | o `requestId` devolvido pelo `POST /mensagem` aparece no evento do pedido (`user/message` ou `agent/inbox/spliced`); o que vem antes disso é conversa que já estava na sessão |
| piso do turno | mesma rota | o turno do pedido é o primeiro começo de turno no piso ou acima dele, e o piso começa em `sessionStats.turns + 1` e sobe a cada turno de outra pessoa que aparecer, venha ele antes ou depois da fronteira |
| só o fim do turno do pedido fecha | mesma rota | `turn/end` de outro turno é ignorado; antes o fim de um turno alheio encerrava o stream do iPhone |
| raciocínio não é resposta | mesma rota | `assistant/message` e `turn/end` só fecham com texto; antes 786 caracteres de raciocínio e nenhum de fala fechavam o stream com a tela vazia |
| fim de turno sem texto com causa | mesma rota | turno encerrado por motivo do DSH (por exemplo `blocked`) agora manda `event: erro` com o motivo, em vez de sumir calado |
| ponte que não cai | topo de `servidor.mjs` | `uncaughtException` e `unhandledRejection` são registrados no log e o processo segue; antes um cliente que abandonava o stream derrubava a ponte inteira (`ECONNRESET` no aparelho) |
| sessão ocupada não recebe a pergunta | `Fontes/Conversa/ConversaViewModel.swift`, `executarEnvio` e `sessaoOcupada` | se a sessão escolhida está respondendo no computador (`rodando` na lista), o app abre uma sessão só do iPhone em vez de entrar na fila |
| versão | `project.yml` | `CURRENT_PROJECT_VERSION` de 8 para 9 |

| o que | como foi medido | resultado |
|---|---|---|
| sessão nova | `node _tmp\teste-eventos.mjs`, mensagem e leitura de `/eventos` | texto `alfa` em 1.450 ms e em 2.846 ms nas duas rodadas |
| sessão com história | mesmo script com um id que já tinha turno fechado | texto `beta` em 1.371 ms e em 1.657 ms, sem repetir a resposta antiga |
| sessão ocupada | `node _tmp\teste-fila.mjs`, pergunta longa e outra por cima 1,5 s depois | só `gama`, a resposta do segundo pedido, em 20.108 ms e em 13.597 ms, depois do turno de lá terminar |
| caminho do iPhone | mesmo teste com o endereço do tailnet | texto `alfa` em 1.866 ms |
| cliente que abandona o stream | `node _tmp\teste-abandono.mjs`, duas vezes | `/v1/saude` respondeu 200 nas duas, a ponte continuou de pé e registrou `fechou por fim do stream` |
| ordem crua dos quadros | `node _tmp\ordem-crua.mjs` com `?cru=1` | 24 quadros: `snapshot`, `step/start`, cinco `user/message`, `assistant-stream start turno=1`, `text-delta`, `block-end`, `assistant/message`, `end`, `step/end`, `turn/end` |
| turno bloqueado | leitura crua de uma sessão que o DSH encerrou com `blocked` | a ponte passou a fechar com motivo em vez de deixar a tela pendurada |

#### O teste do iPhone às 23:04, que achou o resto

O build 8 já instalado mandou `[ponte SUPERCOLLIDER] Teste` para a sessão desta conversa, que estava
respondendo na hora. O log da ponte mostrou o buraco que ainda sobrava:

```
2026-11-27T02:04:09Z eventos -> session-94f30e75...: 87 quadros, 0 chars de texto, 786 de raciocinio, fechou por fim do turno (end)
```

O `end` do stream de uma etapa não carrega número de turno, então ele fechava o stream do iPhone
achando que o turno tinha acabado, com o raciocínio do turno do computador e nenhuma fala. Foi o que
produziu as três mudanças de cima: `end` de etapa não fecha mais nada, `turn/end` só fecha o turno do
pedido, e o piso do turno não depende mais da ordem em que os quadros chegam. Como isso mora só na
ponte, vale para o build 8 e para o build 9 sem reinstalar nada.

#### O teste do iPhone às 23:19, que fechou o caso

A mensagem seguinte do aparelho caiu no caso oposto: a tela ficou em "escrevendo" e nenhum texto
apareceu, sem erro e sem fechamento. O log parou no `GET .../eventos` e nunca registrou a linha de
fechamento:

```
2026-11-27T02:19:19.325Z req GET /v1/sessoes/session-94f30e75.../eventos de 127.0.0.1
```

A leitura crua do retrato da sessão (`?cru=1`) mostrou duas coisas que a ponte não estava usando. O
`snapshot` traz `records` com o pedido do iPhone (o `agent/inbox/spliced` com o `rpcId`), o
`turn/start` do turno dele, o `assistant/message` com `data.turn` e o `turn/end`. E
`sessionStats.turns` já contava o turno do próprio pedido quando ele acabara de começar, então o piso
calculado como `turns + 1` caía um acima do turno certo: nenhum `turn/start` batia no piso, o stream
nunca travava um turno e ficava mudo até o vigia.

As três correções:

- o piso sai dos turnos dos registros do `snapshot` que vêm antes da fronteira, nunca de
  `sessionStats.turns`;
- depois da fronteira, o `snapshot` é lido como se fossem quadros ao vivo: o `assistant/message` do
  turno do pedido entrega o texto e o `turn/end` dele fecha o stream. É o que salva o stream aberto
  segundos depois do POST, com a resposta já pronta;
- se o turno do pedido não for identificado em 90 s, a ponte avisa na tela em vez de deixar
  "escrevendo" para sempre.

Medições depois do reinício, com o mesmo código:

| caso | resultado |
|---|---|
| sessão com história, stream aberto junto do POST | "dois" em 1.275 ms |
| mesma sessão, stream aberto 400 ms depois | "dois" em 1.213 ms |
| stream aberto 3 s depois, resposta já pronta | "dois." em 15 ms, lido do retrato |
| stream aberto 8 s depois, resposta já pronta | "dois." em 13 ms, lido do retrato |
| sessão nova | "alfa" em 3.013 ms e em 5.119 ms |
| sessão com história | "beta" em 1.355 ms |
| sessão ocupada, duas rodadas | só "gama", em 18.475 ms e em 24.718 ms |
| cliente que abandona o stream | `/v1/saude` responde 200 e a ponte segue viva |
| tailnet | "alfa." em 3.864 ms |
| erros não tratados no log desde o reinício | nenhum |

Também vale para o build 8, que está no aparelho: nada disso mudou o app.

#### A conta do que mudou

| o que | como foi medido | resultado |
|---|---|---|
| rodada do CI | `gh run view 45924613321`, commit `7c3ac46` | `success` nos dois jobs, "Simulador e capturas" em 7m48s e "IPA sem assinatura" em 3m02s |
| pacote entregue | artefato `ipa` da rodada, conferido com `zipfile` e `plistlib` | `DSH-livre.ipa` com 932.449 bytes e sha256 `5EEA7C014B5B842AAD560B3471445A91FF625DD80B83631284312BEB35E4FC8C` |
| conteúdo do pacote | mesmo conferidor | 15 entradas, nenhuma com `PlugIns`, `dev.ramses.dsh`, versão `1.0.0` build `9`, mínimo 18.0 |
| binário | `file_size` de `Payload/DSH.app/DSH` no `zipfile` | 3.798.496 bytes, 1.952 a mais que os 3.796.544 do build 8, que é o código novo |
| onde o arquivo está | `C:\Users\victo\iCloudDrive\DSH-livre-20261126-build9.ipa` e `_tmp\share\DSH-livre-20261126-build9.ipa` | mesmo sha256 nos dois |

Depois de instalar, Ajustes tem de mostrar "1.0.0 (9)" no rodapé. Com o motor na ponte, a pergunta
responde mesmo quando a sessão escolhida está respondendo no computador, porque o app abre uma sessão
só dele; com o motor no DeepSeek direto, a resposta vem pelo stream descomprimido do build 7.

O que esta rodada **não** prova: nada foi instalado no aparelho ainda. A prova é de compilação nos
dois jobs, do conteúdo do pacote e dos quatro caminhos da ponte medidos daqui com o mesmo código que
o build 9 carrega. A regra da sessão ocupada foi exercitada pela ponte e pela compilação, não pelo
toque na tela do iPhone.

## 11. O que fica aberto

O que está abaixo é conhecido e não escondido. Nenhum item impede usar o app no dia a dia, mas
cada um é uma promessa que o app ainda não cumpre.

| o que | estado | por que não foi feito |
|---|---|---|
| validar a chave da DeepSeek em Ajustes | passou a existir em 25/11/2026: o botão "Testar a chave" faz uma chamada real, com `max_tokens: 16`, e mostra o código HTTP e o começo do corpo | antes só conferia o prefixo `sk-`; o custo agora é de 16 tokens por toque, e é o usuário quem decide tocar |
| bloco de código muito longo | cresce sem limite dentro da bolha | cortar com "mostrar mais" mexe no `TextoRico`, e a conversa de demonstração já usa o limite como prova de rolagem |
| primeiro quadro da resposta ao vivo | o recuo pendente aparece a partir do segundo quadro | o streaming chega em pedaços e o primeiro é renderizado antes de haver linha completa |
| criar sessão pela ponte | a rota foi exercitada daqui com `POST /v1/sessoes` (200 com `sessionId`) e o app ganhou o botão "Nova sessão no DSH" no build 4 | falta tocar o botão no aparelho e ver a sessão nova abrir; a rodada do CI não tem tailnet, então o simulador não exercita a ponte |
| folha do artefato durante a resposta | pode fechar sozinha quando o texto ao vivo vira mensagem gravada | a bolha ao vivo é substituída no fim do stream, e com ela o estado que segurava a folha |
| widget e compartilhamento no iPhone | exigem conta paga do programa de desenvolvedor | os dois alvos usam App Group, que a conta gratuita não libera; com conta gratuita, o pacote que instala é o `DSH-livre.ipa`, sem as extensões |
| remover anexo no transcrito | a bolha desenha o cartão sem a ação de remover | anexo já enviado não sai da conversa, e o parâmetro `aoRemover` do cartão fica reservado à barra de entrada, que ainda usa as etiquetas dela |
| instalação em iPhone físico | reinstalada em 25/11/2026 pelo Sideloadly com conta gratuita, com o build da gaveta, do teste de chave e do QR | a assinatura vence em 7 dias; renovar exige o Sideloadly com o PC e o iPhone na mesma rede |
| pareamento por QR exercitado no aparelho | o caminho está provado no servidor (`POST /v1/pareamento` e `/v1/pareamento/trocar`, com código de uso único) e o build 5 traz o leitor dentro de Ajustes, com `AVCaptureMetadataOutput` e o mesmo `PedidoDePareamento` do link `dsh://` | falta ler um QR de verdade com a câmera do iPhone e ver o token cair no cofre; é o teste seguinte. O simulador do CI não tem QR nem câmera com imagem, então ele não fecha essa prova |
| texto do pedido de câmera | resolvido no build 6: `NSCameraUsageDescription` cita a foto anexada e o QR de pareamento, e o pacote traz a frase nova em `Info.plist` | o alerta do sistema agora descreve as duas ações que usam a câmera |
| resposta vazia do motor DeepSeek direto | tratado no build 7: o stream passou a ser lido pela delegação do `URLSession`, que descomprime, e o erro diz quantas linhas chegaram junto do `Content-Encoding` | falta confirmar no aparelho que a conversa responde; se não responder, a faixa do erro passa a nomear a causa |
| pergunta caindo em sessão ocupada | tratado no build 9: a ponte só entrega o turno do próprio pedido (fronteira pelo `requestId`) e o app abre sessão nova quando a escolhida está `rodando` no computador | falta confirmar no aparelho: mandar duas mensagens seguidas, com uma sessão do PC respondendo, e ver a resposta certa na tela do iPhone |
| troca entre dois computadores | a lista, o token por instância e o espelho para as preferências existem e a seção Computadores abre no simulador com um computador salvo | falta ter dois computadores com ponte de pé e alternar entre eles para ver a sessão de cada um carregar no aparelho; o simulador do CI não tem tailnet |
| foto pela ponte | o motor DeepSeek direto recebe a foto de verdade, em base64; a ponte recebe só o texto reconhecido, e o pedido diz isso ao modelo | a ponte é transporte de texto e não tem rota de imagem; fazer a foto atravessar exigiria uma rota nova nela e um servidor que aceitasse o JPEG |
| importar a chave de busca web | o cofre do PC não tem `TAVILY_API_KEY` nem `BRAVE_API_KEY` | criar uma chave gratuita na Tavily, gravar no cofre do PC e usar o botão de importar, ou colar direto em Ajustes |


