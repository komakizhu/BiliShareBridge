# BiliShareBridge

哔哩哔哩 iOS 分享与双开链接桥接动态库。项目只包含自研的 `BiliShareBridge`，不包含上游 `BiliBiliTweak`、8.89 专用 `BiliNetworkCompat` 或任何 B 站 App IPA。

## 功能

- 拦截微信 SDK 的分享请求，将支持的视频、番剧、直播间和用户空间链接交给 iOS 系统分享面板。
- 将分享完成、取消或失败结果回传给原客户端。
- 为蓝色分身在系统 URL 边界转换 `bilibili` 与 `bilitwin` scheme；蓝色 App 需在 `Info.plist` 设置 `BLPrivateScheme=bilitwin`。
- 日志只记录钩子和分享面板状态，不记录分享链接、账号资料或 SDK token。

## 构建注入包

需要 macOS、Xcode 命令行工具及 `dpkg-deb`。运行：

```sh
python3 src/build_sharebridge_packages.py
```

产物写入 `outputs/plugins/BiliShareBridge/1.1.1/`：

- `BiliShareBridge-TrollFools.zip`：包含 arm64 与 arm64e 通用动态库，供 TrollFools 注入。
- `BiliShareBridge_1.1.1_iphoneos-arm.deb`：有根越狱包。
- `BiliShareBridge_1.1.1_iphoneos-arm64.deb`：无根越狱包，安装到 `/var/jb`。
- `BiliShareBridge_1.1.1_iphoneos-arm64e.deb`：RootHide 包。

越狱包过滤粉色版 `tv.danmaku.bilianime` 和蓝色版 `tv.danmaku.bilianime.blue`。三种包的标识为 `com.github.komakizhu.bilisharebridge`。若目标 App 已内嵌此动态库，不要再注入，以免重复加载。

## 本机检查

链接和载荷解析可在 Mac 上检查：

```sh
clang -fobjc-arc -framework Foundation src/SharePayload.m src/test_payload.m -o /tmp/bilisharebridge-payload-test
/tmp/bilisharebridge-payload-test
```

包构建脚本会检查 arm64/arm64e 架构、代码签名、ZIP 完整性、DEB 架构、安装路径和 Bundle ID 过滤规则。当前没有在目标设备上验证注入、启动或微信发送。

## 许可证

桥接源码采用 GPL-3.0-only，完整条款见 [LICENSE](LICENSE)。

本项目是独立社区项目，与哔哩哔哩或腾讯无关联。
