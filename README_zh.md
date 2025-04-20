# OpenVPN SOCKS5 代理与自动修复系统

这个项目提供了一个 Docker 容器，可以自动管理 OpenVPN 连接并将其暴露为 SOCKS5 代理。它具有自动 VPN 服务器轮换、健康监控和自动恢复等功能。

## 主要特性

- **自动 VPN 配置管理**
  - 自动从 VPNGate 下载 VPN 配置
  - 定期更新配置（每10分钟）
  - 使用前验证配置有效性
  - 更新前自动备份现有配置

- **智能 VPN 连接管理**
  - 基于国家的 VPN 服务器选择
  - 连接失败时自动切换服务器
  - 健康状态监控和自动恢复
  - 通过 SOCKS5 代理验证连接

- **SOCKS5 代理接口**
  - 易用的 SOCKS5 代理接口
  - 可配置的身份验证
  - 本地网络绑定以确保安全

- **自动修复功能**
  - 自动健康检查
  - 检测并从连接失败中恢复
  - 智能服务器选择
  - 集成 Docker 的健康检查系统

## 快速开始

1. 克隆仓库：
   ```bash
   git clone https://github.com/yourusername/openvpn-socks5-healthcheck.git
   cd openvpn-socks5-healthcheck
   ```

2. 创建 config.env 文件：
   ```bash
   # 基本配置
   SOCKS5_USER=myuser
   SOCKS5_PASS=mypass
   
   # 可选：指定首选 VPN 国家（例如：JP, KR, US）
   VPN_COUNTRY=JP
   ```

3. 启动服务：
   ```bash
   docker compose up -d
   ```

## 配置说明

### 环境变量

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| SOCKS5_USER | SOCKS5 代理用户名 | user |
| SOCKS5_PASS | SOCKS5 代理密码 | pass |
| VPN_COUNTRY | 首选 VPN 服务器国家（如 JP, KR） | - |
| ACTIVE_CONFIG | 指定使用的 VPN 配置文件 | - |
| HEALTH_CHECK_INTERVAL | 健康检查间隔（秒） | 30 |

### Docker Compose 配置

```yaml
version: '3.8'

services:
  vpn-socks5:
    build: .
    container_name: ${NAME:-vpn-socks5}
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
    volumes:
      - ./vpn:/vpn
      - ./config.env:/config.env:ro
    env_file:
      - config.env
    environment:
      - ACTIVE_CONFIG=${ACTIVE_CONFIG:-}
      - VPN_COUNTRY=${VPN_COUNTRY:-JP}
      - SOCKS5_USER=${SOCKS5_USER:-user}
      - SOCKS5_PASS=${SOCKS5_PASS:-pass}
    ports:
      - "127.0.0.1:7777:7777"
    healthcheck:
      test: ["CMD", "curl", "-x", "socks5h://127.0.0.1:7777", "-U", "${SOCKS5_USER}:${SOCKS5_PASS}", "https://www.google.com", "-f", "-s", "-o", "/dev/null"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 15s
```

## 使用说明

### 基本使用

1. 启动服务：
   ```bash
   docker compose up -d
   ```

2. 使用 SOCKS5 代理：
   ```
   主机：127.0.0.1
   端口：7777
   用户名：[config 中的 SOCKS5_USER]
   密码：[config 中的 SOCKS5_PASS]
   ```

### 国家特定 VPN

要使用特定国家的 VPN 服务器：

1. 在 config.env 中设置 VPN_COUNTRY：
   ```bash
   VPN_COUNTRY=JP  # 使用日本服务器
   ```

2. 或在启动时指定：
   ```bash
   VPN_COUNTRY=KR docker compose up -d  # 使用韩国服务器
   ```

可用的国家代码：JP（日本）、KR（韩国）、US（美国）等。

### 自动健康监控

容器会自动执行以下操作：
- 每30秒进行一次健康检查
- 如果健康检查失败，自动切换到其他 VPN 服务器
- 通过自动修复功能维持连接稳定性
- 每10分钟更新 VPN 配置

### 日志和监控

查看容器日志：
```bash
docker compose logs -f
```

检查容器健康状态：
```bash
docker ps  # 查看 STATUS 列
```

## 安全注意事项

- SOCKS5 代理默认只绑定到 localhost (127.0.0.1)
- 代理访问需要身份验证
- VPN 配置在使用前会进行验证
- 容器使用最小所需权限运行

## 故障排除

1. 容器无法启动：
   - 检查 tun 设备是否可用
   - 验证 config.env 文件权限
   - 查看容器日志了解错误信息

2. 代理无法访问：
   - 验证端口映射是否正确
   - 检查 SOCKS5 认证信息
   - 确保容器处于健康状态

3. VPN 连接不稳定：
   - 尝试指定其他国家
   - 检查网络连接
   - 查看容器日志排查问题

### 常见问题解决

1. 配置文件更新：
   - 系统会自动每10分钟更新一次配置
   - 更新前会自动备份现有配置
   - 可以在日志中查看更新状态

2. 服务器切换：
   - 当前服务器不可用时会自动切换
   - 优先使用指定国家的服务器
   - 如果指定国家没有可用服务器，会使用其他国家的服务器

3. 性能优化：
   - 可以通过指定国家来选择地理位置较近的服务器
   - 健康检查间隔可以根据需要调整
   - 配置文件会自动验证以确保可用性

## 高级功能

1. 自动修复系统：
   - 集成了 Docker 的健康检查机制
   - 使用 willfarrell/autoheal 自动重启不健康的容器
   - 智能检测和恢复服务

2. 配置管理：
   - 支持手动指定特定配置文件
   - 自动管理配置文件的生命周期
   - 提供配置文件的备份和恢复

3. 网络安全：
   - 所有流量通过 VPN 隧道
   - 支持 SOCKS5 认证
   - 本地绑定增加安全性

## 贡献指南

欢迎提交 Pull Requests 来改进这个项目！

## 许可证

本项目采用 MIT 许可证 - 详见 LICENSE 文件 