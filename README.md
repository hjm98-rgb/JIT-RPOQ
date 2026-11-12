# JIT RPOQ

iPad / iPhone 上的 **JIT 启动器**。导入配对文件后，点一下有 `get-task-allow` 权限的应用就能开 JIT；支持 iOS 26 的 RPP 配对 + LocalDevVPN 回环隧道，也支持经典配对文件。

## 它做了什么

| 能力 | 说明 |
| --- | --- |
| 配对文件导入 | 支持 `.mobiledevicepairing` / `.plist` / 粘贴 plist 文本；区分「经典配对文件」与「RPP 配对文件（iOS 26）」 |
| 配对校验 | 用 libidevice 的 `rp_pairing_file_read` 真实解析，坏文件直接报错 |
| 回环检测 | 探测 `10.7.0.1:49152`，判断 LocalDevVPN 是否已连上 |
| 应用扫描 | 通过 `installation_proxy` 读取设备上全部应用，并从 `Entitlements` 里的 `get-task-allow` 判断哪些能开 JIT |
| 一键开 JIT | 带调试启动 → debugserver `vAttach` → `D` 分离，应用获得 JIT |
| iOS 26 脚本模式 | 内置 `jit26.js`，处理 `brk #0xf00d` 的 JIT 页请求（`prepare_memory_region`） |
| 自动跳转 | `jitrpoq://enable?bundle=xxx`，应用里需要 JIT 时跳过来自动开 |
| 脚本系统 | JavaScriptCore + `send_command` / `prepare_memory_region` / `get_pid`，可导入自定义 `.js` |
| 额外功能 | 应用搜索 / 收藏 / 普通启动 / 复制跳转链接 / 实时日志 / 一键自检 |

## 使用顺序

1. 电脑用 `idevicepair` / 爱思助手 / iloader 生成配对文件，或让设备侧导出；
2. 打开 JIT RPOQ → 主页「导入配对文件」→ 选择是经典还是 RPP；
3. iOS 26：打开 **LocalDevVPN** 并连接（必须，否则 `10.7.0.1` 不可达）；
4. 「应用」页刷新 → 点目标应用 → 自动开 JIT；
5. 应用需要 JIT 时，让它打开 `jitrpoq://enable?bundle=<BundleID>`，会跳回启动器并自动开启。

## 两种配对文件

- **经典配对文件**：`idevicepair pair`、爱思、iTunes 时代留下的 `pairing record`，就是一张包含 `HostCertificate` / `HostPrivateKey` / `DeviceCertificate` / `RootCertificate` 的 plist。
- **RPP 配对文件**：iOS 17.4+/26 走 RemotePairing Protocol，同一张配对 plist 通过 RPP 隧道（`_remotepairing._tcp`，回环入口 `10.7.0.1:49152`）连到设备。iOS 26 上必须由 LocalDevVPN 建出这个回环入口。

## 技术链路

```
配对 plist ──rp_pairing_file_read──▶ RpPairingFile
        ──tunnel_create_rppairing(10.7.0.1:49152)──▶ Adapter + RSD Handshake
        ├─ heartbeat_connect_rsd  (调试心跳保活)
        ├─ remote_server_connect_rsd ─ process_control_launch_app(start_suspended)
        └─ debug_proxy_connect_rsd ─ vAttach / QStartNoAckMode
                                   └─ 脚本模式：brk #0xf00d 循环 + prepare_memory_region
```

JIT 的本质：应用以「被调试」状态启动并挂上 debugserver，`get-task-allow` 生效，进程拿到可执行内存权限；随后 detach，应用继续跑，JIT 保留。

## 云打包（GitHub Actions）

推送到 `main` 或手动触发 `Build JIT RPOQ`，runner 会：

1. `brew install xcodegen` → `xcodegen generate`
2. `xcodebuild -sdk iphoneos CODE_SIGNING_ALLOWED=NO` 编译未签名 arm64 包
3. 打成 `JITRPOQ-unsigned.ipa` 并上传 artifact

下载后用你自己的证书（全能签 / 小白签 / 个人证书）签名安装即可。

## 目录

```
JITRPOQ/
├── App/RootView.swift           # 入口 + TabView + URL Scheme
├── Core/JITEngine.swift         # RPP 隧道、应用扫描、开 JIT
├── Core/JITScriptRunner.swift   # JavaScriptCore 桥 + JIT 页写入
├── Core/AppModel.swift          # 状态、配对、自动开启
├── Views/                       # 主页 / 应用 / 脚本 / 日志
├── Resources/jit26.js           # 内置 iOS 26 JIT 脚本
└── idevice/                     # libidevice FFI（arm64 静态库 + 头 + modulemap）
```
