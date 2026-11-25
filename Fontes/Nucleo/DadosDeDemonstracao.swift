import Foundation
import SwiftData

// Única fonte de dados das capturas do CI. Sem rede: os textos são fixos.
// Contrato: conversa com 6 mensagens, raciocínio de 3 parágrafos, um bloco
// Swift, um HTML de relógio e anexos.
enum DadosDeDemonstracao {

    static let raciocinioLongo = """
    Primeiro preciso decidir o formato: um relógio de parede em HTML puro, sem biblioteca, com o ponteiro vindo do horário local do aparelho. Isso descarta canvas como primeira opção, porque transformar rotação em CSS é mais simples de manter e não precisa de laço de animação.

    Depois vem a parte visual: fundo escuro, marcas de hora em círculo e três ponteiros com origens diferentes. A rotação de cada ponteiro é a fração do ciclo correspondente, então horas usam 30 graus por hora mais um sexto por minuto, minutos usam 6 graus, segundos usam 6 graus.

    Por último o acerto do relógio: atualizar a cada segundo deixaria o ponteiro de segundos saltando, então uso um intervalo curto e recalculado quando a aba volta a ficar visível. Também preciso do rótulo de fuso horário, porque a mesma página aberta em outra máquina mostra outra hora.
    """

    static let blocoSwift = """
    ```swift
    import SwiftUI

    struct PonteiroDoRelogio: Shape {
        var angulo: Angle
        var comprimento: CGFloat
        var espessura: CGFloat

        func path(in rect: CGRect) -> Path {
            var caminho = Path()
            let centro = CGPoint(x: rect.midX, y: rect.midY)
            let ponta = CGPoint(
                x: centro.x + cos(angulo.radians) * comprimento,
                y: centro.y + sin(angulo.radians) * comprimento
            )
            caminho.move(to: centro)
            caminho.addLine(to: ponta)
            return caminho.strokedPath(StrokeStyle(lineWidth: espessura, lineCap: .round))
        }
    }
    ```
    """

    static let htmlDoRelogio = """
    ```html
    <!DOCTYPE html>
    <html lang="pt-BR">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Relógio de parede</title>
    <style>
      :root { color-scheme: dark; }
      body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #101216; font-family: system-ui, sans-serif; }
      .mostrador { position: relative; width: 260px; height: 260px; border-radius: 50%; border: 2px solid #2b3040; background: radial-gradient(circle at 50% 40%, #1b1f2a, #0c0e13); }
      .ponto { position: absolute; inset: 0; display: grid; place-items: start center; }
      .ponto i { width: 2px; height: 10px; background: #4b5468; }
      .ponteiro { position: absolute; left: 50%; bottom: 50%; transform-origin: bottom center; border-radius: 4px; }
      #hora { width: 6px; height: 70px; margin-left: -3px; background: #e8ecf4; }
      #minuto { width: 4px; height: 96px; margin-left: -2px; background: #a9b4c8; }
      #segundo { width: 2px; height: 104px; margin-left: -1px; background: #e2564a; }
      #fuso { position: absolute; bottom: 30%; width: 100%; text-align: center; color: #7d879c; font-size: 12px; letter-spacing: .08em; }
    </style>
    </head>
    <body>
      <div class="mostrador" id="mostrador">
        <div id="fuso"></div>
        <div class="ponteiro" id="hora"></div>
        <div class="ponteiro" id="minuto"></div>
        <div class="ponteiro" id="segundo"></div>
      </div>
      <script>
        const marcas = document.getElementById("mostrador");
        for (let i = 0; i < 12; i++) {
          const ponto = document.createElement("div");
          ponto.className = "ponto";
          ponto.style.transform = `rotate(${i * 30}deg)`;
          ponto.innerHTML = "<i></i>";
          marcas.appendChild(ponto);
        }
        document.getElementById("fuso").textContent =
          Intl.DateTimeFormat().resolvedOptions().timeZone;
        function desenhar() {
          const agora = new Date();
          const segundos = agora.getSeconds() + agora.getMilliseconds() / 1000;
          const minutos = agora.getMinutes() + segundos / 60;
          const horas = (agora.getHours() % 12) + minutos / 60;
          document.getElementById("hora").style.transform = `rotate(${horas * 30}deg)`;
          document.getElementById("minuto").style.transform = `rotate(${minutos * 6}deg)`;
          document.getElementById("segundo").style.transform = `rotate(${segundos * 6}deg)`;
          requestAnimationFrame(desenhar);
        }
        desenhar();
      </script>
    </body>
    </html>
    ```
    """

    static func conversa() -> Conversa {
        let inicio = Date().addingTimeInterval(-3600)
        let conversa = Conversa(
            titulo: "Relógio de parede em HTML",
            criadaEm: inicio,
            atualizadaEm: Date()
        )

        let pedido = Mensagem(
            papel: .usuario,
            conteudo: "Quero um relógio de parede para abrir no navegador do aparelho. Sem biblioteca, com ponteiro de hora, minuto e segundo.",
            criadaEm: inicio
        )

        let proposta = Mensagem(
            papel: .assistente,
            conteudo: """
            Um relógio de parede em HTML puro resolve com três ponteiros girados por CSS e um laço curto de JavaScript.

            O ponto que costuma dar errado é o ponteiro de horas: ele não pode pular de hora em hora, precisa somar a fração do minuto. Com isso os três ponteiros andam juntos e o desenho fica contínuo.
            """,
            raciocinio: raciocinioLongo,
            criadaEm: inicio.addingTimeInterval(20)
        )

        let pedidoDeSwift = Mensagem(
            papel: .usuario,
            conteudo: "Dá para ter o mesmo resultado em SwiftUI, com o ponteiro como Shape?",
            criadaEm: inicio.addingTimeInterval(80)
        )

        let respostaComCodigo = Mensagem(
            papel: .assistente,
            conteudo: "Dá. A ideia é desenhar a linha num `Path` e girar o `Shape` pelo ângulo, então o mesmo componente serve para os três ponteiros.\n\n" + blocoSwift,
            criadaEm: inicio.addingTimeInterval(140)
        )

        let anexos = Mensagem(
            papel: .usuario,
            conteudo: "Segui a ideia e cheguei neste HTML. O relógio aparece certo, mas quero o fuso escrito embaixo.",
            criadaEm: inicio.addingTimeInterval(220),
            anexos: [
                Anexo(nome: "captura-do-relogio.png", tipo: .imagem, tamanhoEmBytes: 24_576),
                Anexo(
                    nome: "relogio.html",
                    tipo: .texto,
                    texto: "<div class=\"mostrador\"><div id=\"hora\"></div></div>",
                    tamanhoEmBytes: 58
                )
            ]
        )

        let entrega = Mensagem(
            papel: .assistente,
            conteudo: "Ajustei o fuso dentro do mostrador e deixei o desenho animado por `requestAnimationFrame`, para o ponteiro de segundos não saltar.\n\n" + htmlDoRelogio,
            criadaEm: inicio.addingTimeInterval(260)
        )

        let mensagens = [pedido, proposta, pedidoDeSwift, respostaComCodigo, anexos, entrega]
        for mensagem in mensagens {
            mensagem.conversa = conversa
        }
        conversa.mensagens = mensagens
        return conversa
    }

    @MainActor
    static func inserir(_ conversa: Conversa, em contexto: ModelContext) {
        contexto.insert(conversa)
        for mensagem in conversa.mensagens {
            contexto.insert(mensagem)
        }
        try? contexto.save()
    }

    @MainActor
    static func instalar(em contexto: ModelContext) -> Conversa {
        let nova = conversa()
        inserir(nova, em: contexto)
        return nova
    }
}
