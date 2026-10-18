import SwiftUI
import Photos
import PhotosUI

@main
struct ShalielieNASApp: App {
    var body: some Scene {
        WindowGroup {
            NASContentView()
        }
    }
}

struct NASContentView: View {
    @StateObject private var model = NASPhotoProcessor()
    @State private var selected: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Section("飞牛 NAS") {
                    TextField("http://192.168.1.10:8766", text: $model.address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("NAS 访问令牌", text: $model.token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("只允许可信局域网 HTTP 或 HTTPS。访问令牌不写入用户偏好和钥匙串。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("选择原始照片") {
                    PhotosPicker(selection: $selected, matching: .images, preferredItemEncoding: .current) {
                        Label(selected == nil ? "从相册选择照片 / Live Photo" : "已选择照片（可重新选择）",
                              systemImage: "photo.on.rectangle")
                    }
                    Text("如果选中的是 Live Photo，App 会从照片图库直接取原始 HEIC 和配对 MOV，无需手动解压 ZIP。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button {
                        Task { await model.process(selected?.itemIdentifier) }
                    } label: {
                        HStack {
                            if model.isBusy { ProgressView() }
                            Text(model.isBusy ? "正在处理…" : "NAS 处理并原生保存到相册")
                        }
                    }
                    .disabled(model.isBusy || selected == nil || model.address.isEmpty || model.token.isEmpty)

                    Text(model.status)
                        .foregroundStyle(model.isError ? Color.red : Color.secondary)
                        .textSelection(.enabled)
                        .font(.callout)
                }
                Section("保存方式") {
                    Text("程序使用系统 Photos.framework 将 HEIC 及 pairedVideo 写成同一个 Live Photo 资源。完成后会检查系统是否识别为动态照片；不会把 ZIP 当作照片存入相册。原始照片不删除。")
                        .font(.footnote)
                }
            }
            .navigationTitle("Shalielie NAS")
        }
    }
}
