# DuckPilot 0.4.1：连接鸭子热点后自动连接

手机先在系统 Wi-Fi 设置连上鸭子热点，再打开 DuckPilot（已打开时切换过来也可以）。App 自动读取该 Wi-Fi 的 IPv4 网关，在网关 UDP 20043 探测 DuckPilot 服务，验证应答后自动填好主板地址、控制和相机端口，建立遥测与视频连接。无需重新输入 IP 或配对密钥。

默认 AP 地址为 10.42.0.1；复用其他 AP 配置时，以手机实际收到的网关为准，不把地址写死。SSID 可以改名，不依赖“DuckPilot”这个名字来判断。普通家用路由器没有对应服务应答时，不会自动建立机器人控制会话；STA 模式继续支持手动地址连接。

## 同时更新 App 和主板接入层

安装 `DuckPilot-Android-arm64-v0.4.1.apk`。主板解压同版本 `mircoduck-lew-udp-cli-0.4.1.zip`，进入解压目录后：

```bash
sudo bash scripts/install-udp.sh
duckctl service status mircoduck-udp
```

安装器只更新接入层、CLI 和文档，保留 robotd、标定和当前网络。旧 0.4.0 网关没有发现应答，0.4.1 App 对它仍可手动连接；要实现免输 IP 的 AP 连接，必须安装本次网关更新。此前个人系统镜像没有重新打包，恢复它后也需要安装本次更新。

## 连接行为

- App 启动、Wi-Fi 变化和回到前台时检测；前台断线时约每 3 秒重试识别。发现窗口约 800 ms，UDP 丢包时会短暂重试。
- 自动连接只获取状态与相机，不获取电机输入租期，不自动 HOME、站立、开启策略或恢复上一次方向。
- 切换 Wi-Fi 会清除原输入并断开旧会话；旧网络迟到的发现应答不用于连接新网络。
- 如果主板已有另一台手机会话，显示等待可用，不抢占该会话。
- 主动点击“断开”会暂停当前网络上的自动连接，避免立刻连回来；切换/重新接入热点或重开 App 后恢复。手动地址入口仍在连接设置中。
- App 后台不发起新的自动连接，清除并释放连续输入、关闭视频；返回前台重新检测。已有站立/保持行为仍由 robotd 决定。

## Android 网络选择

无互联网热点可能不会成为 Android 的默认网络。原生桥接使用 ConnectivityManager 观察 Wi-Fi，并把本 App 的新 UDP/WebRTC 连接绑定到该 Wi-Fi，避免手机同时开蜂窝数据时走错出口。它不修改手机其他 App 的网络，也不读取 SSID、不扫描附近热点、不申请定位权限。使用 INTERNET、ACCESS_NETWORK_STATE、CHANGE_NETWORK_STATE 权限。

手机提示热点“无法访问互联网”时，选择继续保持连接。这里要求手机已经成功加入热点；App 不替用户打开 Wi-Fi 或输入热点的 Wi-Fi 密码。

实现依据：[Android 网络状态与回调](https://developer.android.com/develop/connectivity/network-ops/reading-network-state)、[ConnectivityManager API](https://developer.android.google.cn/reference/android/net/ConnectivityManager)。

## 发现报文

协议保持无密钥 UDP v2，发现不创建/续租控制会话：

```json
{"v":2,"op":"discover","nonce":"0123456789abcdef0123456789abcdef"}
```

```json
{"v":2,"op":"discover","service":"mircoduck-lew","nonce":"0123456789abcdef0123456789abcdef","control_port":20043,"camera_port":8443,"busy":false}
```

客户端只接受来自所探测网关和端口、nonce 一致、服务名和端口范围正确的应答。nonce 用于匹配本次探测，不是身份认证或配对密钥。实际控制仍使用原有 hello、会话序号、短期 ticket 和失联输入清理机制。网关可通过 `--camera-port` 指定发现应答中的相机端口。

## 排错和验证范围

未自动连接时，检查手机是否仍保持在鸭子热点、网关是否为主板地址、主板是否已安装 0.4.1 接入层及 UDP 20043 是否可达。连接设置会显示识别/等待/重试信息；也可先用手动地址检查。

本次 34 项 Linux Python 测试、18 项 Flutter 测试、静态检查和 Android ARM64 构建通过。新增测试覆盖真实本地 UDP 发现、普通网关无应答、错误服务名/nonce/端口、已有会话、切换网络的迟到应答、主动断开和后台取消。Android 原生 Wi-Fi 路由桥接已编译，但没有手机/AP 实机联测；主板当时正在充电，本次发现协议尚未部署到实体主板。此前 0.4.0 的无密钥遥测实测不能替代本次自动连接验收。
