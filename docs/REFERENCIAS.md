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
