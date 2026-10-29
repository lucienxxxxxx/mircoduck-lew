# mircoduck-lew

面向 Radxa ZERO 3W、飞特 HD1910 与 IMU200 的个人维护版本，包含 Android 手机 App、UDP 接入层、硬件控制台和 `robotd` 源码。

由 [lucienxxxxxx](https://github.com/lucienxxxxxx) 维护，基于 [kissqy/Microduck-kissqy](https://github.com/kissqy/Microduck-kissqy) 和 [Pollen Robotics Microduck](https://github.com/pollen-robotics/microduck) 整理。保留上游署名、版权头及分项许可；本项目不是官方发布。

**当前版本：0.4.1；手机 App：鸭控 DuckPilot；robotd 构建：`1fa8438-feetech-control.43-ft01.1`，IPC API40；手机 UDP 协议 v2。**

## 这个版本做了什么

- 在保留 kissqy FT6 支持的基础上，增加 **IMU-to-Feetech v0.1**：身份 `00 01 00 49 46`，读取 `124/20`。
- 正确区分陀螺、四元数、加速度、采样计数和状态；角速度使用 `raw × 0.0175 °/s`。
- v0.1 使用舵机组读后单播读取 IMU，不依赖 IMU 和舵机的混合应答排序；共享 20 ms 总线周期预算。
- 检查 READY、数据有效位、stale、FIFO 和 I/O 故障；连续重复计数拒绝，正常计数回绕允许。
- 修复标定模式中旧启动占位状态遮挡实时总线状态的问题。
- 控制台同时识别原生 FT6 和 v0.1 适配服务；保留实时反馈、标定模式、扭矩 OFF 等操作条件。
- 安装默认保持 commissioning；不在启动时自动站立或行走。
- Android 横屏全屏相机，悬浮控制与左右渐变模糊蒙板；画面支持四向旋转。
- 左摇杆控制前后与左右转向，慢/中/快三档；右侧直接提供上电、卸力、站立、长叫、短叫与停止，底部动作面板可横向滚动。
- 读取真实的 15 关节、IMU、坐姿状态和已加载动作；过期或未提供的数据不补零。
- UDP 为无密钥局域网直连，保留会话序号和短期票据；300 ms 无输入释放，实体手柄优先，手机与更新后的控制台共享控制权锁。
- UDP 通过现有官方 IPC 请求 robotd；本次手机接入没有修改或重新替换 robotd 二进制。

## 目录

```text
console/                  当前 Python + 网页控制台
app/                      Flutter Android 手机客户端
gateway/                  主板 Python 标准库 UDP 适配服务
cli/                      duckctl 统一终端控制、STA/AP 切换
firmware/                 robotd 及其 Rust 依赖源码、数学测试夹具
config/                   未标定的通用配置示例
scripts/                  构建、资源准备、测试和发布整理工具
tests/                    控制台前后端兼容回归
docs/                     协议、构建、安装、校准和验证说明
LICENSES/                 上游原始许可及 Apache-2.0 全文
PROJECT.json              版本与来源记录
```

## 手机控制

**0.4.1：手机连上鸭子热点后，自动检测网关并连接，无需再填 IP。** [配置与实现说明](docs/AP-AUTO-CONNECT.md)。App 和主板接入层都需更新。


主板安装接入层：`sudo bash scripts/install-udp.sh`。手机与主板接入同一局域网，填写自己的主板地址、UDP 端口 `20043`，无需密钥。相机使用现有 mediad WebRTC 信令端口 `8443`。操作顺序为“连接 → 上电 → 站立”；控制权租期在内部处理。

主板统一命令及 STA/AP 切换见 [duckctl 文档](docs/CLI.md)。卸力释放舵机扭矩，主板继续运行。

安装、编译和操作说明见 [DuckPilot 使用说明](docs/DUCKPILOT.md)，报文及超时约定见 [UDP 协议](docs/UDP.md)。个人系统恢复镜像含实际标定和凭据，不属于公开源码发布内容。

## 启动控制台

需要 Python 3.11+ 和 OpenSSH。安装包中附带的 Python 运行环境不放进源码仓库。

```bash
python scripts/prepare-console.py
python console/console.py --dashboard --feetech --open
```

在页面中输入自己的 SSH 地址和凭据。模型网格首次按固定提交及 SHA256 下载；不下载时仍可查看其他界面。Windows 密码登录还需要构建或准备 `console/ssh-askpass.exe`，见 [构建说明](docs/BUILD.md)。

## 在 WSL 构建 robotd

```bash
sudo apt-get update
sudo apt-get install -y build-essential gcc-aarch64-linux-gnu python3 pkg-config
rustup target add aarch64-unknown-linux-gnu --toolchain 1.99.1
bash scripts/build-robotd.sh
```

生成 `dist/robotd`。完整步骤、glibc 要求及源代码测试见 [docs/BUILD.md](docs/BUILD.md)。

## 安装与校准

本仓库不发布任何一台机器的真实零位或 IMU 安装值。`config/hd1910-calibration.example.toml` 全部关节未标定，不能直接用于运动。只读 ID200 不能作为舵机写入、归中或扭矩控制的目标。

保留现有主板配置的升级流程见 [docs/INSTALL.md](docs/INSTALL.md)；先备份，再在扭矩关闭的 commissioning 模式验证 IMU 和所有舵机。当前未进行运动性能验收。

3D 中的悬空高度与 IMU 安装旋转不是同一个问题；安装旋转仅调整坐标轴。校准过程见 [docs/CALIBRATION.md](docs/CALIBRATION.md)。

## 验证范围

- 飞特协议及总线测试：**40 通过 / 0 失败**，含 v0.1 解析和伪串口测试。
- robotd 扩展测试：11 通过 / 9 失败，与未修改的 control.43 相同；不是全套测试全绿。
- 标定状态显示修复后的相关测试：5 通过 / 0 失败。
- WSL ARM64 release 构建、ELF 检查和 QEMU 启动检查通过。
- 2026-10-24 实机 commissioning 约 50 Hz，观察窗口内连续 1,994 轮成功、零通信失败，IMU ready/valid、15 个舵机反馈齐全。
- 手机当前：34 项 Python 检查、18 项 App 自动化检查通过，静态检查和 ARM64 APK 构建通过。0.4.1 热点自动连接尚未在 Android 手机/AP 实机验收，新发现协议待主板充电后安装；历史相机/遥测记录见 VALIDATION.md。

详情与限制见 [docs/VALIDATION.md](docs/VALIDATION.md)。私人硬件原始日志未公开。

## 许可

**这是分项许可的源码公开项目，不能将整个仓库统称为 Apache-2.0 或统一的 OSI 开源软件。**

- 原固件 Rust 工作区：Apache-2.0。
- kissqy 控制台原创部分：上游个人非商业许可，允许个人非商业修改与免费分享，保留其限制。
- Three.js、模型几何和其他第三方内容：遵守各自许可。
- 本项目独立新增的构建、测试和文档文件：Apache-2.0；不改变所依赖上游内容的许可。

见 [LICENSE](LICENSE)、[NOTICE.md](NOTICE.md) 和 [上游来源](docs/PROVENANCE.md)。
