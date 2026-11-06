# Sing-Box Hysteria2 & Reality 快速配置脚本

一个用于在 Linux 服务器上安装、配置和管理 [Sing-Box](https://github.com/SagerNet/sing-box) 的 Shell 脚本，针对 Hysteria2 和 VLESS Reality 协议进行了优化。

## 特性

*   **一键安装 Sing-Box (beta 版)**：通过官方安装脚本部署最新 beta 版本（先下载到临时文件再执行，避免 pipe-to-bash）。
*   **多种安装模式**：
    *   同时安装 Hysteria2 和 Reality (VLESS) 服务，实现共存。
    *   单独安装 Hysteria2 服务。
    *   单独安装 Reality (VLESS) 服务。
*   **自动化配置**：
    *   Hysteria2: 自动生成自签名证书、随机密码。
    *   Reality (VLESS): 自动生成 UUID、Reality Keypair (私钥和公钥)。
    *   使用 `jq` 安全地构建 `config.json`，避免用户输入导致的 JSON 注入或格式错误。
    *   用户可自定义监听端口、伪装域名 (SNI) 等关键参数，且输入经过校验。
*   **Systemd 服务管理**：
    *   自动创建并配置 Sing-Box 的 systemd 服务。
    *   方便地启动、停止、重启、查看服务状态及日志。
    *   设置开机自启。
*   **导入信息与二维码**：
    *   安装完成后，自动显示详细的客户端导入参数。
    *   如果系统已安装 `qrencode`，则会直接在终端显示导入链接的二维码。
    *   支持随时查看上次成功安装的配置信息及二维码。
*   **依赖自动处理**：
    *   自动检测核心依赖 (`curl`, `openssl`, `jq`) 和可选依赖 (`qrencode`)。
    *   如果依赖缺失，会提示用户并尝试通过系统包管理器 (apt, yum, dnf) 自动安装。
*   **便捷管理**：
    *   提供菜单式交互界面，操作简单直观。
    *   支持查看和编辑 Sing-Box 配置文件 (使用 `nano`)。
    *   一键更新 Sing-box 内核。
    *   一键卸载 Sing-box 及相关配置。
*   **信息持久化**：上次成功安装的配置参数会被保存，方便后续通过菜单再次查看；持久化文件权限设置为 `600`。
*   **纯净脚本**：
    *   移除了多余的外部推广链接、Telegram 链接、网站链接。
    *   IP 检测优先使用本地网络接口，不再请求第三方 IP 探测服务，避免服务器 IP 泄露。

## 环境要求

*   Linux (x86_64 / amd64, aarch64 / arm64 架构理论上支持，未全面测试)
*   root 权限 (脚本内操作需要 sudo)
*   核心依赖: `curl`, `openssl`, `jq` (脚本会尝试自动安装)
*   可选依赖: `qrencode` (用于显示二维码，脚本会尝试自动安装)

## 使用方法

### 1. 下载并运行脚本

建议先下载到本地，检查内容后再执行：

```bash
wget -O lvhy.sh https://raw.githubusercontent.com/kiss8202/vlhy2/main/lvhy.sh
# 或
# curl -fsSL -o lvhy.sh https://raw.githubusercontent.com/kiss8202/vlhy2/main/lvhy.sh

chmod +x lvhy.sh
sudo bash lvhy.sh
```

### 2. 再次运行脚本

```bash
sudo bash lvhy.sh
```

脚本将以 root 权限运行，并显示主菜单。

### 3. 使用 sb 快捷命令（推荐）

首次通过菜单选项 `1`、`2` 或 `3` 完成安装后，脚本会自动：

1. 将自身复制到 `/usr/local/bin/lvhy.sh`
2. 创建 `/usr/local/bin/sb` 快捷命令

之后在任何目录下直接输入即可进入菜单：

```bash
sb
```

> 注意：如果首次运行是通过 `bash <(curl ...)` 等 pipe 方式执行，由于脚本不在本地文件，不会创建 sb 快捷命令。建议先下载脚本文件再执行安装。

### 4. 菜单选项说明

脚本启动后会显示主菜单，根据提示输入数字选择相应功能即可。

**初次使用建议：**

*   选择 `1`, `2`, 或 `3` 进行安装。脚本会引导你输入必要的参数（如端口、SNI 等），大部分参数有默认值可直接回车使用。
*   安装成功后，脚本会显示客户端导入所需的全部信息，包括文本参数和二维码（如果 `qrencode` 已安装）。请妥善保存这些信息。
*   之后你可以使用选项 `11` 再次查看这些信息。

### 注意事项

*   **配置文件**: Sing-Box 的主配置文件位于 `/usr/local/etc/sing-box/config.json`。Hysteria2 使用的自签名证书位于 `/etc/hysteria/`。
*   **持久化信息**: 上次成功安装的导入参数会保存在 `/usr/local/etc/sing-box/.last_singbox_script_info` 文件中，权限为 `600`，以便下次运行时通过菜单查看。卸载时如果选择删除配置目录，此文件也会被删除。
*   **SNI (伪装域名)**:
    *   对于 Reality，选择一个响应良好且不易被 GFW 干扰的 SNI（如 `www.microsoft.com`, `www.apple.com` 等）非常重要。脚本会让你自定义。
    *   对于 Hysteria2 的自签名证书，SNI 主要用于客户端验证，默认使用 `bing.com`，你也可以自定义。
*   **端口占用**: 请确保你为 Hysteria2 和 Reality 选择的监听端口未被其他程序占用。脚本默认 Hysteria2 使用 `8443`，Reality 使用 `443`。
*   **防火墙**: 如果你的服务器启用了防火墙 (如 ufw, firewalld)，请确保放行 Sing-Box 使用的端口。
    例如，如果使用 ufw 并且 Reality 使用 443 端口，Hysteria2 使用 8443 端口：
    ```bash
    sudo ufw allow 443/tcp
    sudo ufw allow 8443/tcp
    sudo ufw allow 8443/udp # Hysteria2 需要 UDP
    sudo ufw reload
    ```

## 贡献

欢迎提交 Pull Requests 或在 Issues 中报告错误、提出建议。

## 免责声明

*   本脚本仅为学习和测试目的提供。
*   请遵守当地法律法规，不要将此脚本用于非法用途。
*   作者不对使用此脚本可能造成的任何后果负责。

## 致谢

*   Sing-Box 项目及其开发者。
*   所有为开源社区做出贡献的人。
