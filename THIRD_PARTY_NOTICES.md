# 第三方组件与许可

JIT RPOQ 本体以 MIT 许可证发布（见 `LICENSE`）。仓库里引用的第三方组件遵循各自许可证：

| 组件 | 位置 | 许可证 | 版权 |
| --- | --- | --- | --- |
| idevice（Rust + C FFI） | `idevice/libidevice_ffi.a`、`idevice/idevice.h` | MIT | Copyright (c) Jackson Coxson |
| libplist（由 idevice 静态链接，用于 plist 解析） | 同上（静态库内） | LGPL-2.1 | Copyright (c) libimobiledevice 项目 |
| JavaScriptCore / SwiftUI / Network.framework | 系统框架 | Apple SDK 条款 | Apple Inc. |

`Resources/jit26.js`、Swift 源码、界面与图标均为本项目原创，随 MIT 许可证一并授权。

如果你要再分发本项目的二进制，请保留本文件与 `LICENSE`。
