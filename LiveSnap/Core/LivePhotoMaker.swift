//
//  LivePhotoMaker.swift
//  视频转实况
//
//  从视频里截一段（0.5–3 秒），生成真正的 iOS 实况照片并存入相册。
//

import Foundation
import AVFoundation
import CoreMedia
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers

struct LivePhotoResult {
    let photoURL: URL
    let videoURL: URL
    let identifier: String
}

enum MakerError: LocalizedError {
    case unreadableVideo
    case trimFailed(String)
    case stillFailed
    case pairFailed(String)
    case permissionDenied
    case saveFailed(String)
    case previewFailed

    var errorDescription: String? {
        switch self {
        case .unreadableVideo:
            return "这段视频读不出来，换一条试试。"
        case .trimFailed(let reason):
            return "截取片段失败：" + reason
        case .stillFailed:
            return "封面帧提取失败。"
        case .pairFailed(let reason):
            return "写入实况照片信息失败：" + reason
        case .permissionDenied:
            return "没有相册写入权限，请到「设置 › 视频转实况」里打开「添加照片」。"
        case .saveFailed(let reason):
            return "保存到相册失败：" + reason
        case .previewFailed:
            return "实况照片预览生成失败。"
        }
    }
}

final class LivePhotoMaker {

    /// iOS 实况照片的配对视频上限
    static let maxLength: Double = 3.0
    /// 最短可生成片段
    static let minLength: Double = 0.5

    // MARK: - 主流程

    func generate(sourceURL: URL,
                  startSeconds: Double,
                  lengthSeconds: Double,
                  workDirectory: URL,
                  progress: @escaping (String) -> Void) async throws -> LivePhotoResult {
        let asset = AVURLAsset(url: sourceURL)
        let durationTime: CMTime
        do {
            durationTime = try await asset.load(.duration)
        } catch {
            throw MakerError.unreadableVideo
        }
        let total = CMTimeGetSeconds(durationTime)
        guard total.isFinite, total > 0.1 else { throw MakerError.unreadableVideo }

        let length = max(Self.minLength, min(lengthSeconds, min(Self.maxLength, total)))
        let start = max(0, min(startSeconds, total - length))
        let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                duration: CMTime(seconds: length, preferredTimescale: 600))

        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        let identifier = UUID().uuidString

        progress("正在截取片段…")
        let clipURL = workDirectory.appendingPathComponent("clip-" + identifier + ".mov")
        try exportClip(asset: asset, range: range, to: clipURL)

        let clipAsset = AVURLAsset(url: clipURL)
        let measured = (try? await clipAsset.load(.duration)).map { CMTimeGetSeconds($0) } ?? length
        let clipDuration = (measured.isFinite && measured > 0.1) ? measured : length

        progress("正在生成封面帧…")
        let photoURL = workDirectory.appendingPathComponent("still-" + identifier + ".jpg")
        try writeStill(assetURL: clipURL, atSeconds: clipDuration / 2, identifier: identifier, to: photoURL)

        progress("正在写入实况照片元数据…")
        let pairedURL = workDirectory.appendingPathComponent("paired-" + identifier + ".mov")
        try await writePairedVideo(sourceURL: clipURL,
                                   identifier: identifier,
                                   clipDuration: clipDuration,
                                   to: pairedURL)

        progress("正在保存到相册…")
        return LivePhotoResult(photoURL: photoURL, videoURL: pairedURL, identifier: identifier)
    }

    // MARK: - 截取片段

    private func exportClip(asset: AVAsset, range: CMTimeRange, to outputURL: URL) throws {
        try? FileManager.default.removeItem(at: outputURL)
        var lastError = "未知错误"
        let presets = [AVAssetExportPresetHighestQuality, AVAssetExportPresetPassthrough]

        for preset in presets {
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { continue }
            guard session.supportedFileTypes.contains(.mov) else { continue }
            session.outputURL = outputURL
            session.outputFileType = .mov
            session.timeRange = range
            session.shouldOptimizeForNetworkUse = false

            let semaphore = DispatchSemaphore(value: 0)
            session.exportAsynchronously {
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 120)

            if session.status == .completed,
               FileManager.default.fileExists(atPath: outputURL.path) {
                return
            }
            if let error = session.error {
                lastError = error.localizedDescription
            } else {
                lastError = "导出状态异常：" + String(describing: session.status.rawValue)
            }
            session.cancelExport()
            try? FileManager.default.removeItem(at: outputURL)
        }

        throw MakerError.trimFailed(lastError)
    }

    // MARK: - 封面帧

    private func writeStill(assetURL: URL, atSeconds: Double, identifier: String, to outputURL: URL) throws {
        let asset = AVURLAsset(url: assetURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1920, height: 1920)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.15, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.15, preferredTimescale: 600)

        let time = CMTime(seconds: max(0.02, atSeconds), preferredTimescale: 600)
        let image: CGImage
        do {
            var actual = CMTime.zero
            image = try generator.copyCGImage(at: time, actualTime: &actual)
        } catch {
            throw MakerError.stillFailed
        }

        try? FileManager.default.removeItem(at: outputURL)
        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL,
                                                                UTType.jpeg.identifier as CFString,
                                                                1,
                                                                nil) else {
            throw MakerError.stillFailed
        }

        let properties: [CFString: Any] = [
            kCGImagePropertyMakerAppleDictionary: ["17": identifier],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifPixelXDimension: image.width,
                kCGImagePropertyExifPixelYDimension: image.height
            ],
            kCGImageDestinationLossyCompressionQuality: 0.94
        ]

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw MakerError.stillFailed
        }
    }

    // MARK: - 写入配对视频

    private func writePairedVideo(sourceURL: URL,
                                  identifier: String,
                                  clipDuration: Double,
                                  to outputURL: URL) async throws {
        let asset = AVURLAsset(url: sourceURL)

        let videoTracks: [AVAssetTrack]
        do {
            videoTracks = try await asset.loadTracks(withMediaType: .video)
        } catch {
            throw MakerError.pairFailed("读取视频轨道失败")
        }
        guard let videoTrack = videoTracks.first else {
            throw MakerError.pairFailed("这段视频没有画面轨道")
        }

        let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        let videoFormats = (try? await videoTrack.load(.formatDescriptions)) ?? []
        let transform = (try? await videoTrack.load(.preferredTransform)) ?? .identity

        try? FileManager.default.removeItem(at: outputURL)
        let reader: AVAssetReader
        let writer: AVAssetWriter
        do {
            reader = try AVAssetReader(asset: asset)
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        } catch {
            throw MakerError.pairFailed(error.localizedDescription)
        }

        writer.metadata = [Self.contentIdentifierItem(identifier)]

        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else {
            throw MakerError.pairFailed("无法读取画面数据")
        }
        reader.add(videoOutput)

        let videoInput = AVAssetWriterInput(mediaType: .video,
                                            outputSettings: nil,
                                            sourceFormatHint: videoFormats.first)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = transform
        guard writer.canAdd(videoInput) else {
            throw MakerError.pairFailed("无法写入画面数据")
        }
        writer.add(videoInput)

        var audioOutput: AVAssetReaderTrackOutput?
        var audioInput: AVAssetWriterInput?
        if let audioTrack = audioTracks.first {
            let formats = (try? await audioTrack.load(.formatDescriptions)) ?? []
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            let input = AVAssetWriterInput(mediaType: .audio,
                                           outputSettings: nil,
                                           sourceFormatHint: formats.first)
            input.expectsMediaDataInRealTime = false
            if reader.canAdd(output), writer.canAdd(input) {
                reader.add(output)
                writer.add(input)
                audioOutput = output
                audioInput = input
            }
        }

        let adaptor = try Self.makeStillImageTimeAdaptor()
        guard writer.canAdd(adaptor.assetWriterInput) else {
            throw MakerError.pairFailed("无法写入实况时间标记")
        }
        writer.add(adaptor.assetWriterInput)

        guard reader.startReading() else {
            throw MakerError.pairFailed(reader.error?.localizedDescription ?? "读取启动失败")
        }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw MakerError.pairFailed(writer.error?.localizedDescription ?? "写入启动失败")
        }
        writer.startSession(atSourceTime: .zero)

        let midpoint = CMTime(seconds: clipDuration / 2, preferredTimescale: 600)
        let markerRange = CMTimeRange(start: midpoint, duration: CMTime(value: 1, timescale: 30))
        let marker = AVTimedMetadataGroup(items: [Self.stillImageTimeItem()], timeRange: markerRange)
        guard adaptor.append(marker) else {
            reader.cancelReading()
            writer.cancelWriting()
            throw MakerError.pairFailed("实况时间标记写入失败")
        }
        adaptor.assetWriterInput.markAsFinished()

        let group = DispatchGroup()
        group.enter()
        Self.pump(from: videoOutput,
                  into: videoInput,
                  queue: DispatchQueue(label: "livesnap.video"),
                  group: group)

        if let output = audioOutput, let input = audioInput {
            group.enter()
            Self.pump(from: output,
                      into: input,
                      queue: DispatchQueue(label: "livesnap.audio"),
                      group: group)
        }

        if group.wait(timeout: .now() + 120) == .timedOut {
            reader.cancelReading()
            writer.cancelWriting()
            throw MakerError.pairFailed("写入超时")
        }

        if reader.status == .failed {
            writer.cancelWriting()
            throw MakerError.pairFailed(reader.error?.localizedDescription ?? "读取视频失败")
        }

        let finishing = DispatchSemaphore(value: 0)
        writer.finishWriting {
            finishing.signal()
        }
        _ = finishing.wait(timeout: .now() + 90)

        guard writer.status == .completed else {
            throw MakerError.pairFailed(writer.error?.localizedDescription ?? "写入没有完成")
        }
    }

    private static func pump(from output: AVAssetReaderOutput,
                             into input: AVAssetWriterInput,
                             queue: DispatchQueue,
                             group: DispatchGroup) {
        var finished = false
        input.requestMediaDataWhenReady(on: queue) {
            while input.isReadyForMoreMediaData {
                if finished { return }
                guard let sample = output.copyNextSampleBuffer() else {
                    finished = true
                    input.markAsFinished()
                    group.leave()
                    return
                }
                if !input.append(sample) {
                    finished = true
                    input.markAsFinished()
                    group.leave()
                    return
                }
            }
        }
    }

    // MARK: - 元数据

    private static func contentIdentifierItem(_ identifier: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.keySpace = AVMetadataKeySpace.quickTimeMetadata
        item.key = "com.apple.quicktime.content.identifier" as NSString
        item.identifier = AVMetadataIdentifier(rawValue: "mdta/com.apple.quicktime.content.identifier")
        item.dataType = kCMMetadataBaseDataType_UTF8 as String
        item.value = identifier as NSString
        return item
    }

    private static func stillImageTimeItem() -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.keySpace = AVMetadataKeySpace.quickTimeMetadata
        item.key = "com.apple.quicktime.still-image-time" as NSString
        item.identifier = AVMetadataIdentifier(rawValue: "mdta/com.apple.quicktime.still-image-time")
        item.dataType = "com.apple.metadata.datatype.int8"
        item.value = NSNumber(value: Int8(0))
        return item
    }

    private static func makeStillImageTimeAdaptor() throws -> AVAssetWriterInputMetadataAdaptor {
        let specification: [CFString: Any] = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier: "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType: "com.apple.metadata.datatype.int8"
        ]

        var formatDescription: CMMetadataFormatDescription?
        let status = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault,
            metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: [specification] as CFArray,
            formatDescriptionOut: &formatDescription
        )

        guard status == 0, let description = formatDescription else {
            throw MakerError.pairFailed("实况时间标记的格式创建失败")
        }

        let input = AVAssetWriterInput(mediaType: .metadata,
                                       outputSettings: nil,
                                       sourceFormatHint: description)
        input.expectsMediaDataInRealTime = false
        return AVAssetWriterInputMetadataAdaptor(assetWriterInput: input)
    }

    // MARK: - 相册

    func saveToLibrary(_ result: LivePhotoResult) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw MakerError.permissionDenied
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.creationDate = Date()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.addResource(with: .photo, fileURL: result.photoURL, options: options)
                request.addResource(with: .pairedVideo, fileURL: result.videoURL, options: options)
            }
        } catch {
            throw MakerError.saveFailed(error.localizedDescription)
        }
    }

    func makePreview(_ result: LivePhotoResult, targetSize: CGSize) async throws -> PHLivePhoto {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<PHLivePhoto, Error>) in
            var resumed = false
            _ = PHLivePhoto.request(withResourceFileURLs: [result.photoURL, result.videoURL],
                                    placeholderImage: nil,
                                    targetSize: targetSize,
                                    contentMode: .aspectFit) { livePhoto, info in
                let degraded = (info[PHLivePhotoInfoIsDegradedKey] as? NSNumber)?.boolValue ?? false
                if degraded || resumed { return }
                resumed = true
                if let livePhoto {
                    continuation.resume(returning: livePhoto)
                } else {
                    continuation.resume(throwing: MakerError.previewFailed)
                }
            }
        }
    }
}
