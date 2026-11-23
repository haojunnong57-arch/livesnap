# 实况工坊 LiveSnap

把任意视频抽 **3 秒**，生成真正的 iOS 实况照片（Live Photo），直接存进「照片」相册。

- SwiftUI + AVFoundation + Photos，纯原生、零第三方依赖
- GitHub Actions 云端编译（macOS 26 / Xcode 26），产出未签名 IPA
- 目标系统 iOS 17.0+，仅 iPhone

## 下载安装

Releases 里的 `LiveSnap-unsigned.ipa` 是**未签名**包：

- AltStore / Sideloadly：用自己的 Apple ID 签名后安装（免费账号 7 天有效，续签即可）
- TrollStore（iOS 14.0–17.0 支持版本）：直接安装，永久有效

## 工作原理

1. `AVAssetExportSession` 按用户选择的起点剪出 3 秒片段
2. `AVAssetImageGenerator` 在片段中点取一帧，写成 JPEG，并在 MakerApple 字典的 `17` 键写入 content identifier
3. `AVAssetReader` + `AVAssetWriter` 原样重封装视频，写入 `com.apple.quicktime.content.identifier` 资产级元数据，并写一条 `com.apple.quicktime.still-image-time` 定时元数据轨道
4. `PHAssetCreationRequest` 把 `.photo` 与 `.pairedVideo` 两个 resource 一起写进相册，Photos 即识别为一张实况照片

视频里没有时长限制；片段固定 3 秒（视频本身不足 3 秒时用整段）。

## 本地编译

```bash
brew install xcodegen
xcodegen generate
open LiveSnap.xcodeproj
```

## 云端编译

推送到 `main` 即触发 `.github/workflows/build.yml`，产物自动发到 `build-latest` Release。
