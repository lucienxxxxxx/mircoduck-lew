# duckctl 0.4：主板统一终端命令

`duckctl` 在 Radxa 主板本地运行，使用现有 `/run/robotd.sock`，不直接访问舵机串口。它统一提供真实状态查询、运动服务准备、站立、卸力、动作、日志、相机服务管理及 STA/AP 切换。Python 3 标准库即可运行；网络命令另需 NetworkManager、nmcli、systemd 及无线驱动的相应能力。

## 安装和帮助

在已安装兼容 R17 飞特运行环境的主板上，解压 0.4 接入层 ZIP 或进入源码目录：

```bash
sudo bash scripts/install-udp.sh
duckctl --version
duckctl --help
duckctl wifi --help
duckctl wifi sta --help
duckctl docs                   # 在主板终端阅读这份完整文档
```

安装位置 `/opt/mircoduck-lew/cli/duckctl.py`，命令链接 `/usr/local/bin/duckctl`。安装器拒绝覆盖其他同名程序。更新接入层会重启 UDP 服务，需要 App 重新连接；安装不会 HOME、卸力、更换 robotd、修改标定或切换网络。旧 `udp.key` 如存在会被忽略，0.4 不读取它。

手机使用 DuckPilot 0.4（UDP v2），填写当前主板地址、控制端口 **20043**、相机端口 **8443** 即可。没有 App 配对密钥。Wi-Fi 密码仍用于加入路由器或保护主板热点，两者含义不同。能访问 UDP 控制端口的设备可以发起会话，适合自己的局域网或主板热点。

## 日常查询

```bash
duckctl status                 # robot.busStatus 完整 JSON，含实际版本、模式、扭矩和反馈
duckctl imu                    # IMU 协议、采样新鲜度与原始诊断
duckctl joints                 # 逐关节反馈
duckctl policies               # 实际已加载策略和坐姿状态
duckctl service status robotd
duckctl service status mircoduck-udp
duckctl service status mediad
duckctl logs robotd -n 100
sudo duckctl logs mediad -n 100 -f
```

查询命令不发动作。状态按 robotd 原字段输出，不伪造未提供的反馈。权限不足时使用 sudo。日志输出可能含主机名和私人环境信息，不宜整段贴进公开仓库。

## 上电、站立、停止和卸力

先把机器人放到适合站立的平面，确认实体手柄已断开、手机和控制台已经停止输入：

```bash
sudo duckctl power on          # 准备 motion 服务；不等于站立
duckctl status                # 观察实际模式与新鲜反馈
sudo duckctl stand            # robot.init：使能关节并移到 HOME；坐姿时用 sit_toggle
sudo duckctl policy on        # 开启策略，由 robotd 执行姿态/传感器等检查
sudo duckctl skill sit_toggle # 坐下/站立切换
sudo duckctl stop             # 发送一次零方向、结束长叫、合嘴
sudo duckctl policy off        # 关闭策略；需要明确禁止继续策略时使用
sudo duckctl relax            # 卸力：robot.relax，释放舵机扭矩
```

**下电在本项目里就是卸力**。App 按钮已改名“卸力”，需确认后调用 `robot.relax`。主板、SSH、motion 服务和摄像头继续运行，舵机不再支撑重量，因此先扶稳或放平。`stop` 是一次清零，保持策略/扭矩；若另一个控制端继续发送方向，后续输入仍会覆盖它。先停止那个输入源，或在需要释放扭矩时用 `relax`。本 CLI 不提供关机、重启主板或直接写舵机寄存器的别名。

站立、技能、策略及短叫使用与 App/控制台相同的内核输入锁，已有控制端占用或实体手柄连接时拒绝。卸力和一次清零允许紧急调用，不等待输入锁。App、终端及服务回执的 accepted 仅代表请求接受，动作完成与否仍看实际反馈。

```bash
sudo duckctl skill roulade     # 前滚
sudo duckctl skill ground_pick
sudo duckctl skill kick_left
sudo duckctl skill kick_right
sudo duckctl sound short      # chirp 短叫
```

仅提供这些固定技能名及 walk、sit_toggle；未加载模型或姿态不满足时 robotd 会拒绝。长叫采用 App 按住/释放机制，CLI 暂不提供永久按住长叫的命令。

## 相机与接入层

```bash
sudo duckctl service start mediad
sudo duckctl service restart mediad
sudo duckctl service stop mediad
sudo duckctl service restart mircoduck-udp
```

如需开机开启相机服务：`sudo systemctl enable mediad`。mediad 沿用已安装的参数与摄像头配置，有客户端时才进行实际视频采集。服务命令不修改配置。NetworkManager 和 robotd 只允许查询状态，不把任意重启/停止作为控制动作。

## 手机自动连接

App 与主板接入层都更新至 0.4.1 后，手机连上鸭子热点即可自动识别网关并连接，不必手填 IP。见 [AP 自动连接说明](AP-AUTO-CONNECT.md)。STA/AP 模式切换仍由本 CLI 明确请求。

## STA 与 AP 是什么

| 模式 | 使用方式 | 手机填写的主板地址 |
| --- | --- | --- |
| STA | 主板作为客户端连接家中路由器或手机热点；手机也连同一个网络 | 路由器 DHCP 分配的地址，`duckctl wifi status` 查看 |
| AP | 主板自己开热点，手机连接它；不要求路由器 | 默认 `10.42.0.1` |

这是一张无线网卡切换两种模式，不是同时运行 STA+AP。AP 默认 2.4 GHz、WPA-PSK、IPv4 shared（提供手机地址）；没有其他互联网出口时，手机显示“无互联网”属正常。控制和视频仍可本地使用。

```bash
duckctl wifi status
duckctl wifi scan
duckctl wifi profiles          # 查看连接名称、UUID、类型和自动连接；不显示密码
```

无线网卡不唯一时，在 sta/ap 后加 `--interface wlan0`，按实际网卡名填写。若缺少 nmcli、网卡 unmanaged/unavailable 或不支持 AP，命令会停止，不接管 netplan、不启停其他网络管理器。

## 切到 AP：主板自己开热点

如已有可用热点配置，可以直接复用，不再输入密码，原热点名称和地址也保持原配置：

```bash
duckctl wifi profiles
sudo duckctl wifi ap --profile <现有AP配置的UUID>
```

或新建热点（默认地址 10.42.0.1）：

```bash
sudo duckctl wifi ap --ssid DuckPilot
# 按隐藏提示输入自己设置的 Wi-Fi 密码
```

输出包含切换编号 `token`、预计地址和确认命令。约 3 秒后后台工作进程切换；当前 SSH 和 App 可能断开。手机/电脑连接新热点，用刚设置的 Wi-Fi 密码，然后：

```bash
ssh radxa@10.42.0.1
sudo duckctl wifi confirm <输出的token>
duckctl wifi status
```

在手机 App 填写 `10.42.0.1`、20043、8443 并连接。这里的 Wi-Fi 密码由你创建，CLI 不附带固定热点密码，也没有 UDP 配对密钥。

## 切回 STA：连接路由器

推荐复用已经保存的 STA 配置，无需再输入 Wi-Fi 密码：

```bash
duckctl wifi profiles
sudo duckctl wifi sta --profile <路由器连接的UUID>
```

或者创建一个新路由器连接：

```bash
sudo duckctl wifi sta --ssid '你的路由器名称'
# 隐藏输入 Wi-Fi 密码
```

切换后电脑/手机也回到同一路由器，用路由器客户端列表找到新地址，重新 SSH，执行输出的 `wifi confirm <token>`。STA 地址可能变化，App 连接设置随之修改。仅支持常见 WPA-PSK 网络，企业 802.1X 或无密码网络请先在 NetworkManager 配好，再使用合适的现有 STA profile。

## 自动回滚与开机保持

切换前会记住当前 Wi-Fi UUID，不删除原配置。新建配置最初 `autoconnect=false`；独立 systemd 定时任务约在提交切换请求 **123 秒** 后回滚。激活目标若失败会立即回滚；SSH 断开不会取消回滚任务。

在截止前重新连上目标网络并执行 `wifi confirm <token>` 后，才把目标设为开机自动连接、优先级 999；本工具其他配置优先级降低，其他软件创建的连接保持原样。实际激活的 UUID 必须与目标一致才能确认。之后旧回滚定时器空操作；不需要手动删除定时器。

```bash
sudo duckctl wifi status
sudo duckctl wifi rollback <token> # 未确认前主动回到先前连接
```

若想恢复更早的已确认模式，再用 `wifi sta --profile ...` 或 `wifi ap --ssid ...` 发起一次新切换。确认前重启时，新配置不会自动连接，原有自动连接配置继续可用。原路由器关闭、密码失效、硬件故障或回滚命令本身失败时，不能保证旧网络能重新连接；本地终端查看状态中的 rollback-failed/error 与系统日志。原先没有连接时，回滚只关闭新连接，不凭空建立一个旧网络。

不要在行走或执行技能时切换网络；先停下输入。网络切换命令本身不执行卸力或站立。

## 密码处理和自动化

默认 getpass 隐藏输入，不把密码放进命令参数或 shell 历史。可通过 `--password-stdin` 从受保护文件/密码管理器提供一行密码（不要用带明文密码的 echo 命令）。密码写入 root:root、0600 的 NetworkManager 配置，不出现在 systemd 任务参数、token 文件或正常 CLI 输出。

SSID 限 1–32 UTF-8 字节；密码支持 8–63 ASCII 字符或 64 位十六进制 PSK。控制字符会被拒绝。新配置用独立 UUID，不覆盖原路由器配置。

命令成功退出码 0，校验、权限、网络或 robotd 错误退出码 1；参数格式错误由 argparse 返回 2。查询、动作结果和切换状态以 JSON 输出，wifi status/scan/profiles 和服务日志保持系统表格格式。内部 `_network` 子命令供 systemd 使用，不需要手动执行。

## 排错与验证边界

| 现象 | 检查 |
| --- | --- |
| App 连不上 | 使用 0.4 APK 和 0.4 网关；检查主板 IP、UDP 20043 和 mircoduck-udp 状态 |
| 旧 App 连不上 | v1/HMAC 报文不再接收，升级 App |
| 参数有值，操作按钮不可用 | 看 fresh、实体手柄、输入锁、HOME/策略条件；不跳过 robotd 原检查 |
| 相机黑屏 | `duckctl service status mediad`、`duckctl logs mediad`；确认 8443、摄像头和曝光 |
| AP 不成功 | 网卡 AP 能力、rfkill、驱动/固件、NetworkManager 日志 |
| nmcli 不存在/设备 unmanaged | 本工具不会自动迁移网络；在本地终端按系统现有网络方案配置 NM，再重试 |
| 切换后找不到主板 | 等待回滚；AP 地址默认 10.42.0.1；STA 从路由器列表找地址 |

配置格式与持久化参考 [NetworkManager keyfile 文档](https://www.networkmanager.dev/docs/api/1.44/nm-settings-keyfile.html)，命令用法参考 [nmcli 官方文档](https://networkmanager.pages.freedesktop.org/NetworkManager/NetworkManager/nmcli.html)。

32 项 Linux 测试覆盖 UDP 会话/失联、CLI 配置生成、卸力 RPC、回滚和确认条件；Flutter 10 项测试及 analyze 通过。主板实测情况另记在 VALIDATION.md。STA/AP 真正切换及 Android 手机安装需要实体操作验收；不得把单元测试当作无线切换或机器人动作已经实测。
