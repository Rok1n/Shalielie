import Foundation

/// NAS returns exactly two stored (uncompressed) ZIP members. The archive is
/// only an internal wire envelope: Photos receives the separate HEIC and MOV.
enum StoredZIP {
    static func unpackPair(_ data: Data, photo: URL, video: URL) throws {
        guard data.count >= 30, data.count <= 350 * 1024 * 1024 else {
            throw NASClientError.malformedOutput
        }
        var cursor = 0
        var havePhoto = false
        var haveVideo = false
        while cursor + 30 <= data.count {
            let signature = number32(data, at: cursor)
            if signature == 0x02014b50 || signature == 0x06054b50 { break }
            guard signature == 0x04034b50 else { throw NASClientError.malformedOutput }
            let flags = number16(data, at: cursor + 6)
            let compression = number16(data, at: cursor + 8)
            let size = number32(data, at: cursor + 18)
            let filenameLength = number16(data, at: cursor + 26)
            let extraLength = number16(data, at: cursor + 28)
            guard flags & 0x08 == 0, compression == 0,
                  size == number32(data, at: cursor + 22),
                  filenameLength > 0,
                  filenameLength <= data.count - cursor - 30,
                  extraLength <= data.count - cursor - 30 - filenameLength else {
                throw NASClientError.malformedOutput
            }
            let nameStart = cursor + 30
            let payloadStart = nameStart + filenameLength + extraLength
            guard size <= data.count - payloadStart else {
                throw NASClientError.malformedOutput
            }
            let name = String(decoding: data[nameStart..<(nameStart + filenameLength)],
                              as: UTF8.self).lowercased()
            let payload = data[payloadStart..<(payloadStart + size)]
            if name.hasSuffix(".heic") && !havePhoto {
                try Data(payload).write(to: photo, options: .atomic)
                havePhoto = true
            } else if name.hasSuffix(".mov") && !haveVideo {
                try Data(payload).write(to: video, options: .atomic)
                haveVideo = true
            } else {
                throw NASClientError.malformedOutput
            }
            cursor = payloadStart + size
        }
        guard havePhoto && haveVideo else { throw NASClientError.malformedOutput }
    }

    private static func number16(_ data: Data, at offset: Int) -> Int {
        Int(data[offset]) | (Int(data[offset + 1]) << 8)
    }

    private static func number32(_ data: Data, at offset: Int) -> Int {
        number16(data, at: offset) | (number16(data, at: offset + 2) << 16)
    }
}
