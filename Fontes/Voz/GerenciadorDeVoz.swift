import AVFoundation
import Combine
import CoreGraphics
import Foundation
import Speech

enum ErroDeVoz: LocalizedError {
    case semPermissaoDeFala
    case idiomaIndisponivel
    case microfoneIndisponivel

    var errorDescription: String? {
        switch self {
        case .semPermissaoDeFala:
            return "O reconhecimento de fala precisa de permissão nos Ajustes."
        case .idiomaIndisponivel:
            return "O reconhecimento de fala em português não está disponível agora."
        case .microfoneIndisponivel:
            return "Não consegui abrir o microfone. Confira a permissão nos Ajustes."
        }
    }
}

/// Fica entre a thread de áudio do AVAudioEngine e o reconhecimento.
/// O tap é instalado uma vez só e continua valendo entre reinícios da tarefa,
/// então a requisição ativa mora aqui em vez de ficar isolada no @MainActor.
private final class PonteDeAudio: @unchecked Sendable {
    var requisicao: SFSpeechAudioBufferRecognitionRequest?

    func anexar(_ buffer: AVAudioPCMBuffer) {
        requisicao?.append(buffer)
    }
}

/// Escuta em pt-BR, entrega a frase quando o usuário cala a boca e fala a resposta
/// enquanto ela ainda chega em pedaços do provedor.
@MainActor
final class GerenciadorDeVoz: ObservableObject {
    @Published var transcrevendo = false
    @Published var textoParcial = ""
    @Published var nivelDeAudio: CGFloat = 0
    /// A tela precisa disso para trocar entre escutar, pensar e falar.
    @Published var falando = false

    var aoConcluirFrase: ((String) -> Void)?

    private static let idioma = "pt-BR"
    private static let pausaParaConcluir: UInt64 = 1_400_000_000
    private static let esperaDaDescarga: UInt64 = 450_000_000
    private static let limiteDeCaracteresSemPausa = 240

    private let reconhecedor: SFSpeechRecognizer?
    private let vozPreferida: AVSpeechSynthesisVoice?
    private let motor = AVAudioEngine()
    private let sintetizador = AVSpeechSynthesizer()
    private let ponteDeAudio = PonteDeAudio()

    private var requisicao: SFSpeechAudioBufferRecognitionRequest?
    private var tarefa: SFSpeechRecognitionTask?
    private var geracao = 0
    private var tapInstalado = false

    private var pausaAgendada: Task<Void, Never>?
    private var descargaAgendada: Task<Void, Never>?
    private var vigiaDaFala: Task<Void, Never>?

    private var pendenteDaFala = ""
    private var inicioDaFala: Date?
    private var textoNaBaseDaFala = ""

    private var reiniciosSeguidos = 0
    private var instanteDoUltimoReinicio: Date?

    init() {
        reconhecedor = SFSpeechRecognizer(locale: Locale(identifier: GerenciadorDeVoz.idioma))
        vozPreferida = GerenciadorDeVoz.melhorVozEmPortugues()
    }

    // MARK: - Escuta

    func iniciar() throws {
        guard !transcrevendo else { return }
        try configurarSessao()
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            try comecarCaptura()
        case .notDetermined:
            pedirPermissaoDeFala()
        default:
            throw ErroDeVoz.semPermissaoDeFala
        }
    }

    /// A tela consulta isto antes de ligar o microfone sozinha: o pedido de
    /// autorização do sistema fica reservado ao toque do usuário no botão.
    var permissaoDeFalaConcedida: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func parar() {
        pausaAgendada?.cancel()
        pausaAgendada = nil
        descargaAgendada?.cancel()
        descargaAgendada = nil
        tarefa?.cancel()
        tarefa = nil
        requisicao?.endAudio()
        requisicao = nil
        ponteDeAudio.requisicao = nil
        if tapInstalado {
            motor.inputNode.removeTap(onBus: 0)
            tapInstalado = false
        }
        if motor.isRunning {
            motor.stop()
        }
        transcrevendo = false
        nivelDeAudio = 0
        reiniciosSeguidos = 0
        instanteDoUltimoReinicio = nil
        // Desativar a sessão com a voz ainda falando cortaria a própria resposta.
        if !sintetizador.isSpeaking {
            _ = try? AVAudioSession.sharedInstance()
                .setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func configurarSessao() throws {
        let sessao = AVAudioSession.sharedInstance()
        do {
            try sessao.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            _ = try sessao.setActive(true)
        } catch {
            throw ErroDeVoz.microfoneIndisponivel
        }
    }

    private func pedirPermissaoDeFala() {
        SFSpeechRecognizer.requestAuthorization { [weak self] situacao in
            guard situacao == .authorized else { return }
            Task { @MainActor in
                guard let self = self else { return }
                do {
                    try self.comecarCaptura()
                } catch {
                    self.parar()
                }
            }
        }
    }

    private func comecarCaptura() throws {
        guard let reconhecedor = reconhecedor, reconhecedor.isAvailable else {
            throw ErroDeVoz.idiomaIndisponivel
        }
        let entrada = motor.inputNode
        let formato = entrada.outputFormat(forBus: 0)
        // Formato de zero canais acontece quando não há entrada disponível (sem microfone
        // ou sessão de áudio negada); instalar o tap assim derruba o app.
        guard formato.channelCount > 0 else {
            throw ErroDeVoz.microfoneIndisponivel
        }
        try prepararReconhecimento()
        if !tapInstalado {
            let ponte = ponteDeAudio
            entrada.installTap(onBus: 0, bufferSize: 2048, format: formato) { [weak self] buffer, _ in
                ponte.anexar(buffer)
                let nivel = GerenciadorDeVoz.nivelDeAudio(de: buffer)
                Task { @MainActor in
                    self?.aplicarNivel(nivel)
                }
            }
            tapInstalado = true
        }
        motor.prepare()
        do {
            try motor.start()
        } catch {
            throw ErroDeVoz.microfoneIndisponivel
        }
        transcrevendo = true
    }

    private func prepararReconhecimento() throws {
        guard let reconhecedor = reconhecedor else {
            throw ErroDeVoz.idiomaIndisponivel
        }
        let novaRequisicao = SFSpeechAudioBufferRecognitionRequest()
        novaRequisicao.shouldReportPartialResults = true
        // Sem reconhecimento local o áudio vai para o servidor da Apple, o que
        // acrescenta latência e quebra a conversa em tempo real.
        if reconhecedor.supportsOnDeviceRecognition {
            novaRequisicao.requiresOnDeviceRecognition = true
        }
        geracao += 1
        let geracaoAtual = geracao
        requisicao = novaRequisicao
        ponteDeAudio.requisicao = novaRequisicao
        tarefa = reconhecedor.recognitionTask(with: novaRequisicao) { [weak self] resultado, erro in
            Task { @MainActor in
                self?.tratar(resultado: resultado, erro: erro, geracao: geracaoAtual)
            }
        }
    }

    private func reiniciarCaptura() {
        guard transcrevendo else { return }
        pausaAgendada?.cancel()
        pausaAgendada = nil
        tarefa?.cancel()
        tarefa = nil
        requisicao?.endAudio()
        requisicao = nil
        ponteDeAudio.requisicao = nil
        do {
            try prepararReconhecimento()
        } catch {
            parar()
        }
    }

    private func tratar(
        resultado: SFSpeechRecognitionResult?,
        erro: Error?,
        geracao: Int
    ) {
        guard transcrevendo, geracao == self.geracao else { return }

        if let resultado = resultado {
            let texto = resultado.bestTranscription.formattedString
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !texto.isEmpty {
                if falando {
                    avaliarBargeIn(texto)
                }
                textoParcial = texto
                agendarPausa()
            }
        }

        if erro != nil || resultado?.isFinal == true {
            // O reconhecedor encerra a tarefa sozinho depois de um silêncio longo.
            // Para a conversa continuar, ou entregamos o que existe ou abrimos outra.
            if !concluirFrase() {
                textoParcial = ""
                if podeReiniciar() {
                    reiniciarCaptura()
                } else {
                    parar()
                }
            }
        }
    }

    private func podeReiniciar() -> Bool {
        let agora = Date()
        if let ultimo = instanteDoUltimoReinicio, agora.timeIntervalSince(ultimo) < 2 {
            reiniciosSeguidos += 1
        } else {
            reiniciosSeguidos = 0
        }
        instanteDoUltimoReinicio = agora
        // Reconhecedor em erro seguido criaria tarefa sem parar; cinco tentativas seguidas
        // em menos de 2 s já indicam ambiente quebrado, não silêncio do usuário.
        return reiniciosSeguidos <= 4
    }

    private func agendarPausa() {
        pausaAgendada?.cancel()
        pausaAgendada = Task { @MainActor [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(nanoseconds: GerenciadorDeVoz.pausaParaConcluir)
            guard !Task.isCancelled else { return }
            _ = self.concluirFrase()
        }
    }

    @discardableResult
    private func concluirFrase() -> Bool {
        let texto = textoParcial.trimmingCharacters(in: .whitespacesAndNewlines)
        let palavras = texto.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
        guard palavras > 3 else { return false }
        textoParcial = ""
        nivelDeAudio = 0
        // Reiniciar antes de avisar evita que o resto do mesmo áudio entre na próxima frase.
        reiniciarCaptura()
        aoConcluirFrase?(texto)
        return true
    }

    private func aplicarNivel(_ nivel: CGFloat) {
        let suave = nivelDeAudio * 0.65 + nivel * 0.35
        nivelDeAudio = min(max(suave, 0), 1)
    }

    private nonisolated static func nivelDeAudio(de buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let canais = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let amostras = canais[0]
        let quantidade = Int(buffer.frameLength)
        var soma: Float = 0
        for indice in 0..<quantidade {
            let amostra = amostras[indice]
            soma += amostra * amostra
        }
        let rms = Double((soma / Float(quantidade)).squareRoot())
        // Escala logarítmica: fala normal fica perto de -30 dB e quase não mexe numa
        // escala linear; de -55 dB a 0 dB a esfera responde à voz sem saturar com tosse.
        let decibeis = 20 * log10(max(rms, 0.000_001))
        let normalizado = (decibeis + 55) / 55
        return CGFloat(min(max(normalizado, 0), 1))
    }

    // MARK: - Fala

    func falar(_ texto: String) {
        let limpo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpo.isEmpty || !pendenteDaFala.isEmpty else { return }
        if !limpo.isEmpty {
            pendenteDaFala += pendenteDaFala.isEmpty ? limpo : " " + limpo
        }
        emitirFrasesCompletas()
        // Frase que nunca termina enquanto o modelo transmite precisa sair mesmo assim,
        // senão o usuário escuta a resposta em silêncio até o último caractere chegar.
        if pendenteDaFala.count > GerenciadorDeVoz.limiteDeCaracteresSemPausa {
            descarregarPendente()
        } else {
            agendarDescarga()
        }
    }

    func calar() {
        descargaAgendada?.cancel()
        descargaAgendada = nil
        pendenteDaFala = ""
        vigiaDaFala?.cancel()
        vigiaDaFala = nil
        if sintetizador.isSpeaking {
            sintetizador.stopSpeaking(at: .immediate)
        }
        falando = false
        inicioDaFala = nil
    }

    private func emitirFrasesCompletas() {
        while let recorte = GerenciadorDeVoz.proximaFrase(em: pendenteDaFala) {
            pendenteDaFala = recorte.resto
            enfileirar(recorte.frase)
        }
    }

    private func agendarDescarga() {
        descargaAgendada?.cancel()
        descargaAgendada = Task { @MainActor [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(nanoseconds: GerenciadorDeVoz.esperaDaDescarga)
            guard !Task.isCancelled else { return }
            self.descarregarPendente()
        }
    }

    private func descarregarPendente() {
        let resto = pendenteDaFala.trimmingCharacters(in: .whitespacesAndNewlines)
        pendenteDaFala = ""
        guard !resto.isEmpty else { return }
        enfileirar(resto)
    }

    private func enfileirar(_ frase: String) {
        let limpa = frase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpa.isEmpty else { return }
        let enunciado = AVSpeechUtterance(string: limpa)
        enunciado.voice = vozPreferida
            ?? AVSpeechSynthesisVoice(language: GerenciadorDeVoz.idioma)
        enunciado.rate = AVSpeechUtteranceDefaultSpeechRate
        if !falando {
            inicioDaFala = Date()
            textoNaBaseDaFala = textoParcial
        }
        falando = true
        sintetizador.speak(enunciado)
        iniciarVigiaDaFala()
    }

    private func iniciarVigiaDaFala() {
        guard vigiaDaFala == nil else { return }
        // AVSpeechSynthesizer não avisa quando a fila inteira termina sem delegate,
        // e o delegate misturaria isolamento de thread com o @MainActor da classe.
        vigiaDaFala = Task { @MainActor [weak self] in
            guard let self = self else { return }
            var ociosos = 0
            while !Task.isCancelled {
                if self.sintetizador.isSpeaking {
                    ociosos = 0
                } else {
                    ociosos += 1
                    if ociosos >= 2 {
                        self.falando = false
                        self.inicioDaFala = nil
                        self.vigiaDaFala = nil
                        return
                    }
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            self.vigiaDaFala = nil
        }
    }

    private func avaliarBargeIn(_ texto: String) {
        guard let inicio = inicioDaFala, Date().timeIntervalSince(inicio) > 0.4 else {
            return
        }
        let novo: String
        if !textoNaBaseDaFala.isEmpty && texto.hasPrefix(textoNaBaseDaFala) {
            novo = String(texto.dropFirst(textoNaBaseDaFala.count))
        } else {
            novo = texto
        }
        let palavras = novo.split(whereSeparator: {
            $0 == " " || $0 == "\n" || $0 == "\t"
        }).count
        guard palavras >= 2 else { return }
        calar()
    }

    private static func proximaFrase(em texto: String) -> (frase: String, resto: String)? {
        var indice = texto.startIndex
        while indice < texto.endIndex {
            let caractere = texto[indice]
            let seguinte = texto.index(after: indice)
            let fecha: Bool
            switch caractere {
            case "!", "?", "\n":
                fecha = true
            case ".":
                // Ponto intra-palavra (3.5, 127.0.0.1) não encerra frase.
                fecha = seguinte == texto.endIndex
                    || texto[seguinte] == " "
                    || texto[seguinte] == "\n"
            default:
                fecha = false
            }
            if fecha {
                let frase = String(texto[texto.startIndex..<seguinte])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let resto = String(texto[seguinte...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !frase.isEmpty else { return nil }
                return (frase, resto)
            }
            indice = seguinte
        }
        return nil
    }

    private static func melhorVozEmPortugues() -> AVSpeechSynthesisVoice? {
        let candidatas = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language == "pt-BR" || $0.language == "pt_BR"
        }
        let ordenadas = candidatas.sorted {
            pontuacaoDaVoz($0) > pontuacaoDaVoz($1)
        }
        if let melhor = ordenadas.first {
            return melhor
        }
        return AVSpeechSynthesisVoice(language: GerenciadorDeVoz.idioma)
    }

    private static func pontuacaoDaVoz(_ voz: AVSpeechSynthesisVoice) -> Int {
        switch voz.quality {
        case .premium:
            return 3
        case .enhanced:
            return 2
        default:
            return 1
        }
    }
}
