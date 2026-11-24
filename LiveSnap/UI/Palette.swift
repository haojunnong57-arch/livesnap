//
//  Palette.swift
//  视频转实况 - 自适应配色、卡片、按钮与原生视图桥接
//

import SwiftUI
import UIKit
import AVFoundation
import Photos
import PhotosUI

enum Palette {
    static let accent = Color(red: 0.976, green: 0.608, blue: 0.196)
    static let accentDeep = Color(red: 0.937, green: 0.451, blue: 0.071)
}

func timeLabel(_ seconds: Double) -> String {
    let value = max(0, seconds.isFinite ? seconds : 0)
    let minutes = Int(value) / 60
    let rest = value - Double(minutes * 60)
    return String(format: "%02d:%04.1f", minutes, rest)
}

struct AdaptiveBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                Color.black
                Circle()
                    .fill(Color(red: 0.55, green: 0.42, blue: 0.98).opacity(0.13))
                    .frame(width: 460, height: 460)
                    .blur(radius: 130)
                    .offset(x: -130, y: -300)
                Circle()
                    .fill(Palette.accent.opacity(0.09))
                    .frame(width: 380, height: 380)
                    .blur(radius: 140)
                    .offset(x: 170, y: 320)
            } else {
                Color(uiColor: .systemBackground)
                Circle()
                    .fill(Palette.accent.opacity(0.14))
                    .frame(width: 420, height: 420)
                    .blur(radius: 120)
                    .offset(x: -150, y: -280)
                Circle()
                    .fill(Color(red: 0.52, green: 0.60, blue: 1.0).opacity(0.12))
                    .frame(width: 380, height: 380)
                    .blur(radius: 130)
                    .offset(x: 170, y: 300)
            }
        }
        .ignoresSafeArea()
    }
}

struct GlassCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.16), radius: 22, x: 0, y: 12)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16.5, weight: .bold, design: .rounded))
            .foregroundStyle(Color(uiColor: .systemBackground))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Capsule().fill(Color.primary))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

struct SecondaryCapsuleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.primary.opacity(0.86))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.06)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
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
