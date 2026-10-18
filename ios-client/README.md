# Native iPhone Live Photo importer for fnOS NAS

SwiftUI source for iOS 17+; build with Xcode 15+ and XcodeGen. This app picks an original Photos asset, exports the HEIC and original .pairedVideo resource, sends them to the NAS, and saves the processed result via PHAssetCreationRequest.addResource(.photo) and .pairedVideo. The HTTP ZIP is only an internal transport envelope; **the saved asset is created natively**, checked for PHAsset.mediaSubtypes.photoLive. Originals are left untouched.

    cd ios-client
    xcodegen generate
    open ShalielieNAS.xcodeproj

Set your own development Team and unique bundle identifier, run on a connected iPhone, and configure the trusted LAN NAS address and token. This is source code, not a signed IPA; actual iPhone validation is still required. Photo/GPS metadata is preserved where possible. Response files are temporarily buffered in iPhone RAM and deleted from the app's temporary directory afterward.

See [Chinese instructions](README.zh-CN.md).
