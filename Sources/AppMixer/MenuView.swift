import SwiftUI

struct MenuView: View {
    @ObservedObject var manager: AudioManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if manager.processes.isEmpty {
                Text("目前沒有 App 在播放聲音")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(manager.processes) { process in
                            ProcessRow(process: process, manager: manager)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(minWidth: 320, idealWidth: 360, maxWidth: .infinity,
               minHeight: 280, idealHeight: 480, maxHeight: .infinity)
    }

    private var header: some View {
        HStack {
            Image(systemName: "slider.horizontal.3")
            Text("App 音量").font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                manager.resetAll()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.plain)
            .help("全部重設為 100%")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help("結束 AppMixer")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct ProcessRow: View {
    let process: AudioProcess
    @ObservedObject var manager: AudioManager

    var body: some View {
        let muted = manager.isMuted(process)
        let displayVolume = muted ? 0 : manager.volume(for: process)
        let volumeBinding = Binding<Double>(
            get: { Double(manager.volume(for: process)) },
            set: { manager.setVolume(Float($0), for: process) }
        )

        HStack(spacing: 8) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(process.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    if process.isPlaying {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                    }
                }
                HStack(spacing: 6) {
                    Button {
                        manager.toggleMute(process)
                    } label: {
                        Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(muted ? Color.red : Color.secondary)
                            .frame(width: 16)
                    }
                    .buttonStyle(.plain)

                    Slider(value: volumeBinding, in: 0...1)
                        .controlSize(.small)
                        .disabled(muted)

                    Text("\(Int((displayVolume * 100).rounded()))%")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.04))
        )
    }

    @ViewBuilder
    private var icon: some View {
        if let nsImage = process.icon {
            Image(nsImage: nsImage)
                .resizable()
                .frame(width: 30, height: 30)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
        }
    }
}
