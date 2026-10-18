# Shalielie fnOS / x86_64 NAS 版

这是 Rok1n/Shalielie 基于上游 nathanatgit/Shalielie v0.7.0 的 Docker Web 适配层。保留原有 HEIC/MOV 摄影风格处理引擎，新增移动网页上传、访问令牌、Live Photo 校验、下载与临时文件清理。**适用范围是已安装 Docker + Compose 的飞牛 fnOS x86_64；这不是飞牛原生 .fpk 安装包。**

**如需真正的相册 Live Photo，优先使用 [iPhone 原生客户端](../ios-client/README.zh-CN.md)。网页下载 ZIP 只是手动导出后备方案，不会自动写入 iOS 动态照片。**

## 兼容性和重要限制

- 主机：Intel/AMD x86_64 NAS，Docker 的 linux/amd64；建议至少 4 GB 可用内存，默认容器上限 3 GB。FFmpeg/HEVC 视频处理耗费 RAM/CPU。
- 输入：原始 iPhone HEIC；Live Photo 必须额外提交同一张照片对应的原始 MOV。服务检查两份文件的内部 Live Photo ID，拒绝混搭；网页从相册选择 Live Photo 不保证能同时读到其 MOV，推荐通过「文件」App 选择两份源文件。
- 输出：静态图片直接下载 HEIC；Live Photo 输出一个包含 HEIC + MOV 的 ZIP。Safari 下载 ZIP 到「文件」App 不意味着「照片」App 会自动把文件配成 Live Photo。恢复动态相片需要在目标手机上验证可靠的导入方式，保留原件。
- 元数据：原引擎保留图像本体、已有 Exif/GPS/辅助数据，并增加必要的 Apple 摄影风格 MakerNote 及内部结构；任何改变元数据的处理都无法做到源文件逐字节完全相同。某些未知的非标准元数据可能无法保证。
- 摄影风格及 iOS 27 Texture/Grain 能否正常编辑取决于原始文件、iPhone 和 iOS；这是实验项目。

## 一、准备飞牛

从 fnOS 应用中心安装 Docker，并启用 Docker Compose 项目功能。NAS 终端中确认：

    uname -m
    docker version
    docker compose version

第一条应是 x86_64。容器包含 Python 3.12、ffmpeg（含 libx265）和 heif-convert，宿主机无需安装这些依赖。不要运行用于「在 Docker 里安装另一个 fnOS 虚拟机」的镜像。

## 二、安装

    git clone https://github.com/Rok1n/Shalielie.git
    cd Shalielie
    git switch feat/fnos-x86-web-live-photo
    cd nas
    cp .env.example .env
    python3 -c "import secrets; print(secrets.token_urlsafe(36))"

将最后一行产生的随机字符串粘贴进 nas/.env，替换 SHALIELIE_TOKEN 的占位符。不要将令牌或 .env 提交到 GitHub。若 NAS 没有 python3，可在其他可信设备生成随机令牌。

    chmod 600 .env
    docker compose -f compose.yaml config --quiet
    docker compose -f compose.yaml build
    docker compose -f compose.yaml up -d
    docker compose -f compose.yaml ps

浏览器打开 http://NAS的局域网IP:8766/。在页面填入 .env 的访问令牌，并从「文件」App 选择照片。端口默认 8766；冲突时修改 .env 中 SHALIELIE_PORT，然后执行 docker compose up -d --force-recreate。

也可以在飞牛 Docker 的 Compose/项目管理界面导入 nas/compose.yaml。由于构建上下文是上一级目录，项目文件必须保留在完整仓库的 nas/ 目录中，不能单独复制 compose.yaml 到空目录使用。第一次部署需要能够下载 Docker 基础镜像和 Debian 软件包。若你已将本分支合并到 master，今后不必执行 git switch 该分支。

## 三、手机处理步骤

1. iPhone 与 NAS 在同一可信局域网，从 Safari 打开 NAS Web 页面。
2. 输入访问令牌，选择原始 HEIC。如果从照片选择器上传得到 JPEG，需先从可信路径将未修改原始文件导出到「文件」App，再从这里选择 HEIC。
3. 对于 Live Photo，额外选择同一拍摄的原始 MOV。Mac「照片」App 中的「文件 → 导出 → 导出未修改的原件」可将 Live Photo 导出成照片和视频两个独立文件。然后通过文件共享将它们传入手机的「文件」App。
4. 提交并保持浏览器打开，下载处理结果。Safari 一般将结果保存到「文件」App 的下载目录；页面也保留手动下载链接。
5. 普通 HEIC 可按保留原格式的方式导入相册；Live Photo 解压 ZIP 后得到两份相同基本文件名的 HEIC/MOV。**不能保证直接在 iOS 文件管理器中选择「存储图像」即可恢复动态照片。** 建议先在 Mac 或目标 iOS 设备测试导入、拍摄时间、GPS 与动态效果，再处理重要文件。

## 四、隐私、保留和资源

工作链路：浏览器上传 → HTTP 上传临时暂存 → /tmp/shalielie-nas/job-*/ 处理 → 下载 HEIC 或 ZIP → 响应完成后移除任务临时目录。没有数据库、相册索引、NAS 照片卷挂载、持久照片输出目录；默认关闭 Web 访问日志。重启时清理中断任务残留。任务执行中源图、输出和 ZIP 可能并存，**会暂时消耗磁盘空间和内存**，并非零占用。容器 Writable Layer、Docker 镜像和系统日志也会使用存储空间。

默认限制：一次请求 320 MB，HEIC 最多 160 MB，MOV 受剩余额度约束；一次只运行一个转换任务；单次处理最长 600 秒。通过 .env 更改 SHALIELIE_MAX_UPLOAD_MB 和 SHALIELIE_TIMEOUT。根据 NAS 硬盘和内存合理设置限额。

必须携带 SHALIELIE_TOKEN 才能调用 API，但默认 HTTP **不是加密传输**。建议只通过可信家庭 Wi-Fi 或 VPN 使用，**不要直接将 8766 端口映射到公网，不要开启 UPnP 公网暴露**。公网使用请配 TLS 反代、VPN、限流和额外的访问控制。任何控制 NAS Docker/root 权限的人可能读取处理中照片。请谨慎处理含 GPS、人物和私人信息的原片。

## 五、检查和维护

    docker compose -f compose.yaml logs --tail=100
    docker compose -f compose.yaml ps
    curl http://127.0.0.1:8766/healthz
    docker compose -f compose.yaml restart
    docker compose -f compose.yaml down

401 为令牌错误；413 为上传限制；415 表示上传了 JPEG/PNG 或无效 MOV；422 表示上游照片不支持、已处理、文件结构不符合要求或 Live Photo ID 不匹配；429 表示仍在处理其他请求；504 表示超时。端口无法访问先检查主机地址、fnOS 防火墙、网络隔离和容器日志。若因断电等造成临时残留，可检查容器内部 /tmp/shalielie-nas；下次服务启动会执行清理。

更新：在仓库根目录 git pull，然后回 nas/ 运行 docker compose -f compose.yaml up -d --build。退出/回滚时请保留 .env 私有配置。**此版本未在你的具体 fnOS NAS 或 iOS 设备上做实机端到端认证；先用可公开的样片测试。**

## 开发与回归测试

    pip install -r nas/requirements.txt httpx
    SHALIELIE_TOKEN=only-for-local-tests-1234567890 python -m unittest discover -s nas/tests -v

本适配不修改上游原有网页版、命令行或 Shortcuts Server 的调用方式。
