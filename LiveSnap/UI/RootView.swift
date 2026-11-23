//
//  RootView.swift
//  实况工坊 LiveSnap
//

import SwiftUI
import PhotosUI
import Photos
import AVFoundation

struct RootView: View {
    @StateObject private var model = MakerViewModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var showPicker = false

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(spacing: 18) {
                    header
                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)

            if model.isGenerating {
                generatingOverlay
            }
        }
        .photosPicker(isPresented: $showPicker,
                      selection: $pickerItem,
                      matching: .videos,
                      photoLibrary: .shared())
        .onChange(of: pickerItem) { _, newValue in
            guard let newValue else { return }
            pickerItem = nil
            model.importVideo(newValue)
        }
        .alert("提示", isPresented: alertBinding) {
            Button("知道了", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { newValue in
                if !newValue { model.errorMessage = nil }
            }
        )
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.violet, Palette.amber.opacity(0.9)],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .frame(width: 46, height: 46)
                Image(systemName: "livephoto")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("实况工坊")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("视频 → 3 秒实况照片")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            if model.imported != nil {
                Button {
                    model.discardVideo()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(.ultraThinMaterial))
                }
            }
        }
    }

    // MARK: - 主体

    @ViewBuilder
    private var content: some View {
        if model.result != nil {
            resultCard
        } else if model.imported != nil {
            trimCard
        } else {
            introCard
        }
    }

    private var introCard: some View {
        GlassCard {
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Palette.violet.opacity(0.7), Palette.amber.opacity(0.55)],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                        .frame(width: 104, height: 104)
                    Image(systemName: "livephoto.play")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.top, 4)

                Text("选视频，抽 3 秒，一键生成")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("生成的实况照片会直接存进「照片」App，长按就能看到那 3 秒动态。")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)

                HStack(spacing: 8) {
                    stepBadge("1", "选视频")
                    stepBadge("2", "调起点")
                    stepBadge("3", "生成入库")
                }

                Button {
                    showPicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "video.badge.plus")
                        Text(model.isImporting ? "正在读取…" : "导入视频")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.isImporting)
                .padding(.top, 4)
            }
        }
    }

    private func stepBadge(_ index: String, _ title: String) -> some View {
        HStack(spacing: 6) {
            Text(index)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Palette.violet.opacity(0.55)))
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }

    private var trimCard: some View {
        GlassCard(padding: 16) {
            VStack(spacing: 16) {
                VideoPlayerView(player: model.player)
                    .frame(height: 330)
                    .background(Color.black.opacity(0.65))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )

                VStack(spacing: 8) {
                    HStack {
                        Text("截取窗口")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        Text(String(format: "%.1f 秒", model.availableLength))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.amber)
                    }

                    if model.maxStart > 0.05 {
                        Slider(
                            value: Binding(
                                get: { model.startTime },
                                set: { model.setStart($0) }
                            ),
                            in: 0...model.maxStart
                        )
                        .tint(Palette.amber)
                    } else {
                        Text("这段视频不足 3 秒，会整段做成实况照片。")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack {
                        Text(model.startLabel)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Text(model.endLabel)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                Button {
                    model.generate()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("生成实况照片")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.isGenerating)

                Button {
                    showPicker = true
                } label: {
                    Text("换一段视频")
                }
                .buttonStyle(SecondaryCapsuleStyle())
            }
        }
    }

    private var resultCard: some View {
        GlassCard(padding: 16) {
            VStack(spacing: 14) {
                Group {
                    if let livePhoto = model.livePhoto {
                        LivePhotoPreview(livePhoto: livePhoto)
                    } else {
                        ZStack {
                            Color.white.opacity(0.06)
                            ProgressView().tint(.white)
                        }
                    }
                }
                .frame(height: 380)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )

                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Palette.mint)
                    Text("已保存到「照片」相册")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                }

                Text("长按上方画面即可预览动态；到「照片」里打开这张图，长按同样会动。")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineSpacing(2)

                HStack(spacing: 10) {
                    Button {
                        model.resetResult()
                    } label: {
                        Text("再做一张")
                    }
                    .buttonStyle(SecondaryCapsuleStyle())

                    Button {
                        showPicker = true
                    } label: {
                        Text("换视频")
                    }
                    .buttonStyle(SecondaryCapsuleStyle())
                }
            }
        }
    }

    private var generatingOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.15)

                Text("正在生成实况照片")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text(model.progressText)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
        }
    }
}
