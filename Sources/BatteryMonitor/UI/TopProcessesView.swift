import AppKit
import SwiftUI

struct TopProcessesView: View {
    let store: BatteryStore

    var body: some View {
        Card(expand: true) {
            VStack(alignment: .leading, spacing: 7) {
                if !store.processesLoaded {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 140)
                } else if store.topProcesses.isEmpty {
                    Text("目前沒有明顯耗電的程式")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 140)
                } else {
                    let maxPower = store.topProcesses.map(\.power).max() ?? 1
                    ForEach(store.topProcesses) { p in
                        HStack(spacing: 8) {
                            icon(for: p)
                                .frame(width: 18, height: 18)
                            Text(p.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Capsule()
                                .fill(Color.orange.gradient)
                                .frame(width: max(3, 70 * p.power / maxPower), height: 5)
                                .frame(width: 70, alignment: .leading)
                            Text(String(format: "%.1f", p.power))
                                .monospacedDigit()
                                .frame(width: 42, alignment: .trailing)
                        }
                        .font(.callout)
                    }
                }
                Spacer(minLength: 0)
                Text("數值為「能源影響」指標（相對值，不是瓦數），每 5 秒更新")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear {
            // 之後每 5 秒的取樣由 AppDelegate 負責，面板關掉就停
            Task { await store.refreshProcesses() }
        }
    }

    @ViewBuilder
    private func icon(for p: EnergyProcess) -> some View {
        if let path = p.appPath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
        } else {
            Image(systemName: "gearshape.fill")
                .resizable()
                .scaledToFit()
                .padding(2)
                .foregroundStyle(.secondary)
        }
    }
}
