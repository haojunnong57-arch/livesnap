//
//  MakerViewModel.swift
//  视频转实况
//

import Foundation
import Combine
import SwiftUI
import Photos
import PhotosUI
import AVFoundation
import CoreTransferable
import UniformTypeIdentifiers

struct ImportedVideo {
    let url: URL
    let duration: Double
}

struct MovieFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { file in
            SentTransferredFile(file.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("video2live-import-" + UUID().uuidString + "." + ext)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return MovieFile(url: destination)
        }
    }
}

final class MakerViewModel: ObservableObject {
    @Published var imported: ImportedVideo?
    @Published var start: Double = 0
    @Published var length: Double = LivePhotoMaker.maxLength
    @Published var thumbnails: [UIImage] = []
    @Published var isGenerating = false
    @Published var isImporting = false
    @Published var isPlaying = false
    @Published var progressText = ""
    @Published var result: LivePhotoResult?
    @Published var livePhoto: PHLivePhoto?
    @Published var errorMessage: String?

    let player = AVPlayer()
    private let maker = LivePhotoMaker()
    private var workDirectory: URL?
    private var loopObserver: Any?
    private var endObserver: NSObjectProtocol?

    var duration: Double { imported?.duration ?? 0 }
    var maxLength: Double { min(LivePhotoMaker.maxLength, max(duration, 0)) }
    var minLength: Double { min(LivePhotoMaker.minLength, maxLength) }
    var end: Double { min(start + length, duration) }

    init() {
        player.actionAtItemEnd = .pause
        loopObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.04, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self, self.isPlaying else { return }
            let current = CMTimeGetSeconds(time)
            guard current.isFinite else { return }
            if current >= self.end - 0.02 {
                self.player.seek(to: CMTime(seconds: self.start, preferredTimescale: 600),
                                 toleranceBefore: .zero,
                                 toleranceAfter: .zero)
            }
        }
    }

    deinit {
        if let loopObserver {
            player.removeTimeObserver(loopObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    // MARK: - 导入

    func importVideo(_ item: PhotosPickerItem) {
        isImporting = true
        errorMessage = nil
        pausePreview()
        player.replaceCurrentItem(with: nil)
        thumbnails = []

        Task {
            var movie: MovieFile?
            do {
                movie = try await item.loadTransferable(type: MovieFile.self)
            } catch {
                movie = nil
            }

            guard let loaded = movie else {
                DispatchQueue.main.async {
                    self.isImporting = false
                    self.errorMessage = "这段视频读取失败，先把它保存到本机相册再试一次。"
                }
                return
            }

            let asset = AVURLAsset(url: loaded.url)
            var seconds: Double = 0
            if let duration = try? await asset.load(.duration) {
                seconds = CMTimeGetSeconds(duration)
            }

            DispatchQueue.main.async {
                self.isImporting = false
                guard seconds.isFinite, seconds > 0.2 else {
                    self.errorMessage = "视频太短了，换一条长一点的。"
                    return
                }
                self.imported = ImportedVideo(url: loaded.url, duration: seconds)
                self.result = nil
                self.livePhoto = nil

                let maxLen = min(LivePhotoMaker.maxLength, seconds)
                self.length = maxLen
                self.start = seconds > maxLen ? (seconds - maxLen) / 2 : 0

                self.player.replaceCurrentItem(with: AVPlayerItem(url: loaded.url))
                self.observeEnd()
                self.seekToStart()
                self.loadThumbnails(url: loaded.url, duration: seconds)
            }
        }
    }

    // MARK: - 截取区间

    func moveWindow(to newStart: Double) {
        let upper = max(0, duration - length)
        start = max(0, min(newStart, upper))
    }

    func resizeLeft(to newStart: Double) {
        let fixedEnd = end
        let lowest = max(0, fixedEnd - maxLength)
        let highest = fixedEnd - minLength
        let value = max(lowest, min(newStart, highest))
        start = value
        length = fixedEnd - value
    }

    func resizeRight(to newEnd: Double) {
        let highest = min(duration, start + maxLength)
        let lowest = start + minLength
        let value = max(lowest, min(newEnd, highest))
        length = max(minLength, value - start)
    }

    func scrub() {
        seekToStart()
    }

    func seekToStart() {
        guard imported != nil else { return }
        player.seek(to: CMTime(seconds: start, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero)
    }

    // MARK: - 预览播放

    func togglePlay() {
        if isPlaying {
            pausePreview()
        } else {
            playPreview()
        }
    }

    func playPreview() {
        guard imported != nil else { return }
        let current = CMTimeGetSeconds(player.currentTime())
        if !current.isFinite || current < start - 0.05 || current >= end - 0.02 {
            player.seek(to: CMTime(seconds: start, preferredTimescale: 600),
                        toleranceBefore: .zero,
                        toleranceAfter: .zero)
        }
        player.play()
        isPlaying = true
    }

    func pausePreview() {
        player.pause()
        isPlaying = false
    }

    // MARK: - 生成

    func generate() {
        guard let video = imported, !isGenerating else { return }
        pausePreview()
        isGenerating = true
        progressText = "准备中…"
        errorMessage = nil

        let startValue = start
        let lengthValue = length

        cleanupWork()
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("Video2Live-" + UUID().uuidString)
        workDirectory = work

        Task {
            let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard authorization == .authorized || authorization == .limited else {
                DispatchQueue.main.async {
                    self.isGenerating = false
                    self.progressText = ""
                    self.errorMessage = MakerError.permissionDenied.errorDescription
                }
                return
            }

            do {
                let made = try await maker.generate(sourceURL: video.url,
                                                    startSeconds: startValue,
                                                    lengthSeconds: lengthValue,
                                                    workDirectory: work) { text in
                    DispatchQueue.main.async {
                        self.progressText = text
                    }
                }
                try await maker.saveToLibrary(made)
                let preview = try? await maker.makePreview(made, targetSize: CGSize(width: 1400, height: 1400))

                DispatchQueue.main.async {
                    self.result = made
                    self.livePhoto = preview
                    self.isGenerating = false
                    self.progressText = ""
                }
            } catch {
                DispatchQueue.main.async {
                    self.isGenerating = false
                    self.progressText = ""
                    if let makerError = error as? MakerError {
                        self.errorMessage = makerError.errorDescription
                    } else {
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    func resetResult() {
        result = nil
        livePhoto = nil
        cleanupWork()
    }

    func discardVideo() {
        pausePreview()
        imported = nil
        result = nil
        livePhoto = nil
        thumbnails = []
        start = 0
        length = LivePhotoMaker.maxLength
        player.replaceCurrentItem(with: nil)
        cleanupWork()
    }

    // MARK: - 内部

    private func observeEnd() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isPlaying else { return }
            self.player.seek(to: CMTime(seconds: self.start, preferredTimescale: 600))
            self.player.play()
        }
    }

    private func loadThumbnails(url: URL, duration: Double) {
        thumbnails = []
        guard duration > 0 else { return }
        let count = 12

        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 260, height: 260)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.25, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)

            var images: [UIImage] = []
            var failed = false

            for index in 0..<count {
                let ratio = (Double(index) + 0.5) / Double(count)
                let time = CMTime(seconds: max(0.02, duration * ratio), preferredTimescale: 600)
                do {
                    let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                    images.append(UIImage(cgImage: cgImage))
                } catch {
                    failed = true
                    break
                }
            }

            let ready = failed ? [] : images
            DispatchQueue.main.async {
                self.thumbnails = ready
            }
        }
    }

    private func cleanupWork() {
        if let directory = workDirectory {
            try? FileManager.default.removeItem(at: directory)
        }
        workDirectory = nil
    }
}
