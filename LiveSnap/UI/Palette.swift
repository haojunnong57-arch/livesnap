//
//  Palette.swift
//  视频转实况 - 设计系统与原生视图桥接
//

import SwiftUI
import UIKit
import AVFoundation
import Photos
import PhotosUI

enum Palette {
    static let accent = Color(uiColor: .systemOrange)
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let hair = Color(uiColor: .separator)
    static let ink = Color(uiColor: .label)
    static let subtle = Color(uiColor: .secondaryLabel)
}

func timeLabel(_ seconds: Double) -> String {
    let value = max(0, seconds.isFinite ? seconds : 0)
    let minutes = Int(value) / 60
    let rest = value - Double(minutes * 60)
    return String(format: "%02d:%04.1f", minutes, rest)
}

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Palette.hair)
            .frame(height: 0.5)
    }
}

struct SectionCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Palette.surface)
            )
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color(uiColor: .systemBackground))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.ink.opacity(configuration.isPressed ? 0.82 : 1))
            )
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Palette.ink.opacity(configuration.isPressed ? 0.45 : 0.72))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
    }
}

struct VideoPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct LivePhotoPreview: UIViewRepresentable {
    let livePhoto: PHLivePhoto

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.livePhoto = livePhoto
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        if uiView.livePhoto !== livePhoto {
            uiView.livePhoto = livePhoto
        }
    }
}
