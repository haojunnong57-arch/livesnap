//
//  Palette.swift
//  实况工坊 LiveSnap - 配色、卡片、按钮与原生视图桥接
//

import SwiftUI
import UIKit
import AVFoundation
import Photos
import PhotosUI

enum Palette {
    static let ink = Color(red: 0.035, green: 0.047, blue: 0.082)
    static let inkSoft = Color(red: 0.086, green: 0.070, blue: 0.145)
    static let amber = Color(red: 1.000, green: 0.780, blue: 0.435)
    static let violet = Color(red: 0.560, green: 0.435, blue: 0.980)
    static let mint = Color(red: 0.420, green: 0.930, blue: 0.780)
}

func timeLabel(_ seconds: Double) -> String {
    let value = max(0, seconds.isFinite ? seconds : 0)
    let minutes = Int(value) / 60
    let rest = value - Double(minutes * 60)
    return String(format: "%02d:%04.1f", minutes, rest)
}

struct AuroraBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.ink, Palette.inkSoft, Palette.ink],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
            Circle()
                .fill(Palette.violet.opacity(0.34))
                .frame(width: 430, height: 430)
                .blur(radius: 110)
                .offset(x: -130, y: -290)
            Circle()
                .fill(Palette.amber.opacity(0.18))
                .frame(width: 360, height: 360)
                .blur(radius: 120)
                .offset(x: 170, y: 310)
        }
        .ignoresSafeArea()
        .background(Palette.ink)
    }
}

struct GlassCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = 22, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.34), Color.white.opacity(0.04)],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.38), radius: 26, x: 0, y: 18)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16.5, weight: .bold, design: .rounded))
            .foregroundStyle(Color(red: 0.06, green: 0.05, blue: 0.09))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Capsule().fill(
                    LinearGradient(colors: [Palette.amber, Palette.mint],
                                   startPoint: .leading,
                                   endPoint: .trailing)
                )
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
            .shadow(color: Palette.amber.opacity(0.22), radius: 16, x: 0, y: 10)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

struct SecondaryCapsuleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.86))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.16 : 0.07)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}

struct VideoPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.backgroundColor = .clear
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
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        if uiView.livePhoto !== livePhoto {
            uiView.livePhoto = livePhoto
        }
    }
}
