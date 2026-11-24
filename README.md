# 视频转实况 LiveSnap

导入视频 → 拖动时间轴选一段（0.5–3 秒）→ 预览 → 生成真正的 iOS 实况照片，直接存进「照片」相册。

- SwiftUI + AVFoundation + Photos，纯原生、零第三方依赖
- 时间轴可拖动左右把手调节长度，也可整段平移；缩略帧实时显示
- 预览播放所选区间并自动循环，满意后再生成
- 背景随系统深浅色切换（深色纯黑 / 浅色纯白）
- GitHub Actions 云端编译（macOS 26 / Xcode 26），产出未签名 IPA
- 目标系统 iOS 17.0+，仅 iPhone

## 下载安装

Releases 里的 `LiveSnap-unsigned.ipa` 是**未签名**包：

- AltStore / Sideloadly：用自己的 Apple ID 签名后安装（免费账号 7 天有效，续签即可）
- TrollStore（支持的系统版本）：直接安装，永久有效

## 为什么最长 3 秒

iOS 的实况照片由「静态图 + 配对视频」组成，配对视频超过 3 秒会被系统拒绝或者只保留静帧，所以区间长度被限制在 0.5–3 秒。

## 工作原理

1. `AVAssetExportSession` 按时间轴所选区间剪出片段
2. `AVAssetImageGenerator` 在片段中点取一帧写成 JPEG，并在 MakerApple 字典的 `17` 键写入 content identifier
3. `AVAssetReader` + `AVAssetWriter` 原样重封装视频，写入 `com.apple.quicktime.content.identifier` 资产级元数据，并写一条 `com.apple.quicktime.still-image-time` 定时元数据轨道
4. `PHAssetCreationRequest` 把 `.photo` 与 `.pairedVideo` 两个 resource 一起写进相册，Photos 即识别为一张实况照片

## 本地编译

```bash
brew install xcodegen
xcodegen generate
open LiveSnap.xcodeproj
```

## 云端编译

推送到 `main` 即触发 `.github/workflows/build.yml`，产物自动发到 `build-latest` Release。
