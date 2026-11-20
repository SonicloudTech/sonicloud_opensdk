# Flutter 3.41 与 iOS 启动迁移

- 目标：安装 FVM，为当前项目固定 Flutter 3.41 系列最新补丁版，适配 iOS 27 的 UIScene 启动要求。
- 方案：使用 FlutterSceneDelegate，在 Info.plist 声明单 Scene；在 didInitializeImplicitFlutterEngine 注册插件并创建原有通信通道。
- 文件分享从当前活动 Scene 获取窗口，避免依赖 AppDelegate.window。
- 保留原有 SDK 方法、通道名、事件格式和现有工作区改动；不升级到其他 Flutter 系列，不做无关格式化。
- 验证：确认 FVM SDK 版本，运行 Flutter 测试并与迁移前结果比较，构建 iOS Release；有可用 iOS 27 设备时验证冷启动。
