//
//  MakerViewModel.swift
//  实况工坊 LiveSnap
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
                .appendingPathComponent("livesnap-import-" + UUID().uuidString + "." + ext)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return MovieFile(url: destination)
        }
    }
}

final class MakerViewModel: ObservableObject {
    @Published var imported: ImportedVideo?
    @Published var startTime: Double = 0
    @Published var isGenerating = false
    @Published var isImporting = false
    @Published var progressText = ""
    @Published var result: LivePhotoResult?
    @Published var livePhoto: PHLivePhoto?
    @Published var errorMessage: String?

    let player = AVPlayer()
    private let maker = LivePhotoMaker()
    private var workDirectory: URL?

    var availableLength: Double {
        min(LivePhotoMaker.clipLength, imported?.duration ?? 0)
    }

    var maxStart: Double {
        guard let video = imported else { return 0 }
        return max(0, video.duration - min(LivePhotoMaker.clipLength, video.duration))
    }

    var startLabel: String { "起点 " + timeLabel(startTime) }
    var endLabel: String { "终点 " + timeLabel(startTime + availableLength) }

    func importVideo(_ item: PhotosPickerItem) {
        isImporting = true
        errorMessage = nil
        player.pause()

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
                self.player.replaceCurrentItem(with: AVPlayerItem(url: loaded.url))
                self.startTime = seconds > LivePhotoMaker.clipLength
                    ? max(0, (seconds - LivePhotoMaker.clipLength) / 2)
                    : 0
                self.seekToStart()
            }
        }
    }

    func setStart(_ value: Double) {
        startTime = value
        seekToStart()
    }

    func seekToStart() {
        guard imported != nil else { return }
        let time = CMTime(seconds: startTime, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func generate() {
        guard let video = imported, !isGenerating else { return }
        isGenerating = true
        progressText = "准备中…"
        errorMessage = nil

        let start = startTime
        cleanupWork()
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("LiveSnap-" + UUID().uuidString)
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
                                                    startSeconds: start,
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
        imported = nil
        result = nil
        livePhoto = nil
        startTime = 0
        player.pause()
        player.replaceCurrentItem(with: nil)
        cleanupWork()
    }

    private func cleanupWork() {
        if let directory = workDirectory {
            try? FileManager.default.removeItem(at: directory)
        }
        workDirectory = nil
    }
}
