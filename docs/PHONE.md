# 手机控制入口

当前版本为 DuckPilot 0.4，使用无密钥 UDP v2；旧 App 的 v1 认证报文不再兼容。

- [完整 App 操作、相机与构建说明](DUCKPILOT.md)
- [UDP v2 协议](UDP.md)
- [主板 duckctl 统一控制与 STA/AP 切换](CLI.md)

连接时仅填写主板地址、控制端口 20043 和相机端口 8443。无需配对密钥。卸力调用 robot.relax，主板继续运行。
