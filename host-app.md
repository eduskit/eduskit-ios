# 宿主 App 集成前置

> 整理对外 **SDK 集成文档** 时，本节必须写入接入检查清单。  
> Headless 与 UI Kit 都适用：系统隐私声明只能写在**宿主 App**，SDK / Framework 无法代填。

打开本地摄像头或麦克风前，宿主必须完成对应平台的隐私声明与权限声明。缺项会在开设备时失败，iOS 会直接 abort。

## iOS（必填）

iOS 在访问摄像头 / 麦克风时读取宿主 App `Info.plist` 的用途说明。XCFramework、SPM 包内的 `Info.plist` **不会**合并进 App。

| Key | 触发时机 | 缺 key 后果 |
|-----|----------|-------------|
| `NSCameraUsageDescription` | 开本地摄像头、`startLocalPreview`、TRTC 启动采集 | 进程 abort：`attempted to access privacy-sensitive data without a usage description` |
| `NSMicrophoneUsageDescription` | 开本地麦克风、TRTC 启动音频采集 | 同上 |

宿主 `Info.plist` 至少包含：

```xml
<key>NSCameraUsageDescription</key>
<string>This app uses the camera for classroom video.</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app uses the microphone for classroom audio.</string>
```

文案由集成方按产品说明改写；系统授权框直接展示该字符串。

Demo 已填写（可对照，勿原样用于正式产品）：

- `examples/ios-swift/EduSdkDemo/Info.plist`
- `examples/ios-oc/EduSdkDemo/Info.plist`

平台页：[iOS Headless](../headless-sdk/ios.md) · [iOS UI Kit](../ui-sdk/ios.md)

## 其他平台

后续整理集成文档时在此补齐 Android 运行时权限、Web `getUserMedia`、小程序 scope、鸿蒙 `ohos.permission` 等宿主声明。
