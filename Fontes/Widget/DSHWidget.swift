import SwiftUI
import WidgetKit
import UIKit

// Widgets do DSH, no alvo DSHWidget.
// O widget não lê nada do app: não há SwiftData aqui e de propósito não há
// rede. Por isso o estado padrão é honesto ("nenhuma conversa aberta") e o
// valor do widget está em ser atalho rápido para conversa, voz e câmera.

// MARK: - Entrada e linha do tempo

struct EntradaDoWidget: TimelineEntry {
    let data: Date
}

// A linha do tempo é estática de propósito: o widget não tem o que atualizar
// sem dados do app, e recarregar sem motivo gasta bateria.
struct ProvedorDoWidget: TimelineProvider {
    func placeholder(in context: Context) -> EntradaDoWidget {
        EntradaDoWidget(data: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (EntradaDoWidget) -> Void) {
        completion(EntradaDoWidget(data: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EntradaDoWidget>) -> Void) {
        let entrada = EntradaDoWidget(data: Date())
        completion(Timeline(entries: [entrada], policy: .never))
    }
}

// MARK: - Endereços de destino

enum DestinosDoWidget {
    // Forçar desembrulho aqui é seguro: são literais fixos, conferidos uma vez.
    static let conversa = URL(string: "dsh://conversa")!
    static let voz = URL(string: "dsh://voz")!
    static let camera = URL(string: "dsh://camera")!
}

// MARK: - Widget da tela de início

struct WidgetDoDSH: Widget {
    let kind = "WidgetDoDSH"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProvedorDoWidget()) { entrada in
            VisaoDoWidget(entrada: entrada)
                .containerBackground(for: .widget) {
                    Color(uiColor: .systemBackground)
                }
        }
        .configurationDisplayName("DSH")
        .description("Atalho para conversar, falar ou abrir a câmera no DSH.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct VisaoDoWidget: View {
    let entrada: EntradaDoWidget

    @Environment(\.widgetFamily) private var familia

    var body: some View {
        switch familia {
        case .systemMedium:
            visaoMedia
        default:
            visaoPequena
        }
    }

    private var visaoPequena: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DSH")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Nenhuma conversa aberta")
                .font(.footnote)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                Link(destination: DestinosDoWidget.conversa) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                }
                Link(destination: DestinosDoWidget.voz) {
                    Image(systemName: "mic.fill")
                }
                Link(destination: DestinosDoWidget.camera) {
                    Image(systemName: "camera.fill")
                }
            }
            .font(.body)
            .foregroundStyle(.tint)
        }
        // Toque fora dos ícones abre a conversa.
        .widgetURL(DestinosDoWidget.conversa)
    }

    private var visaoMedia: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DSH")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                atalho(titulo: "Conversa", icone: "bubble.left.and.text.bubble.right", destino: DestinosDoWidget.conversa)
                atalho(titulo: "Voz", icone: "mic.fill", destino: DestinosDoWidget.voz)
                atalho(titulo: "Câmera", icone: "camera.fill", destino: DestinosDoWidget.camera)
            }
            Spacer(minLength: 0)
            Text("Nenhuma conversa aberta. Escolha como começar.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .widgetURL(DestinosDoWidget.conversa)
    }

    private func atalho(titulo: String, icone: String, destino: URL) -> some View {
        Link(destination: destino) {
            VStack(spacing: 6) {
                Image(systemName: icone)
                    .font(.title3)
                Text(titulo)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        }
        .foregroundStyle(.primary)
    }
}

// MARK: - Widget da tela de bloqueio

struct WidgetDeBloqueio: Widget {
    let kind = "WidgetDeBloqueio"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProvedorDoWidget()) { entrada in
            VisaoDeBloqueio(entrada: entrada)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName("DSH")
        .description("Atalho do DSH na tela de bloqueio.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

private struct VisaoDeBloqueio: View {
    let entrada: EntradaDoWidget

    @Environment(\.widgetFamily) private var familia

    var body: some View {
        switch familia {
        case .accessoryRectangular:
            retangular
        default:
            circular
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "mic.fill")
                .font(.headline)
        }
        // No círculo não cabe rótulo nem alvo de toque por item: o widget todo
        // leva à voz, que é a ação mais curta no pulso.
        .widgetURL(DestinosDoWidget.voz)
    }

    private var retangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("DSH")
                .font(.headline)
            Text("Toque para conversar")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(DestinosDoWidget.conversa)
    }
}

// MARK: - Pacote

@main
struct WidgetsDoDSH: WidgetBundle {
    var body: some Widget {
        WidgetDoDSH()
        WidgetDeBloqueio()
    }
}
