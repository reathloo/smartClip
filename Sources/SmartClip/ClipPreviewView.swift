import AppKit
import Combine
import SwiftUI

struct ClipPreviewView: View {
    let item: ClipSummary
    let loadPayload: (UUID) async -> ClipPayload?
    let onClose: () -> Void
    let onCopy: () -> Void
    var onOpen: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var payload: ClipPayload?
    @State private var isLoading = false
    @State private var revealedSensitive = false
    @AccessibilityFocusState private var headerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(ClipTheme.line)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().overlay(ClipTheme.line)
            footer
        }
        .background(ClipTheme.canvas)
        .transition(.opacity)
        .task(id: item.id) {
            guard !item.isSensitive else { return }
            await load()
        }
        .onAppear { headerFocused = true }
        .onDisappear { conceal() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            if item.isSensitive { conceal() }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: revealedSensitive)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: close) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(IconControlStyle())
            .help("Close preview")
            .accessibilityLabel("Close preview")

            Image(systemName: item.isSensitive ? "lock.fill" : item.kind.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(item.isSensitive ? Color.orange : item.kind.color)
                .frame(width: 34, height: 34)
                .background((item.isSensitive ? Color.orange : item.kind.color).opacity(0.09),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.favoriteName ?? item.kind.label)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .accessibilityFocused($headerFocused)
                Text(metadataLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if item.kind == .url, let onOpen, !item.isSensitive || revealedSensitive {
                Button("Open", systemImage: "arrow.up.right", action: onOpen)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Button(item.isSensitive && !revealedSensitive ? "Reveal" : "Copy",
                   systemImage: item.isSensitive && !revealedSensitive ? "eye" : "doc.on.doc") {
                if item.isSensitive && !revealedSensitive {
                    reveal()
                } else {
                    onCopy()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
        .background(ClipTheme.surface.opacity(0.96))
    }

    @ViewBuilder private var content: some View {
        if item.isSensitive && !revealedSensitive {
            sensitivePlaceholder
        } else if isLoading {
            ProgressView("Opening protected content…")
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let payload {
            payloadView(payload)
        } else {
            ContentUnavailableView(
                "Preview unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("The entry may have expired or could not be opened.")
            )
        }
    }

    private var sensitivePlaceholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "eye.slash")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.orange)
                .frame(width: 70, height: 70)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                .accessibilityHidden(true)
            Text("Sensitive content")
                .font(.system(size: 15, weight: .semibold))
            Text("The original value stays hidden until you reveal it.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Reveal temporarily", systemImage: "eye", action: reveal)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    @ViewBuilder private func payloadView(_ payload: ClipPayload) -> some View {
        switch payload.kind {
        case .text, .code, .url, .email:
            ScrollView {
                Text(payload.text ?? "")
                    .font(.system(size: 13, design: payload.kind == .code ? .monospaced : .default))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(22)
            }
            .background(ClipTheme.surface)
        case .image:
            if let data = payload.imageData {
                AsyncClipImage(data: data)
            } else {
                ContentUnavailableView("Image unavailable", systemImage: "photo.badge.exclamationmark")
            }
        case .files:
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(payload.filePaths ?? [], id: \.self) { path in
                        fileRow(path)
                    }
                }
                .padding(18)
            }
        }
    }

    private struct AsyncClipImage: View {
        let data: Data
        @State private var image: NSImage?

        var body: some View {
            Group {
                if let image {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 1_200, maxHeight: 900)
                        .padding(24)
                }
                .background(Color.primary.opacity(0.025))
                } else {
                    ProgressView("Decoding image…").controlSize(.small)
                }
            }
            .task(id: data) {
                guard let decoded = await ClipImageDecoder.decode(data), !Task.isCancelled else { return }
                image = NSImage(cgImage: decoded, size: .zero)
            }
        }
    }

    private func fileRow(_ path: String) -> some View {
        let exists = FileManager.default.fileExists(atPath: path)
        return HStack(spacing: 11) {
            Image(systemName: exists ? "doc" : "exclamationmark.triangle")
                .foregroundStyle(exists ? item.kind.color : Color.orange)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
            Spacer()
            if !exists {
                Text("Missing")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(ClipTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ClipTheme.line))
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        HStack(spacing: 7) {
            if item.isSensitive && revealedSensitive {
                Label("Hidden again when this window loses focus", systemImage: "lock")
                    .foregroundStyle(.orange)
            } else {
                Label("Preview", systemImage: "eye")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            KeyboardHint(text: "esc")
            Text("Close")
            KeyboardHint(text: "⌘C")
            Text("Copy")
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .frame(height: 42)
        .background(ClipTheme.surface.opacity(0.96))
    }

    private var metadataLabel: String {
        let source = item.sourceName ?? "Unknown app"
        return "\(source) · \(item.lastCopiedAt.formatted(.relative(presentation: .named)))"
    }

    private func reveal() {
        revealedSensitive = true
        Task { await load() }
    }

    @MainActor private func load() async {
        guard payload == nil, !isLoading else { return }
        isLoading = true
        let loaded = await loadPayload(item.id)
        guard !Task.isCancelled else { return }
        payload = loaded
        isLoading = false
    }

    private func conceal() {
        payload = nil
        isLoading = false
        revealedSensitive = false
    }

    private func close() {
        conceal()
        onClose()
    }
}
