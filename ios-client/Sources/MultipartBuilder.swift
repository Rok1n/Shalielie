import Foundation

/// Builds the multipart upload body on disk, without loading originals into RAM.
enum MultipartBuilder {
    static func write(photo: URL, video: URL?, boundary: String, to target: URL) throws {
        _ = FileManager.default.createFile(atPath: target.path, contents: nil)
        let output = try FileHandle(forWritingTo: target)
        defer { try? output.close() }
        try append(photo, field: "photo", filename: "source.HEIC",
                   mime: "image/heic", boundary: boundary, into: output)
        if let video {
            try append(video, field: "video", filename: "source.MOV",
                       mime: "video/quicktime", boundary: boundary, into: output)
        }
        try output.write(contentsOf: Data("--\(boundary)--\r\n".utf8))
    }

    private static func append(_ source: URL, field: String, filename: String,
                               mime: String, boundary: String,
                               into output: FileHandle) throws {
        let lines = [
            "--\(boundary)",
            "Content-Disposition: form-data; name=\"\(field)\"; filename=\"\(filename)\"",
            "Content-Type: \(mime)", "", ""
        ]
        try output.write(contentsOf: Data(lines.joined(separator: "\r\n").utf8))
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
        try output.write(contentsOf: Data("\r\n".utf8))
    }
}
