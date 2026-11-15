import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import DesignSystem
import BackendInterface

struct StudioView: View {
    @Bindable var model: AppModel
    @Environment(\.studioPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var player: AVPlayer?

    var body: some View {
        HSplitView {
            mainColumn
                .frame(minWidth: 520)
            inspector
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 340)
        }
        .background(palette.bgBase)
        .onChange(of: model.studioMediaURL) { _, url in
            Task { @MainActor in
                rebuildPlayer(url)
            }
        }
        .onAppear {
            rebuildPlayer(model.studioMediaURL)
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            WorkspaceHeader(
                title: "Studio",
                status: model.features.ffmpegAvailable ? "Local FFmpeg editing" : "FFmpeg required",
                statusColor: model.features.ffmpegAvailable ? palette.success : palette.warning
            ) {
                HStack(spacing: 8) {
                    StudioToolbarButton("Import", systemImage: "square.and.arrow.down", isEnabled: !model.studioBusy) {
                        model.importStudioMedia()
                    }
                    StudioToolbarButton(
                        "Export",
                        systemImage: "arrow.up.right.video",
                        isPrimary: true,
                        isEnabled: model.features.ffmpegAvailable && model.studioMediaURL != nil && !model.studioBusy
                    ) {
                        Task { await model.exportStudioClip() }
                    }
                }
            }
            .padding(.horizontal, StudioSpace.lg)

            if !model.features.ffmpegAvailable {
                Text("Install FFmpeg from Integrations. Studio does not require Claude or Instagram.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, StudioSpace.lg)
                    .padding(.bottom, 8)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.85))
                if player != nil {
                    StudioPlayerView(player: player)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    VStack(spacing: 8) {
                        if model.studioBusy {
                            ProgressView().controlSize(.small)
                            Text("Importing…")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(palette.textSecondary)
                        } else {
                            Image(systemName: "film")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(palette.textTertiary)
                            Text("Import a clip to preview")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 280, idealHeight: 360)
            .padding(.horizontal, StudioSpace.lg)

            timeline
                .padding(StudioSpace.lg)

            if let job = model.studioJob {
                jobStrip(job)
                    .padding(.horizontal, StudioSpace.lg)
                    .padding(.bottom, StudioSpace.md)
            }
            Spacer(minLength: 0)
        }
    }

    private var timeline: some View {
        let duration = max(model.studioInspection?.durationSeconds ?? 0, 0)
        let hasMedia = model.studioMediaURL != nil && duration > 0
        let inUpper = hasMedia ? max(0.01, min(duration, model.studioOutPoint) - 0.05) : 0.01
        let outLower = hasMedia ? min(duration, model.studioInPoint + 0.05) : 0
        let outUpper = hasMedia ? max(outLower, duration) : 0.01

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(timecode(model.studioInPoint))
                    .font(StudioType.timecode)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text("In / Out")
                    .font(StudioType.caption)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(timecode(model.studioOutPoint))
                    .font(StudioType.timecode)
                    .foregroundStyle(palette.textSecondary)
            }

            VStack(spacing: 8) {
                HStack {
                    Text("In")
                        .font(StudioType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .frame(width: 28, alignment: .leading)
                    Slider(
                        value: $model.studioInPoint,
                        in: 0...max(0.01, inUpper)
                    )
                    .tint(palette.accent)
                    .disabled(!hasMedia)
                    .onChange(of: model.studioInPoint) { _, value in
                        seek(value)
                    }
                }
                HStack {
                    Text("Out")
                        .font(StudioType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .frame(width: 28, alignment: .leading)
                    Slider(
                        value: $model.studioOutPoint,
                        in: outLower...outUpper
                    )
                    .tint(palette.accent)
                    .disabled(!hasMedia)
                    .onChange(of: model.studioOutPoint) { _, value in
                        seek(value)
                    }
                }
            }
            .animation(StudioMotion.reduced(reduceMotion, StudioMotion.state), value: model.studioInPoint)
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: StudioSpace.md) {
            Text("Inspector")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textTertiary)

            if let inspection = model.studioInspection {
                labeled("Duration", timecode(inspection.durationSeconds ?? 0))
                labeled("Size", "\(inspection.width ?? 0)×\(inspection.height ?? 0)")
                labeled("Aspect", inspection.aspectRatio ?? "—")
                labeled("Audio", inspection.hasAudio ? "Yes" : "No")
                labeled("Format", inspection.format ?? "—")
            } else {
                Text("No media selected")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textTertiary)
            }

            Divider().overlay(palette.border)

            Text("Export preset")
                .font(StudioType.caption)
                .foregroundStyle(palette.textTertiary)
            Picker("Preset", selection: $model.studioExportPreset) {
                ForEach(AppModel.StudioExportPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .labelsHidden()
            .pickerStyle(.radioGroup)

            Spacer()
            Text("Paths stay inside the managed Media/Temp directories.")
                .font(StudioType.caption)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(StudioSpace.md)
        .background(palette.bgSidebar)
    }

    private func jobStrip(_ job: RecentJobDTO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Export · \(job.state)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if !["COMPLETED", "FAILED", "CANCELLED"].contains(job.state.uppercased()) {
                    Button("Cancel") {
                        Task { await model.cancelStudioJob() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.danger)
                }
            }
            StudioProgressBar(progress: job.progress)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border, lineWidth: 0.5))
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(StudioType.caption).foregroundStyle(palette.textTertiary)
            Spacer()
            Text(value).font(StudioType.timecode).foregroundStyle(palette.textSecondary)
        }
    }

    private func timecode(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let m = total / 60
        let s = total % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", m, s, ms)
    }

    private func rebuildPlayer(_ url: URL?) {
        player?.pause()
        player = nil
        guard let url else { return }
        guard FileManager.default.fileExists(atPath: url.path) else {
            model.lastError = "Imported media is missing from the library."
            return
        }
        // AVPlayerView (AppKit) — do not use SwiftUI VideoPlayer on this packaging path.
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
    }

    private func seek(_ seconds: Double) {
        guard let player else { return }
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
