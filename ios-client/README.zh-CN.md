# iPhone 原生 Live Photo 导入客户端

这一目录是飞牛 NAS 版的 iOS 原生客户端源码。**Safari 下载 ZIP 并不等于在相册中获得 Live Photo**，所以这里直接用 Photos.framework 的 PHAssetCreationRequest 添加 .photo 与 .pairedVideo 两项资源，创建一张真正的系统 Live Photo，并检查 PHAsset.mediaSubtypes 是否含 .photoLive。

用户在 App 中直接选择相册原始 Live Photo；App 读取原始 HEIC 和配对 MOV，发送给 NAS 处理。NAS 返回的 ZIP **仅作 App 内部网络传输载体**，App 解出两个文件，使用照片图库原生 API 写入同一个资产。用户最终只在「照片」App 看到新的 Live Photo，不会把 ZIP 保存进相册。原片保留。

## 安装（需要 Mac 和 Xcode）

适用 iOS 17 或更新版本、Xcode 15+。安装 XcodeGen（Mac 上可以通过 brew install xcodegen）。先按 ../nas/README.zh-CN.md 在 fnOS x86_64 中部署 NAS 处理服务。

    cd ios-client
    xcodegen generate
    open ShalielieNAS.xcodeproj

在 Xcode 选中 ShalielieNAS target → Signing & Capabilities，设置自己的 Apple Team，将 Bundle Identifier 改为唯一标识，例如 com.yourname.ShalielieNAS。连接 iPhone，选择实际设备，点击 Run 安装调试版 App；按系统提示信任开发者及授权照片库（全部或包含目标照片的有限权限）、本地网络。**这不是预签名的 IPA，NAS 本身无法替代 iOS 端安装和签名流程。**

## 使用步骤

1. App 内输入 NAS 网址，例如 http://192.168.1.10:8766，以及 NAS 部署时随机生成的 SHALIELIE_TOKEN。
2. 直接从系统相册选择原始 Live Photo。不需要先导出 HEIC/MOV，也不需要手动解压 ZIP。
3. 点击「NAS 处理并原生保存到相册」。客户端通过 PHAssetResourceManager.writeData 取得照片 HEIC 和视频 .pairedVideo，NAS 检查内部 Live Photo ID 匹配并分别处理两个文件。
4. App 收到结果后，用 PHAssetCreationRequest.addResource(with: .photo) 和 addResource(with: .pairedVideo) 导入。保存成功后再次查询 PHAsset.mediaSubtypes 是否含 .photoLive。
5. 回到「照片」App，确认新照片有 Live 标识、可以长按播放，打开编辑验证摄影风格，退出后重开仍可播放，时间/GPS 合理且原件未被覆盖。

## 限制

- **需要安装原生 iOS App**：普通 Safari/HTML 没有直接创建 Photos Live Photo 的权限；NAS 只负责计算。
- 只有真实原始 HEIC 和配套 MOV 才可以完成原生导入，JPEG 不会被伪装为 Live Photo。iCloud 中的原件可能需要联网读取。
- 原上游摄影风格修改、Live Photo 视频构建依然是实验性代码，不能保证所有拍摄设备、iOS 版本、图片效果都成功。Apple 可能重写部分元数据，EXIF 的逐标签完全保留还没有实机验证。App 会补录原图库的拍摄日期与 GPS。
- iPhone 临时上传文件在任务结束时删除，NAS 无永久照片卷和历史图库。客户端目前把服务器响应临时缓存在 RAM 中，大 Live Photo 可能产生内存压力；不适合大量并发。
- 令牌不持久储存。HTTP 明文连接只接受 RFC1918 局域网地址、100.64/10 内部 VPN 地址或 .local 域名；优先选择可信局域网或私有 VPN，不要直接把 NAS 端口转发到互联网。
- 此实现尚未通过 Mac Xcode 与真实 iPhone 的编译和设备验证，因此仍作为开发版本提供。要正式使用需验证源文件保真和相册动态照片回写。

## 故障排查

403/401：检查访问 token 和 NAS 地址；415：输入不是原始 HEIC 或 MOV；422：原引擎无法处理当前照片，或配对 ID 异常；App 报「未确认动态照片」：系统没有识别 .photoLive，不能认为转换成功。网络不通检查 NAS 防火墙、8766 端口、iOS 本地网络授权及是否错误使用公网 HTTP。
