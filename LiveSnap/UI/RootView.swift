//
//  RootView.swift
//  视频转实况
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
            AdaptiveBackground()

            ScrollView {
                VStack(spacing: 16) {
                    content
                }
                .padding(.horizontal, 18)
                .padding(.top, 26)
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

    // MARK: - 首屏

    private var introCard: some View {
        GlassCard(padding: 24) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Palette.accent, Palette.accentDeep],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                        .frame(width: 96, height: 96)
                    Image(systemName: "livephoto.play")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.top, 6)

                Text("视频转实况")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.primary)

                Text("导入视频，拖动时间轴选一段 0.5–3 秒，预览满意后生成，直接存进「照片」。")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)

                HStack(spacing: 8) {
                    stepBadge("1", "选视频")
                    stepBadge("2", "拖区间")
                    stepBadge("3", "导入相册")
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
                .background(Circle().fill(Palette.accent))
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.72))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
    }

    // MARK: - 截取 + 预览

    private var trimCard: some View {
        GlassCard(padding: 14) {
            VStack(spacing: 14) {
                VideoPlayerView(player: model.player)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                    )
                    .overlay(alignment: .bottomLeading) {
                        Text("长按播放按钮可循环预览所选片段")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                            .padding(10)
                    }

                HStack(spacing: 12) {
                    Button {
                        model.togglePlay()
                    } label: {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.primary)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(.ultraThinMaterial))
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                    }

                    TrimTimeline(
                        duration: model.duration,
                        start: model.start,
                        end: model.end,
                        thumbnails: model.thumbnails,
                        onBandChanged: { model.moveWindow(to: $0) },
                        onLeftChanged: { model.resizeLeft(to: $0) },
                        onRightChanged: { model.resizeRight(to: $0) },
                        onScrub: { model.scrub() }
                    )
                    .frame(height: 64)
                    .padding(.vertical, 6)
                }

                HStack {
                    Text("起点 " + timeLabel(model.start))
                    Spacer()
                    Text("长度 " + String(format: "%.1f 秒", model.length))
                        .foregroundStyle(Palette.accentDeep)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("终点 " + timeLabel(model.end))
                }
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Color.secondary)

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

                HStack(spacing: 10) {
                    Button {
                        showPicker = true
                    } label: {
                        Text("换一段视频")
                    }
                    .buttonStyle(SecondaryCapsuleStyle())

                    Button {
                        model.discardVideo()
                    } label: {
                        Text("取消")
                    }
                    .buttonStyle(SecondaryCapsuleStyle())
                }
            }
        }
    }

    // MARK: - 结果

    private var resultCard: some View {
        GlassCard(padding: 14) {
            VStack(spacing: 14) {
                Group {
                    if let livePhoto = model.livePhoto {
                        LivePhotoPreview(livePhoto: livePhoto)
                    } else {
                        ZStack {
                            Color.black
                            ProgressView().tint(.white)
                        }
                    }
                }
                .frame(height: 380)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                )

                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Palette.accentDeep)
                    Text("已保存到「照片」相册")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.primary)
                    Spacer()
                    Text(String(format: "%.1f 秒", model.length))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.secondary)
                }

                Text("长按上方画面可预览动态；到「照片」里打开这张图，长按同样会动。")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.secondary)
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
            Color.black.opacity(0.35).ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .tint(Color.primary)
                    .scaleEffect(1.15)

                Text("正在生成实况照片")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary)

                Text(model.progressText)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.secondary)
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
    }
}
