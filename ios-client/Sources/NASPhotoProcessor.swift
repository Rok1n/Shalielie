import Foundation
import Photos
import PhotosUI
import UniformTypeIdentifiers
import CoreLocation

enum NASClientError: LocalizedError {
    case noPhotoSelected, noAccess, inaccessibleAsset, notOriginalHEIC, invalidServer
    case badResponse(Int, String), malformedOutput, noNativeLivePhoto
    var errorDescription: String? {
        switch self {
        case .noPhotoSelected: "请先选择照片。"
        case .noAccess: "需要照片图库读取与写入权限（包括选中项目）。请在 iOS 设置里调整权限。"
        case .inaccessibleAsset: "无法读取原始照片资源，请授予权限后重新选择；iCloud 照片需可下载。"
        case .notOriginalHEIC: "选择的原图不是 HEIC。不能用 JPEG 替代。"
        case .invalidServer: "NAS 地址无效；HTTP 只允许局域网地址或 .local 域名。"
        case .badResponse(let status, let text): "NAS 返回 HTTP \(status)：\(text)"
        case .malformedOutput: "服务器返回的 HEIC/MOV 内容无法识别。"
        case .noNativeLivePhoto: "已调用相册保存，但系统未确认动态照片。请在相册检查新照片，不要删除原件。"
        }
    }
}

@MainActor
final class NASPhotoProcessor: ObservableObject {
    @Published var address = ""
    @Published var token = ""
    @Published var isBusy = false
    @Published var isError = false
    @Published var status = "选择原始照片或 Live Photo。NAS 只负责处理，iPhone 将结果原生保存到相册。"

    func process(_ selection: PhotosPickerItem?) async {
        guard !isBusy else { return }
        isBusy = true
        isError = false
        defer { isBusy = false }
        do {
            guard let selection else { throw NASClientError.noPhotoSelected }
            let endpoint = try self.endpoint()
            let secret = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard secret.count >= 24 else { throw NASClientError.invalidServer }

            let auth = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            guard auth == .authorized || auth == .limited else { throw NASClientError.noAccess }
            guard let identifier = selection.itemIdentifier,
                  let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
            else { throw NASClientError.inaccessibleAsset }

            let resources = PHAssetResource.assetResources(for: asset)
            guard let original = resources.first(where: { $0.type == .photo }) else {
                throw NASClientError.inaccessibleAsset
            }
            guard UTType(original.uniformTypeIdentifier)?.conforms(to: .heic) == true ||
                  UTType(original.uniformTypeIdentifier)?.conforms(to: .heif) == true else {
                throw NASClientError.notOriginalHEIC
            }
            let paired = resources.first(where: { $0.type == .pairedVideo })
            let expectsLive = asset.mediaSubtypes.contains(.photoLive)
            if expectsLive && paired == nil { throw NASClientError.inaccessibleAsset }

            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("ShalielieNAS-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            status = "从系统相册读取未修改原件（iCloud 资源可能需要下载）…"
            let sourcePhoto = directory.appendingPathComponent("source.HEIC")
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            try await PHAssetResourceManager.default().writeData(
                for: original, toFile: sourcePhoto, options: options)
            var sourceVideo: URL?
            if let paired {
                let url = directory.appendingPathComponent("source.MOV")
                try await PHAssetResourceManager.default().writeData(
                    for: paired, toFile: url, options: options)
                sourceVideo = url
            }

            status = "上传到飞牛 NAS，处理摄影风格及动态视频…"
            let multipart = directory.appendingPathComponent("upload.bin")
            let boundary = "Shalielie\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
            try MultipartBuilder.write(photo: sourcePhoto, video: sourceVideo,
                                       boundary: boundary, to: multipart)
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/form-data; boundary=\(boundary)",
                             forHTTPHeaderField: "Content-Type")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 900

            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 900
            config.timeoutIntervalForResource = 1200
            config.urlCache = nil
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }

            // Response is bounded by NAS upload limit. A future large-file client
            // should stream the HTTP response instead of holding it in Data.
            let (response, urlResponse) = try await session.upload(for: request, fromFile: multipart)
            guard let http = urlResponse as? HTTPURLResponse else {
                throw NASClientError.malformedOutput
            }
            guard http.statusCode == 200 else {
                let message = String(data: response.prefix(1000), encoding: .utf8) ?? "处理失败"
                throw NASClientError.badResponse(http.statusCode, message)
            }

            let photoURL = directory.appendingPathComponent("patched.HEIC")
            let videoURL: URL?
            if expectsLive {
                let movieURL = directory.appendingPathComponent("patched.MOV")
                try StoredZIP.unpackPair(response, photo: photoURL, video: movieURL)
                videoURL = movieURL
            } else {
                try response.write(to: photoURL, options: .atomic)
                videoURL = nil
            }
            guard try FileSniffer.isHEIC(photoURL) else {
                throw NASClientError.malformedOutput
            }
            if let videoURL, try !FileSniffer.isMOV(videoURL) {
                throw NASClientError.malformedOutput
            }

            status = "正在通过 Photos.framework 写入系统相册…"
            // Capture original capture metadata from the library as a fallback,
            // in addition to preserving the embedded EXIF in the processed HEIC.
            let capturedAt = asset.creationDate
            let capturedLocation = asset.location
            var createdIdentifier: String?
            try await PHPhotoLibrary.shared().performChanges {
                let item = PHAssetCreationRequest.forAsset()
                let photoOptions = PHAssetResourceCreationOptions()
                photoOptions.originalFilename = "Shalielie.HEIC"
                photoOptions.uniformTypeIdentifier = UTType.heic.identifier
                item.addResource(with: .photo, fileURL: photoURL, options: photoOptions)
                if let videoURL {
                    let videoOptions = PHAssetResourceCreationOptions()
                    videoOptions.originalFilename = "Shalielie.MOV"
                    videoOptions.uniformTypeIdentifier = UTType.quickTimeMovie.identifier
                    item.addResource(with: .pairedVideo, fileURL: videoURL, options: videoOptions)
                }
                if let capturedAt { item.creationDate = capturedAt }
                if let capturedLocation { item.location = capturedLocation }
                createdIdentifier = item.placeholderForCreatedAsset?.localIdentifier
            }

            if expectsLive {
                guard let createdIdentifier,
                      let saved = PHAsset.fetchAssets(
                        withLocalIdentifiers: [createdIdentifier], options: nil).firstObject,
                      saved.mediaSubtypes.contains(.photoLive) else {
                    throw NASClientError.noNativeLivePhoto
                }
                status = "已成功保存原生 Live Photo：HEIC + pairedVideo 属于同一系统相册资源。原件已保留。"
            } else {
                status = "已成功保存新的 HEIC 到系统相册。原件已保留。"
            }
        } catch {
            isError = true
            status = "失败：\(error.localizedDescription)"
        }
    }

    private func endpoint() throws -> URL {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else { throw NASClientError.invalidServer }

        if scheme == "http" {
            let segments = host.split(separator: ".").compactMap { Int($0) }
            let ipv4 = segments.count == 4 && segments.allSatisfy { 0 <= $0 && $0 <= 255 }
            let privateIPv4 = ipv4 &&
                (segments[0] == 10 ||
                 (segments[0] == 192 && segments[1] == 168) ||
                 (segments[0] == 172 && (16...31).contains(segments[1])) ||
                 (segments[0] == 100 && (64...127).contains(segments[1])))
            guard privateIPv4 || host.hasSuffix(".local") else {
                throw NASClientError.invalidServer
            }
        } else if scheme != "https" {
            throw NASClientError.invalidServer
        }
        return url.appendingPathComponent("api/patch")
    }
}

private enum FileSniffer {
    static func isHEIC(_ url: URL) throws -> Bool {
        let data = try prefix(url)
        guard data.count >= 12 else { return false }
        return Array(data[4..<8]) == Array("ftyp".utf8)
            && ["heic", "heix", "heim", "heis", "hevc", "hevx", "mif1", "msf1"]
                .contains(String(decoding: data[8..<12], as: UTF8.self))
    }
    static func isMOV(_ url: URL) throws -> Bool {
        let data = try prefix(url)
        return data.count >= 12 && Array(data[4..<8]) == Array("ftyp".utf8)
            && String(decoding: data[8..<12], as: UTF8.self) == "qt  "
    }
    private static func prefix(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: 16) ?? Data()
    }
}
