# Referências e decisão de desenho

Documento de apoio do app. Registra o que foi olhado, o que foi copiado, o que foi
recusado de propósito e as suposições que ficaram abertas.

## Conceito em três linhas

1. Papel quente, tinta quase preta e um âmbar sóbrio: o app parece um caderno de
   anotações que responde, não um painel de inteligência artificial.
2. A resposta não mora em balão. Texto longo em balão vira coluna estreita, então
   a resposta ocupa a largura toda; só a fala do usuário tem forma de recado.
3. Uma cor de destaque, usada apenas no que age: enviar, parar, link, ponto de
   sessão viva. Nada de gradiente, brilho, mascote ou enfeite de IA.

## Fontes consultadas

Busca feita com `web_search` por capturas e descrições dos três apps de conversa
que o público já conhece. As páginas oficiais em si não foram lidas linha a linha
(o conteúdo é de aplicativo, atrás de JavaScript e de loja), então o que segue é o
que aparece nas capturas públicas e nas descrições dos próprios fabricantes.

| app | o que copiar | o que evitar |
|---|---|---|
| ChatGPT (https://chatgpt.com) | barra de entrada flutuante que ocupa a largura e cresce com o texto; resposta larga, sem cartão; código com bloco próprio e botão de copiar | verde da marca em botão, ícone de "brilho" antes de cada resposta, animação de digitação enfeitada |
| Claude (https://claude.ai) | hierarquia silenciosa: título discreto, texto com entrelinha generosa; raciocínio em bloco recolhível em vez de poluir a resposta | papel creme com serifa em tudo (marca registrada, não decisão de produto), caixa com borda em cada bloco |
| Gemini (https://gemini.google.com) | seletor de modelo junto da entrada, sem sair da tela; estados vazios com uma frase e não com grade de sugestões | gradiente azul/roxo, brilho de quatro pontas, voz de marketing no texto |

Link de marca não é decoração: o app é da DeepSeek, então o âmbar não copia
nenhuma das três e o nome do provedor aparece no chip, não no título da tela.

## O que veio da revisão de limpeza (skill `declutter`)

A revisão foi feita antes de escrever Swift, com contagem de sinais e a rubrica de
50 pontos (hierarquia, tipografia, cor, botões, formulários, estados, navegação,
acessibilidade). O antes e depois abaixo está ordenado por impacto, não por
facilidade:

1. **Balão de resposta removido.** Era o maior sinal de "IA de prateleira" e o
   maior custo de leitura: a resposta agora ocupa a largura e só o usuário tem
   recado com fundo.
2. **Uma cor de destaque.** Antes o desenho pedia âmbar, verde de sucesso e roxo
   de "pensando". Ficou um âmbar; verde só aparece como texto de confirmação e
   vermelho só em erro.
3. **Zero enfeite de IA.** Sem brilho, sem partícula, sem digitação letra a letra.
   O indicador de raciocínio é um ponto que pulsa e um rótulo com o tempo real.
4. **Sem carimbo de tempo em cada mensagem.** A hora de cada fala não decide nada
   durante a conversa; ela aparece na gaveta, por conversa.
5. **Seletor de modelo no chip, não em tela de ajustes.** Trocar de modelo é
   decisão de conversa, não configuração de app.
6. **Estado vazio com uma frase.** Nada de seis cartões de sugestão: a primeira
   tela diz o que fazer e onde a resposta vai parar.
7. **Enviar e parar no mesmo alvo.** O botão troca de forma e de rótulo; o polegar
   não procura outro lugar no meio da resposta.
8. **Contraste conferido antes do desenho.** A paleta nasceu com a tabela abaixo,
   não foi corrigida depois.

## Catálogo de componentes (devlibs)

O catálogo de MCP do host central foi consultado por HTTP (6 consultas, como
combinado) atrás de padrão de estrutura, não de código. O que foi usado como
referência de forma: cartão de entrada flutuante, folha modal para lista longa,
linha de lista com ação secundária em menu, estado vazio curto. Nada foi copiado:
o projeto não aceita biblioteca de terceiro, e o contrato fixa os tipos.

Na revisão de 26/11/2026 o catálogo foi consultado de novo (3 consultas de 6), atrás do
que um app de conversa com IA faz na tela, com ChatGPT, Claude, Gemini e o próprio
DeepSeek como referência. O que voltou: `spaceui/ai-chat-workspace` (MIT), com
compositor que tem seletor de modelo e de ferramenta dentro dele, ações por mensagem
(copiar, avaliar), barra lateral com busca de conversa e o raciocínio com contador ao
vivo; `spectrum-ui/reasoning-trace` e `notra/chatgpt-reasoning`, o mesmo padrão de
"trabalhou por N s" recolhível; `reui/c-input-group-19` e `reui/c-input-group-18`, o
compositor com anexo e barra de ações. Todos são React e nenhum é SwiftUI, então nada
foi instalado: o que se aproveitou é a forma, que já é a mesma dos quatro apps citados.
O que ficou de fora, e por quê, está na lista abaixo, em "o que o app não tem".

## O que os quatro apps de IA têm e o app ainda não

Comparação com ChatGPT, Claude, Gemini e DeepSeek, e com o que o catálogo mostra do
mesmo padrão. A coluna "hoje" é o código deste repositório, não impressão.

| padrão | os quatro apps | hoje | prova |
|---|---|---|---|
| copiar a resposta | botão sob cada resposta | só o bloco de código tem copiar; a resposta inteira não | `UIPasteboard` aparece em `BlocoDeCodigo.swift:154` e em nenhum outro ponto de conversa |
| tentar de novo | sob a última resposta, refaz sem redigitar | não existe: a saída é reenviar a pergunta | `BolhaDeMensagem` não tem ação na resposta |
| seletor de modelo com uma linha | nome mais o que ele faz ("raciocina antes, mais lento") | só o nome e o check | o menu é montado com `rotuloDoModelo` |
| medidor de contexto | tokens usados e o teto do modelo | a API manda `usage` e o app joga fora | `ServicoDeepSeek.swift:165` emite `.uso` e `ConversaViewModel.swift:162` descarta |
| conversa é a sessão | lista com busca e fixar | tem, e o build 5 passou a guardar a sessão | `MenuLateral`, `TelaSessoesDsh` |
| raciocínio recolhível com tempo | "Pensou por Ns" | tem | `PensamentoRetratil` |
| estado vazio com uma ação | uma frase e o campo | tem | `DadosDeDemonstracao` e a primeira tela |

Ou seja: a parte de conversa já está no nível dos quatro, e o que falta é a camada de
ação em cima da resposta e o dado de uso que o app já recebe.

## A revisão de limpeza de 26/11/2026, na tela de Ajustes

Alvo: `Fontes/Ajustes/TelaDeAjustes.swift` inteiro, mais a folha nova do leitor de
QR. Não foram olhadas as telas irmãs (conversa, sessões, voz) nesta passada, e a
tela não foi tocada no aparelho: o que se viu de desenho é a captura do simulador.

O contador de sinais deu zero em todas as famílias, antes e depois das mudanças,
o que é esperado: ele lê marcas como rótulo de olho, emoji, degradê e travessão, e
não vê U3 a U8, U14, nem as regras de formulário e de estado. O achado daqui saiu
de leitura.

| # | onde | regra | o que estava | o que fazer |
|---|---|---|---|---|
| 1 | seção Motor | U9 e o teste do estado real | o seletor de Motor não tinha efeito visível: `configurar()` só usa a ponte quando há sessão escolhida, e a tela não dizia isso | feito no build 5: linha de estado com as três situações e botão que leva à escolha da sessão |
| 2 | seção Ponte | formulários, "a ordem é a da conversa" | o único caminho para parear era sair do app e usar a câmera do sistema | feito no build 5: a seção começa com o leitor de QR |
| 3 | parágrafos de apoio, 10 deles | U4, U5 e unslop 28 | cada seção explicava o produto em uma ou duas frases longas, e a de Motor chegou a 4 linhas | fica uma frase por seção, a que afirma um fato que o controle não mostra (o prefixo `sk-`, o `tvly-`, o endereço do tailnet); o resto sai |
| 4 | campos de chave e de endereço | formulários, "rótulo sempre visível" e U7 | o rótulo era o placeholder, que some ao digitar; só o VoiceOver tinha rótulo | rótulo visível acima do campo e o exemplo embaixo, sem repetir o que o campo já diz |
| 5 | seção Ponte | formulários, ordem | entre o campo do token e o botão que conclui a configuração havia dois parágrafos e um botão de teste | ordem: QR, endereço, token, testar, importar; os parágrafos do meio saem |
| 6 | linha de estado do motor | acabamento | o ícone de 13 pt fica centralizado num alvo de 44 pt e desalinha da primeira linha do texto | alinhar o ícone ao topo do texto |

O que se manteve de propósito: os dois botões "Salvar chave" e "Apagar chave" nas
duas seções usam o mesmo verbo para a mesma ação; os alvos de toque ficam em 44 pt;
o texto fraco sobre fundo claro mede 5,6:1 na tabela abaixo, então o parágrafo
pequeno passa em AA; e não há degradê, emoji nem travessão em nenhuma string.

Ficaram como tarefa os itens 3 a 6, que são corte de texto e mudança de layout, e a
regra da casa é propor antes de mexer.

## Paleta e contraste

Escura: fundo `#0E1013`, superfície `#16191D`, texto `#EDEFF2`, texto fraco
`#A6AEB8`, destaque `#E3A33C`. Clara: fundo `#F6F4F0`, superfície `#FFFFFF`,
texto `#15171A`, texto fraco `#5C626B`, destaque `#8A5A00`.

| par | escuro | claro | mínimo |
|---|---|---|---|
| texto sobre fundo | 16,5:1 | 16,6:1 | 4,5:1 |
| texto fraco sobre fundo | 8,5:1 | 5,6:1 | 4,5:1 |
| glifo do botão sobre destaque | 8,7:1 | 5,4:1 | 3,0:1 |
| erro sobre fundo | 6,4:1 | 6,1:1 | 4,5:1 |
| confirmação sobre fundo | 9,5:1 | 5,6:1 | 4,5:1 |

## Suposições

- **Tema claro e escuro seguem o sistema.** O contrato não prevê tela de Ajustes,
  então não há alternador de aparência dentro do app.
- **A ponte do DSH não devolve transcrição.** Pelo que o swift-base expõe, dá para
  listar sessões e enviar mensagem, não para ler o histórico delas. Por isso
  escolher uma sessão cria uma conversa local com o título da sessão, avisa que as
  próximas mensagens vão para ela e não finge importar o passado.
- **Copiar código usa a área de transferência do sistema**, com aviso falado pelo
  VoiceOver, porque o contrato não pede história de cópias.
- **O teclado não empurra a barra para fora**: a barra fica em `safeAreaInset` no
  pé, então sobe junto com o teclado sem cálculo manual.
