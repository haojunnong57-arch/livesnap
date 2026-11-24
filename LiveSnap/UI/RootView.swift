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
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            if model.result != nil {
                ScrollView {
                    resultView
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            } else if model.imported != nil {
                trimView
            } else {
                ScrollView {
                    introView
                        .padding(.horizontal, 20)
                        .padding(.top, 30)
                        .padding(.bottom, 48)
                }
                .scrollIndicators(.hidden)
            }

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

    // MARK: - 首屏

    private var introView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("VIDEO → LIVE PHOTO")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(Palette.accent)

            Text("视频转实况")
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(Palette.ink)
                .padding(.top, 10)

            Text("选一段画面（默认 3 秒，最长 6 秒），生成一张长按会动的实况照片，直接存进「照片」。")
                .font(.system(size: 14.5))
                .foregroundStyle(Palette.subtle)
                .lineSpacing(5)
                .padding(.top, 9)

            SectionCard(padding: 0) {
                VStack(spacing: 0) {
                    stepRow(index: "01", title: "选一条视频", detail: "相册里任意视频都可以")
                    Hairline().padding(.leading, 58)
                    stepRow(index: "02", title: "拖动时间轴", detail: "两端把手定长度，整段可平移")
                    Hairline().padding(.leading, 58)
                    stepRow(index: "03", title: "生成并存入相册", detail: "在「照片」里长按即可播放")
                }
            }
            .padding(.top, 28)

            Button {
                showPicker = true
            } label: {
                Text(model.isImporting ? "正在读取…" : "选取视频")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.isImporting)
            .padding(.top, 18)

            Text("生成前可先循环预览所选片段。")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
                .padding(.top, 12)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func stepRow(index: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(index)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.accent)
                .padding(.top, 4)
                .frame(width: 30, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.subtle)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }

    // MARK: - 截取

    private var trimView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("截取片段")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.ink)

                Spacer()

                Text(String(format: "%.1f 秒", model.length))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Palette.accent.opacity(0.13)))
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            Spacer(minLength: 14)

            VideoSurface(player: model.player)
                .aspectRatio(model.videoAspect, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    if !model.isReady {
                        ProgressView()
                            .tint(.white)
                    } else if !model.isPlaying {
                        playBadge
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { model.togglePlay() }
                .padding(.horizontal, 20)
                .animation(.snappy(duration: 0.24), value: model.isPlaying)
                .animation(.easeInOut(duration: 0.2), value: model.isReady)

            Spacer(minLength: 14)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            controlPanel
        }
    }

    private var playBadge: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 64, height: 64)
            .background(Circle().fill(Color.black.opacity(0.42)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .transition(.scale(scale: 0.86).combined(with: .opacity))
    }

    private var controlPanel: some View {
        VStack(spacing: 14) {
            TrimTimeline(
                duration: model.duration,
                start: model.start,
                end: model.end,
                playhead: model.playhead,
                thumbnails: model.thumbnails,
                onBandChanged: { model.moveWindow(to: $0) },
                onLeftChanged: { model.resizeLeft(to: $0) },
                onRightChanged: { model.resizeRight(to: $0) },
                onScrub: { model.scrub() }
            )
            .frame(height: 64)

            HStack(spacing: 0) {
                Text(timeLabel(model.start))
                    .foregroundStyle(Palette.subtle)
                Spacer()
                Text(String(format: "长度 %.1f 秒", model.length))
                    .foregroundStyle(Palette.accent)
                    .fontWeight(.semibold)
                Spacer()
                Text(timeLabel(model.end))
                    .foregroundStyle(Palette.subtle)
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())

            if model.length > 3.05 {
                HStack(spacing: 5) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                    Text("超过 3 秒时，部分机型只会播放前 3 秒")
                        .font(.system(size: 11.5))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Palette.accent.opacity(0.92))
                .transition(.opacity)
            }

            Button {
                model.generate()
            } label: {
                Text("生成实况照片")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.isGenerating || !model.isReady)
            .padding(.top, 2)

            HStack(spacing: 0) {
                Button("换一段视频") { showPicker = true }
                    .buttonStyle(QuietButtonStyle())
                Button("取消") { model.discardVideo() }
                    .buttonStyle(QuietButtonStyle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 6)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 26,
                                   bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0,
                                   topTrailingRadius: 26,
                                   style: .continuous)
                .fill(Palette.surface)
                .ignoresSafeArea(edges: .bottom)
        )
        .animation(.snappy(duration: 0.25), value: model.length > 3.05)
    }

    // MARK: - 结果

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("实况照片")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(String(format: "%.1f 秒", model.length))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Palette.subtle)
            }

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
            .frame(height: 356)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 14)

            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                Text("已保存到「照片」相册")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
            }
            .padding(.top, 16)

            Text("在上方长按画面即可预览动态效果；保存的原图在「照片」里长按同样会动。")
                .font(.system(size: 13))
                .foregroundStyle(Palette.subtle)
                .lineSpacing(4)
                .padding(.top, 8)

            Button {
                model.resetResult()
            } label: {
                Text("再做一张")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 22)

            Button {
                showPicker = true
            } label: {
                Text("换一段视频")
            }
            .buttonStyle(QuietButtonStyle())
            .padding(.top, 2)
        }
    }

    private var generatingOverlay: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .tint(Palette.ink)

                Text("正在生成实况照片")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.ink)

                Text(model.progressText)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.subtle)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Palette.surface)
            )
        }
    }
}
