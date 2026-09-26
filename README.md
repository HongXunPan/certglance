# SSL 证书看板

macOS 26 原生小组件，用于查看域名证书到期情况与接收本地提醒。

当前为功能开发阶段：工程可做无签名构建，正式签名、DMG、更新与安装后共享数据验收尚未完成。技术边界见 [工程代码技术选型](docs/工程代码技术选型.md)。

## 开发验证

在本目录运行：

```sh
plutil -lint SSLWidget.xcodeproj/project.pbxproj App/Info.plist Widget/Info.plist App/App.entitlements Widget/Widget.entitlements
xcrun swift format lint --recursive --strict App Widget Shared
xcodebuild -project SSLWidget.xcodeproj -scheme SSLWidget -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
xcrun swiftc -swift-version 6 -parse-as-library -module-cache-path .build/SwiftModuleCache -Xcc -fmodules-cache-path=.build/ClangModuleCache Shared/DomainModels.swift Shared/NotificationPolicy.swift Tests/ModelChecks.swift -o .build/ModelChecks && .build/ModelChecks
```

无签名构建仅证明源码和工程能编译，不能证明系统小组件注册、共享容器和通知投递可用。
