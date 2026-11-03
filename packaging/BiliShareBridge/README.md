# BiliShareBridge 注入包

这些包只包含本仓库自研的 `BiliShareBridge.dylib`，不包含 TouchFriend 的 `BiliBiliTweak.dylib`，也不包含 8.89 专用的 `BiliNetworkCompat`。

## 文件类型

- `BiliShareBridge-TrollFools.zip`：解压后，在 TrollFools 中选择目标哔哩哔哩 App 并注入其中的 `.dylib`。也可直接使用同目录的 `.dylib`。
- `BiliShareBridge_1.1.1_iphoneos-arm.deb`：有根越狱包。
- `BiliShareBridge_1.1.1_iphoneos-arm64.deb`：无根越狱包，安装路径带 `/var/jb` 前缀。
- `BiliShareBridge_1.1.1_iphoneos-arm64e.deb`：RootHide 包，使用 RootHide 的包架构和安装布局。

构建产物位于 `outputs/plugins/BiliShareBridge/1.1.1/`。

三个越狱包共用 `com.github.komakizhu.bilisharebridge` 包标识，分别供对应架构的包管理器选择。

## 目标 App

越狱包的过滤规则包含粉色版 `tv.danmaku.bilianime` 和蓝色版 `tv.danmaku.bilianime.blue`。蓝色版需在 App 的 `Info.plist` 中保留 `BLPrivateScheme=bilitwin`，桥接库才能执行 scheme 转换。

已经内嵌 `BiliShareBridge.dylib` 的 App 不要再通过 TrollFools 或越狱包重复注入。独立注入包用于没有内嵌该库的目标 App。

## 构建

在 macOS 安装 Xcode 命令行工具和 `dpkg-deb` 后运行：

```sh
python3 src/build_sharebridge_packages.py
```

脚本会构建 arm64 与 arm64e 通用动态库，并检查架构、签名、依赖、ZIP 内容、DEB 架构、安装路径和 Bundle ID 过滤规则。它不会安装或操作手机。

本机打包核对不等于目标设备注入成功。当前包还没有在手机上验证加载、启动或微信发送。

自研源码采用 GPL-3.0-only，完整条款见本目录的 `LICENSE`。
