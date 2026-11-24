//
//  TrimTimeline.swift
//  视频转实况 - 可拖动的截取时间轴（缩略帧 + 左右把手 + 整体拖动 + 播放指针）
//

import SwiftUI
import UIKit

struct TrimTimeline: View {
    let duration: Double
    let start: Double
    let end: Double
    let playhead: Double
    let thumbnails: [UIImage]

    let onBandChanged: (Double) -> Void
    let onLeftChanged: (Double) -> Void
    let onRightChanged: (Double) -> Void
    let onScrub: () -> Void

    @State private var bandBase: Double?
    @State private var leftBase: Double?
    @State private var rightBase: Double?

    private var safeDuration: Double { max(duration, 0.1) }

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let height = geometry.size.height
            let x0 = CGFloat(start / safeDuration) * width
            let x1 = CGFloat(end / safeDuration) * width

            ZStack(alignment: .topLeading) {
                strip(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Rectangle()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: max(0, x0), height: height)

                Rectangle()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: max(0, width - x1), height: height)
                    .offset(x: x1)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Palette.accent, lineWidth: 2)
                    .frame(width: max(0, x1 - x0), height: height)
                    .offset(x: x0)

                if playhead >= start - 0.02, playhead <= end + 0.02 {
                    Rectangle()
                        .fill(Palette.accent)
                        .frame(width: 2, height: height)
                        .offset(x: min(max(CGFloat(playhead / safeDuration) * width - 1, x0), x1 - 2))
                        .allowsHitTesting(false)
                }

                Color.white.opacity(0.001)
                    .frame(width: max(0, x1 - x0 - 28), height: height)
                    .offset(x: x0 + 14)
                    .contentShape(Rectangle())
                    .gesture(bandGesture(width: width))

                handle(height: height)
                    .offset(x: x0 - 15, y: -7)
                    .gesture(leftGesture(width: width))

                handle(height: height)
                    .offset(x: x1 - 15, y: -7)
                    .gesture(rightGesture(width: width))
            }
        }
    }

    @ViewBuilder
    private func strip(width: CGFloat, height: CGFloat) -> some View {
        if thumbnails.isEmpty {
            LinearGradient(colors: [Color(white: 0.22), Color(white: 0.34)],
                           startPoint: .leading,
                           endPoint: .trailing)
                .frame(width: width, height: height)
        } else {
            HStack(spacing: 0) {
                ForEach(thumbnails.indices, id: \.self) { index in
                    Image(uiImage: thumbnails[index])
                        .resizable()
                        .scaledToFill()
                        .frame(width: width / CGFloat(thumbnails.count), height: height)
                        .clipped()
                }
            }
            .frame(width: width, height: height)
        }
    }

    private func handle(height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.white)
                .frame(width: 6, height: height + 10)
                .shadow(color: Color.black.opacity(0.35), radius: 2, x: 0, y: 1)
        }
        .frame(width: 30, height: height + 14)
        .contentShape(Rectangle())
    }

    private func bandGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if bandBase == nil { bandBase = start }
                let base = bandBase ?? start
                let delta = Double(value.translation.width / width) * safeDuration
                onBandChanged(base + delta)
            }
            .onEnded { _ in
                bandBase = nil
                onScrub()
            }
    }

    private func leftGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if leftBase == nil { leftBase = start }
                let base = leftBase ?? start
                let delta = Double(value.translation.width / width) * safeDuration
                onLeftChanged(base + delta)
            }
            .onEnded { _ in
                leftBase = nil
                onScrub()
            }
    }

    private func rightGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if rightBase == nil { rightBase = end }
                let base = rightBase ?? end
                let delta = Double(value.translation.width / width) * safeDuration
                onRightChanged(base + delta)
            }
            .onEnded { _ in
                rightBase = nil
                onScrub()
            }
    }
}
