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

教学小黑板的私有 checkpoint 使用独立对象存储桶和 60 秒签名 URL，仍通过白板的
`workspace_url` 下载 gzip。此工具尚未开放，私有下载的客户端运行验收仍在进行。
集成时需要把实际私有桶 HTTPS 域名加入 Web CSP/connect-src、小程序下载/请求域名及
宿主网络白名单，并在私有桶配置允许宿主来源的 CORS。不要把签名 URL 写入公开消息或
日志；链接过期后重新读取授权 checkpoint 取得新地址，不能改用公开 CDN。
Android/iOS、Harmony、Desktop、Flutter/RN 也需要使用返回的私有地址，并逐端验证下载、
checksum/gzip 处理与过期刷新。已签发 URL 到期前仍可使用，撤销授权会阻止取得新地址。

后续整理集成文档时在此补齐 Android 运行时权限、Web `getUserMedia`、鸿蒙 `ohos.permission` 等宿主声明。

## 微信小程序（必填）

| 项 | 时机 | 缺项后果 |
|---|---|---|
| `scope.camera` | 本地预览、上台视频、设备检测 | 摄像头授权失败，RTC 本地画面无法采集 |
| `scope.record` | 上台音频、设备检测 | 麦克风授权失败 |
| request 合法域名 | `backendUrl`、client-api、OpenIM、遥测 | `wx.request` 失败 |
| downloadFile 合法域名 | 教学工具提示音、课件资源 | 音频/文件下载失败 |
| socket 合法域名 | OpenIM `wss` | IM 无法连接 |
| web-view 业务域名 | 仅当白板仍走 H5 桥时 | 白板页无法打开 |
| TRTC 小程序插件 | 台上 RTC | 无法进 TRTC 房 |

系统授权文案写在宿主 `app.json` 的 `permission` 中，SDK 无法代填。Demo 见 `examples/wechat-classroom/app.json`。

### 小程序教学工具提示音

将 EduSDK backendUrl 域名同时加入小程序 request 和 downloadFile 允许域名。固定提示音为公开的哈希 URL 资源，不上传个人数据、不发送用户凭据；SDK 临时缓存约 21 KB 音频并在课堂声音所有者释放时删除。播放器遵守系统静音设置，切后台停止播放。请将 edu_service 的 SDK Assets 路由与对应 SDK 产物一同部署；平台能力缺失或下载失败时工具操作继续，提示音不会换源补播。


### Web 持续听课配置入口（实施中）

Web Headless 与 UI Options 现支持 `continuation: () => Configure | Promise<Configure>`，
返回值遵守 `schema/classroom-continuation.yaml`。每次初始化/重试都在 Core init 后、后台
join 前调用，便于重新取得实际环境和能力；采集或 Core 校验失败会阻止进课，不静默忽略。
偏好 scope 的 application、tenant、account、device 应使用宿主稳定且隔离的标识，不传
用户 Token 或临时随机值代替账号/设备。宿主提供首次默认值或禁用能力，已保存偏好及系统
限制仍由 Core 处理。省略此选项表示未启用持续听课；普通前台课堂不因此被禁用。

`continuationWindow` 是实际系统窗口端口；配置中的 available 必须有真实平台能力支持，
配置本身不授予浏览器或系统权限。后续环境变化仍通过 `requestClassroomContinuation`
提交 environment 输入。默认 UI 会在宿主没有自带环境订阅时安装观察器，并在 Document PiP
可用时安装实时舞台端口。这仍不表示浏览器已经允许自动进入。宿主仍需在自身隐私声明说明后台听课、开麦/摄像头、
屏幕共享的用途和关闭方式；本 SDK 配置不能替代宿主声明或系统授权。

启用该配置时，Web UI 白板会使用 Core 当前许可装配独立 Web Audio 输出，接收播放 effect，
并等待 Room/AudioContext 清理。需要更新到包含 MediaAudioSession 工厂的新 DrawsKit 产物；
当前本地源码已接线，正式产物与真实背景音频验收尚未完成。


Web Document PiP 的原生关闭可能没有可靠原因，宿主应保留 `unknown`，不能统一当作
用户点击或系统中断。Core 对非预期 unknown 关闭停止麦摄与屏幕共享，按设置继续听课，
保留返回入口并抑制本轮后台重开。自定义“返回课堂”按钮应通过窗口端口的明确 restore
路径关闭，以保留可确认的恢复语义。该能力不替代宿主对权限与采集状态的可见提示。


默认 Web UI 在 continuation 已配置、没有宿主自定义 continuationWindow、且容器窗口
支持 Document PiP 时，会安装自己的实时舞台窗口端口；宿主无需自行搬移 Vue/Canvas。
这仅提供窗口与舞台能力，不自动证明浏览器允许后台自动进入。自定义端口及注入 Headless
仍由宿主负责配置实际能力与回执。课堂 destroy 会请求原生关闭，关闭确认由平台回执决定。

Web/共享 TS 可通过 `continuationEnvironment(report)` 在配置成功后订阅后续环境变化，
返回同步解绑函数。report 接收完整 environment 输入（含实际 capabilities），返回Promise，
宿主应处理失败；不要把无法识别的锁屏/权限当作允许。SDK在重试和销毁时解绑并隔离旧
runtime回调。省略订阅不会自动获得浏览器环境检测能力。

UI 包提供 `createBrowserContinuationEnvironment({document, sample, onError})`，返回值可传给
`continuationEnvironment`。它在订阅时和 visibilitychange 时采样，并仅用 document 的
visibilityState 更新 app_foreground；sample 仍须提供真实 lock_state、classroom_visible、
window_minimized 和 capabilities。异步旧样本与卸载后的回调被隔离，错误交给 onError。
该适配器不会请求权限，不把隐藏页面推断为锁屏，也不能单凭 API 存在宣称自动 PiP 可用。

上述浏览器适配器还接受 `subscribeChanges(changed)`：宿主可在锁屏检测、权限变化或
课堂路由显隐变化时调用 changed，触发新的完整事实采集，不必伪造 visibilitychange。
该订阅也必须返回同步解绑函数；注册失败会撤销浏览器监听，正常销毁只解绑一次。

锁屏观察使用 `observeBrowserScreenLock(detector, permissionStatus, changed)`，其中
permissionStatus 来自 `navigator.permissions.query({name:'idle-detection'})`。权限运行中
撤销会立即停止检测并通知unknown；再次授权需要创建新的观察者，不自动恢复旧owner。
调用方须处理ready拒绝，并在生命周期结束时dispose。该函数不会自行请求授权。
# Web 自动 PiP 原生触发入口

`@eduskit/ui` 导出 `observePipMediaAction({ session, triggered, onError })`，用于宿主将
`navigator.mediaSession` 的 `enterpictureinpicture` action 独占委托给课堂。注册失败直接
抛错，不能报告能力可用。返回的清理函数撤销 action；同一个 MediaSession 不允许重复
课堂 owner。浏览器没有读取旧 handler 的接口，宿主不能同时用其他播放器覆盖此 action。

`triggered` 同步接收浏览器原始 `reason`（可能缺失），接入方仍须经过 Core 决策，不能
把所有回调都当作用户手动请求，否则会绕过关闭自动小窗的偏好。注册成功只代表 action
受支持，不代表自动进入已获授权。当前入口尚未与默认课堂配置/Core 请求完成端到端装配；
异步 Core 往返后的原生激活有效性也需真实浏览器验证，不能用单元测试宣称自动 PiP 可用。

Chrome 自动 PiP 还取决于采集或播放状态、站点设置等条件；不得为了达到条件擅自开麦、
开摄或播放无意义音频。依据：[Chrome 媒体播放自动 PiP](https://developer.chrome.com/blog/automatic-picture-in-picture-media-playback)、
[视频会议自动 PiP](https://developer.chrome.com/blog/automatic-picture-in-picture)。

浏览器环境装配可使用 `createBrowserContinuationEnvironment` 的可选 `mediaSession`：
显式传入 `navigator.mediaSession` 后，原生 action 触发该次 `sample(trigger)`，其中
`trigger.reason` 为浏览器原值。初始、可见性及宿主环境事件采样不携带 trigger；不要
缓存一次触发作为永久授权。采样结果仍通过原有 environment 输入交给 Core，适配器
不会将 action 改成手动 minimize，也不会自行将 automatic_window 设为 available。
注册不支持会失败并释放此前订阅；清理时会同时释放原生 action 和宿主事件订阅。
默认 UI 在 continuation 已配置且宿主没有传入 `continuationEnvironment` 时安装该观察器。
锁屏只在 `idle-detection` 权限已经是 granted 时读取 `screenState`，否则保持 unknown；标签隐藏只改变可见性。
Document PiP 存在时才把 `whiteboard_window` 报为 available，并只在此时注册 mediaSession。
桌面指针环境把后台麦、摄和共享报为 available；手机浏览器报 unavailable，后台音频保持 unknown。
自动进入仍受浏览器手势限制。本轮用单元测试覆盖了隐藏标签不是锁屏，没有在真实 Chrome 里走完进小窗。

Web entry capability sampling: merge
`sampleDocumentPipEntryCapabilities(window, trigger)` into the capabilities returned
by `createBrowserContinuationEnvironment.sample(trigger)`. It samples only
`manual_window` and `automatic_window`; the host must still supply verified audio,
capture, realtime whiteboard and lock facts. Automatic entry requires a native
Media Session trigger and current transient activation. API presence alone never
grants it. Do not cache the returned entry flags as persistent permission. Core
still evaluates saved preferences, host policy, lifecycle and suppression.


### Android / iOS 持续听课接入状态（实施中）

当前移动 Headless 提供创建参数 `continuation`、`requestClassroomContinuation`、只读投影和
`continuationWindow` 端口。Android 官方 Activity 在启用 continuation 时绑定系统 PiP 端口和前台媒体服务；
iOS 官方 ViewController 绑定 AVKit 视频通话内容源，并在明确离课前保留同一 `ClassroomController`。
不要仅配置 `supportsPictureInPicture` 或后台音频模式，就向用户展示“已支持后台听课”。

创建参数 `continuation` 接收返回严格 `configure` JSON 的函数：Android 为 `() -> String`，
iOS 为 `() throws -> String`。SDK 在工作线程调用的 initialize 内、Core 初始化后执行该函数，
成功前拒绝进课。采集或 Core 校验失败会抛错并退休当前实例；重试需新建 SDK，不能在
失败实例上继续 enterClassroom。省略该参数表示未配置此能力，并非自动启用后台听课。

接入顺序是：提供配置工厂，在工作线程完成 initialize，确认
偏好存储投影就绪，再提交环境事实。配置的 scope 必须由宿主提供稳定的应用、租户、
账号与设备标识，不能使用测试中的随机 scope；系统权限和能力每次按实际情况采集。
Android 的 `ContinuationEnvironmentReporter` 必须在配置成功后创建，构造与系统查询
在工作线程执行；分别报告宿主应用是否在前台、课堂是否可见，不能将课堂隐藏直接当作
整个应用后台。退出当前 SDK 生命周期时关闭 reporter，防止向已退休实例继续投递。

宿主负责应用清单、系统后台能力声明及用途说明；SDK 负责统一产品策略、权限事实输入
及失败降级。配置不会代替系统授权，也不能保证后台存活。Android 生产 Activity 与调试 Activity
使用同一窗口端口。API 36 模拟器已观察到系统进入和按请求身份退出的回执。真机上的锁屏、关摄、
停止共享和三种内容切换还没有在已加入的课堂里跑通，当前不应作为可发布能力宣称。

播放 effect 的 `playback` 通道在同一个 SDK runtime 内保持 FIFO，跨课堂取消也不能
丢弃执行链或创建并行替代队列。先完成在途输出后再执行后续目标；`lifecycle` 清理
屏障独立执行。最终 runtime 销毁必须隔离迟到回执，不能送入新建的 Core 实例。


移动 Headless 另提供 `continuationEnvironment`，必须与 `continuation` 一起设置。
SDK 在配置成功后于专用工作线程调用订阅函数；Android 返回 `AutoCloseable`，iOS 返回
解绑闭包。report 可在任意线程调用，Android 返回 `CompletableFuture<Void>`，iOS 通过
结果回调告知 Core 是否接受输入；不要在订阅注册函数内同步等待 report 完成。
SDK 将输入串行送入 Core，销毁立即隔离后续输入，并在工作线程清理订阅。若销毁发生在
注册期间，迟到返回的订阅句柄也会被清理。注册失败会使初始化失败、退休当前 SDK；
注册函数抛错前已取得的资源需自行释放，因为未返回的句柄 SDK 无法取得。
该入口不自动推测应用后台、锁屏或 PiP 权限。官方 UI Kit 已按当前系统事实提交环境和能力。


Android 官方课堂入口新增 `EduClassroomOptions.continuation: EduContinuationOptions?`。
启用时传入稳定 tenantId/deviceId，application/account 分别使用 appId/userId；可设置
allowWindow/allowBackgroundAudio/allowBackgroundMicrophone，以及可选首次媒体 defaults。
初始化提交给 Core，已保存的用户选择仍由 Core 决定，不在 UI Kit 覆盖。
Activity 的 onStart/onStop 上报课堂可见性，AndroidX ProcessLifecycleOwner 单独提供
应用进程可见性；其后台通知存在延迟（[官方说明](https://developer.android.com/reference/androidx/lifecycle/ProcessLifecycleOwner)）。
这不是多进程全局检测，也不把窗口失焦当后台。重试重新采样锁屏/环境，旧订阅不能清掉
新 SDK 的订阅。

Android 官方课堂按窗口声明、实时舞台、通知权限和录音权限分别上报能力。设备支持 PiP 本身不等于课堂端口可用。
`background_camera` 与 `background_screen_share` 保持 unavailable：没有相机前台服务，也没有持有 MediaProjection 的服务。
因此切到后台时 Core 会停止共享。前台媒体服务只保留现有 session，不决定关麦、关摄或离课。
iOS 在系统 PiP 可用时，窗口与白板窗口能力同值；相机和屏幕共享后台能力保持 unavailable。


iOS 官方入口同样接受 `EduClassroomOptions.continuation: EduContinuationOptions?`，字段与
Android 对齐并支持 Objective-C。ViewController 报告课堂展示，Scene 通知采集各窗口
前后台状态；没有 Scene session 的 UIKit 应用使用 UIApplication 生命周期。UI 线程只
采集原生事实，JSON 编码及 SDK 投递在串行工作线程，旧订阅清理按身份隔离。

锁屏事实采用保守边界：受保护数据不可用时可确认 locked；后台/临时失活无法可靠确认
锁屏时上报 unknown，不缓存前台 unlocked。`isProtectedDataAvailable=true` 本身不能证明
解锁，因为未启用保护时也为 true（[Apple 文档](https://developer.apple.com/documentation/uikit/uiapplication/isprotecteddataavailable)）。
iOS 15 起，只有已经在跑的白板 surface、老师视频或远端共享才会进入 AVKit 小窗。没有现成画面时进入失败，不使用静态层。
关闭展示不等于离课；明确离课才销毁 controller。后台音频只在 Core 已经允许播放时激活会话，不替换 RTC 的 category。
音频中断只提示，不改偏好。另一个 Scene 不算本课堂前台，方向更新只发给课堂自己的 windowScene。
未知锁屏仍由 Core 保守关闭采集，不能据此承诺后台持续共享或发言。模拟器完成了配置和隐藏展示测试，没有真机画中画闭环。

### 持续听课验证边界

原目标尚未完成。策略仍只在 Core。下面是本轮可复核的证据，编译成功不计入。

| 平台 | 结论 | 本轮证据 |
| --- | --- | --- |
| Android | 需修改，生产端口和前台服务已接上 | API 36 模拟器 `ContinuationWindowPortTest` 通过；Headless 持续听课仪器测试 9 项通过；官方 UI `ClassroomContinuationBindingTest` 2 项通过。没有真机课堂的锁屏、关摄、停共享和三种内容切换 |
| iOS | 需修改，AVKit 内容源和会话保留已接上 | iPhone 17 模拟器 `ClassroomContinuationBindingTest` 2 项、`ContinuationSdkIntegrationTest` 3 项通过。没有真机画中画 |
| Web | 共享策略已覆盖，默认 UI 补了环境和 Document PiP | `classroom-pip-mount` 与 `web-continuation-environment` 通过。没有真实 Chrome 自动进入 |
| Qt | 共享策略已覆盖，桌面窗口流程已在代码中 | 本轮没有重新构建或跑 `edusdk_ui_qt_continuation_flow_test`。macOS 结果也不能代表 Windows/Linux |
| Electron | 只做 Qt Launcher | `platforms/desktop/electron` 的 launcher 与构建工具测试通过。没有签名、Windows 安装和 sdk-api 身份交接 |
| Harmony / 微信 / 支付宝 / 抖音 | 不适用为系统小窗 | 没有窗口端口。宿主不得把窗口能力报成 available。未核实各自后台音频，因此不能承诺继续听课 |
| Flutter / RN | 不适用 | 不实现课堂，只在将来的桥接里转发已有 Headless 端口 |

主线程只发布界面状态。Android 环境采样、包信息查询和音频焦点在工作线程；进入 PiP 的界面操作留在主线程。iOS 的 JSON 和环境投递在 `edusdk.ui.continuation.environment`，AVKit 和视图迁移留在主线程，且不调用 Core。Web 环境采样不在画布帧回调里。渲染线程不等待 Core、网络或解码。

DrawsKit 正式依赖没有切换。Maven 上的 0.2.5 缺少当前房间媒体接口，本轮 Android 构建使用本地源码 `EDUSDK_DRAWSKIT_SOURCE`。这不是发布验收。四端小窗白板的实时翻页、绘制和课件媒体也还没有产品级证据。
