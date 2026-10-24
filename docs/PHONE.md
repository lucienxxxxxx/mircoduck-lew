# Android 手机控制（0.2 历史记录）

当前 0.3 版本已改为鸭控 DuckPilot 全屏相机界面，使用说明见 [DUCKPILOT.md](DUCKPILOT.md)。以下保留 0.2 的双摇杆操作记录。

App 0.2.0 从此前为本用户开发的 Flutter 横屏机器人控制台延续，已替换原先的 27 关节 ROS/rosbridge 接入，匹配当前 15 关节 Microduck。App 包名 `com.lucien.microduck_lew`。当前 APK 是个人测试签名，尚未在真实 Android 手机安装验收；后续正式分发应配置自己的发布签名并保持签名连续。

## 主板安装

需要已经安装本项目适配的 R17 robotd / IPC API40，以及 Python 3 标准库。将源码复制到主板后运行：

```bash
sudo bash scripts/install-udp.sh
sudo systemctl status mircoduck-udp --no-pager
sudo cat /etc/mircoduck-lew/udp.key
```

安装器保留已存在的密钥；首次生成 32 字节随机密钥（64 位十六进制），权限 0600。更新会重启接入层并释放手机输入，需要重新连接。它不会发送 HOME 或使能扭矩，也不会更换 robotd。密钥只交给自己的手机，勿放入 Git、截图或公共固件。

手机与主板接入同一局域网，设置中填写主板自己的 IP、端口 `20043` 和配对密钥。默认示例地址需自行修改。App 仅在内存中保留密钥，退出后需重新填写。HMAC 认证不加密遥测，适用于可信局域网；不提供互联网远程转发。

## 操作顺序

1. 认证连接，检查 15 关节及 IMU 的实时数据；此时不接管，也不使能电机。
2. 点击“接管控制”。实体手柄存在或另一个更新后的控制台占用时会拒绝；先释放其控制权。
3. 需要运动时明确选择“切换模式”到 motion；服务切换期间会释放控制，等实际状态更新后重新接管。
4. 摆放稳妥后点击 HOME 并确认。START 在未 HOME 时也会请求初始化；HOME 后 START 切换策略启用状态。这些操作可能使机器人移动，不能当作只读测试。
5. 用低幅度开始操作。默认摇杆幅度 25%；它还经过控制台原有 0.1 死区，低幅度时杆行程的中心区域会更大。

| 控件 | 与现有控制台一致的含义 |
| --- | --- |
| 左杆 / 右杆，drive 模式 | 前后、横移 / 转向；满幅上限 0.3 m/s、0.3 m/s、1.5 rad/s，再乘手机幅度 |
| Y / B | 头部 / 身体姿态模式切换 |
| A、X、LB、RB、方向下 | 使用 robotd `pad.bindings` 返回的实际技能绑定；X 保留原有按住连续请求语义 |
| 扩展手柄 LT / RT | 嘴巴与原有音效映射 |
| 停止 | 清除连续输入并释放手机控制；保持原有策略站立/保持行为，不等同于卸力 |
| 扩展手柄“卸力” | 经确认请求 robot.relax；需先放好或支撑机器人 |

离开前台、断连、反馈过期都会清除手机输入，不自动重新接管。UDP 输入超过 300 ms 没有更新会释放；仅心跳不能续期。接入层释放会发送零速度，robotd 原有 deadman 继续生效。软件停止行为未经过实际行走验收。

## 遥测含义

关节 ID 与顺序沿用 robotd 的实际 15 关节。每个关节单独标记新鲜度；一个分片到达不会替另一个分片的旧关节续期。commissioning 通常只提供编码器原始位置，不能伪装成已换算的角度。电流保持 `raw`，没有做 mA 标定；没有电池百分比估算。

IMU 重力和角速度按 robotd 当前接口原样呈现，角速度单位 rad/s。commissioning 的重力来自传感器报告，motion 来自正式状态流；两者的坐标处理遵循 robotd，不额外进行手机端校准。界面 roll/pitch 是重力换算，不能替代机械摆正或 IMU 安装校准。

## 构建与检查

本次验证环境为 Flutter/Dart SDK、JDK17 和 Android SDK；确切版本记录见 VALIDATION.md。使用 `pubspec.lock` 和带 SHA256 的 Gradle wrapper。

```bash
cd app
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
```

真实主板只读测试为显式选择的测试，默认跳过，使用自己的密钥文件，不将真实地址或密钥写入源码：

```bash
MICRODUCK_TEST_HOST=<board-ip> MICRODUCK_TEST_KEY_FILE=<private-key-file> flutter test test/live_board_test.dart
```

源码 App 独立部分为 Apache-2.0；Flutter、Dart、Gradle 等依赖保留各自许可。UDP 服务复用的 `console/remote_input.py` 仍受原控制台个人非商业许可约束。
