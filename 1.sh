bash << 'MULTI_OS_EOF'
set -e

SCRIPT_PATH="/root/install.sh"
[ -f "$SCRIPT_PATH" ] || { echo "[ERROR] 脚本不存在: $SCRIPT_PATH"; exit 1; }
cp -a "$SCRIPT_PATH" "${SCRIPT_PATH}.bak.multios.$(date +%Y%m%d_%H%M%S)"
echo "[INFO] 已备份"

python3 << 'PY_EOF'
import re
import sys
path = "/root/install.sh"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

if 'detect_system()' in content and 'svc_restart()' in content:
    print("[WARN] 已存在兼容层，跳过"); sys.exit(0)

def rep(old, new, tag):
    global content
    if old not in content:
        print(f"[ERROR] 未找到: {tag}"); sys.exit(1)
    content = content.replace(old, new, 1)

# ===== 1. 插入兼容层（在 attempt_install_package 之前） =====
compat_block = '''# ==================== 系统兼容层（Debian / Alpine） ====================
OS_TYPE=""
INIT_SYSTEM=""
PKG_MGR=""

detect_system() {
    if [ -f /etc/alpine-release ]; then
        OS_TYPE="alpine"; INIT_SYSTEM="openrc"; PKG_MGR="apk"
    elif command -v systemctl &>/dev/null && [ -d /run/systemd/system ]; then
        OS_TYPE="systemd"; INIT_SYSTEM="systemd"
        if command -v apt-get &>/dev/null; then PKG_MGR="apt"
        elif command -v dnf &>/dev/null; then PKG_MGR="dnf"
        elif command -v yum &>/dev/null; then PKG_MGR="yum"
        fi
    else
        error "不支持的初始化系统（需 systemd 或 OpenRC）"
        exit 1
    fi

    if [ "$OS_TYPE" == "alpine" ]; then
        local need_install=()
        command -v bash   &>/dev/null || need_install+=("bash")
        command -v curl   &>/dev/null || need_install+=("curl")
        command -v jq     &>/dev/null || need_install+=("jq")
        command -v openssl &>/dev/null || need_install+=("openssl")
        command -v ip     &>/dev/null || need_install+=("iproute2")
        [ -f /etc/ssl/certs/ca-certificates.crt ] || need_install+=("ca-certificates")
        if [ ${#need_install[@]} -gt 0 ]; then
            info "Alpine 基础依赖安装: ${need_install[*]}"
            apk add --no-cache "${need_install[@]}" 2>/dev/null || \\
                apk add --no-cache bash curl jq openssl ca-certificates iproute2
        fi
    fi
    info "系统: $OS_TYPE | 包管理器: $PKG_MGR | 初始化: $INIT_SYSTEM"
}

svc_start()   { if [ "$INIT_SYSTEM" == "openrc" ]; then rc-service sing-box start;   else systemctl start sing-box;   fi; }
svc_stop()    { if [ "$INIT_SYSTEM" == "openrc" ]; then rc-service sing-box stop;    else systemctl stop sing-box;    fi; }
svc_restart() { if [ "$INIT_SYSTEM" == "openrc" ]; then rc-service sing-box restart; else systemctl restart sing-box; fi; }
svc_status()  { if [ "$INIT_SYSTEM" == "openrc" ]; then rc-service sing-box status;  else systemctl status sing-box --no-pager -l; fi; }
svc_is_active() {
    if [ "$INIT_SYSTEM" == "openrc" ]; then
        rc-service sing-box status &>/dev/null
    else
        systemctl is-active --quiet sing-box
    fi
}
svc_enable()  { if [ "$INIT_SYSTEM" == "openrc" ]; then rc-update add sing-box default &>/dev/null; else systemctl enable sing-box &>/dev/null; fi; }
svc_disable() { if [ "$INIT_SYSTEM" == "openrc" ]; then rc-update del sing-box default &>/dev/null; else systemctl disable sing-box &>/dev/null; fi; }
svc_daemon_reload() { if [ "$INIT_SYSTEM" == "openrc" ]; then true; else systemctl daemon-reload; fi; }
svc_log_tail() {
    local n="${1:-20}"
    if [ "$INIT_SYSTEM" == "openrc" ]; then
        logread 2>/dev/null | grep -i sing-box | tail -n "$n" || \\
            tail -n "$n" /var/log/messages 2>/dev/null || true
    else
        journalctl -u sing-box -n "$n" --no-pager
    fi
}
svc_log_follow() {
    local n="${1:-50}"
    if [ "$INIT_SYSTEM" == "openrc" ]; then
        logread -f 2>/dev/null || tail -f /var/log/messages
    else
        journalctl -u sing-box -f --no-pager -n "$n"
    fi
}

attempt_install_package() {'''

rep(
'attempt_install_package() {',
compat_block,
'插入兼容层')

# ===== 2. 整段替换 attempt_install_package =====
old_attempt = '''attempt_install_package() {
    local package_name="$1"
    local friendly_name="${2:-$package_name}"

    if command -v "$package_name" &>/dev/null; then
        return 0
    fi

    read -rp "依赖 '${friendly_name}' 未安装。是否尝试自动安装? (y/N): " install_confirm
    if [[ ! "$install_confirm" =~ ^[Yy]$ ]]; then
        warn "跳过安装 '${friendly_name}'。某些功能可能因此不可用或显示不完整。"
        return 1
    fi

    info "正在尝试安装 '${friendly_name}'..."
    if command -v apt-get &>/dev/null; then
        apt-get update -y >/dev/null 2>&1 || warn "apt-get update 失败，继续尝试安装 '${friendly_name}'..."
        apt-get install -y "$package_name" || return 1
    elif command -v yum &>/dev/null; then
        yum install -y "$package_name" || return 1
    elif command -v dnf &>/dev/null; then
        dnf install -y "$package_name" || return 1
    else
        error "未找到已知的包管理器 (apt, yum, dnf)。请手动安装 '${friendly_name}'。"
        return 1
    fi

    if command -v "$package_name" &>/dev/null; then
        success "'${friendly_name}' 安装成功。"
        return 0
    else
        error "'${friendly_name}' 安装失败。请检查错误信息并尝试手动安装。"
        return 1
    fi
}'''
new_attempt = '''attempt_install_package() {
    local package_name="$1"
    local friendly_name="${2:-$package_name}"

    if command -v "$package_name" &>/dev/null; then
        return 0
    fi

    # Alpine 包名映射
    local real_pkg="$package_name"
    if [ "$PKG_MGR" == "apk" ]; then
        case "$package_name" in
            qrencode) real_pkg="libqrencode-tools" ;;
            netstat)  real_pkg="net-tools" ;;
            ss)       real_pkg="iproute2" ;;
        esac
    fi

    read -rp "依赖 '${friendly_name}' 未安装。是否尝试自动安装? (y/N): " install_confirm
    if [[ ! "$install_confirm" =~ ^[Yy]$ ]]; then
        warn "跳过安装 '${friendly_name}'。某些功能可能因此不可用或显示不完整。"
        return 1
    fi

    info "正在尝试安装 '${friendly_name}'..."
    if [ "$PKG_MGR" == "apk" ]; then
        apk add --no-cache "$real_pkg" || return 1
    elif [ "$PKG_MGR" == "apt" ]; then
        apt-get update -y >/dev/null 2>&1 || warn "apt-get update 失败，继续尝试安装 '${friendly_name}'..."
        apt-get install -y "$real_pkg" || return 1
    elif [ "$PKG_MGR" == "dnf" ]; then
        dnf install -y "$real_pkg" || return 1
    elif [ "$PKG_MGR" == "yum" ]; then
        yum install -y "$real_pkg" || return 1
    else
        error "未识别的包管理器，请手动安装 '${friendly_name}'。"
        return 1
    fi

    if command -v "$package_name" &>/dev/null; then
        success "'${friendly_name}' 安装成功。"
        return 0
    else
        error "'${friendly_name}' 安装失败。请检查错误信息并尝试手动安装。"
        return 1
    fi
}'''
rep(old_attempt, new_attempt, 'attempt_install_package')

# ===== 3. 整段替换 create_systemd_service =====
old_css = '''create_systemd_service() {
    if [ -z "$SINGBOX_CMD" ]; then
        error "Sing-box command (SINGBOX_CMD) 未设置。无法创建 systemd 服务。"
        return 1
    fi
    info "创建/更新 systemd 服务: ${SINGBOX_SERVICE_FILE}"
    cat > "$SINGBOX_SERVICE_FILE" <<EOF
[Unit]
Description=Sing-Box Service
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=${SINGBOX_CONFIG_DIR}
ExecStart=${SINGBOX_CMD} run -c ${SINGBOX_CONFIG_FILE}
ExecReload=/bin/kill -HUP \\$MAINPID
Restart=on-failure
RestartSec=10
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable sing-box
    success "Systemd 服务已创建并设置为开机自启。"
}'''
new_css = '''create_systemd_service() {
    if [ -z "$SINGBOX_CMD" ]; then
        error "Sing-box command (SINGBOX_CMD) 未设置。无法创建服务。"
        return 1
    fi

    if [ "$INIT_SYSTEM" == "openrc" ]; then
        info "创建/更新 OpenRC 服务: /etc/init.d/sing-box"
        cat > /etc/init.d/sing-box <<EOF
#!/sbin/openrc-run
description="Sing-Box Service"
command="${SINGBOX_CMD}"
command_args="run -c ${SINGBOX_CONFIG_FILE}"
command_background=true
pidfile="/var/run/sing-box.pid"
respawn_delay=10
respawn_max=0

depend() {
    need net
    after firewall
}
EOF
        chmod +x /etc/init.d/sing-box
        svc_enable
        success "OpenRC 服务已创建并设置为开机自启。"
    else
        info "创建/更新 systemd 服务: ${SINGBOX_SERVICE_FILE}"
        cat > "$SINGBOX_SERVICE_FILE" <<EOF
[Unit]
Description=Sing-Box Service
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=${SINGBOX_CONFIG_DIR}
ExecStart=${SINGBOX_CMD} run -c ${SINGBOX_CONFIG_FILE}
ExecReload=/bin/kill -HUP \\$MAINPID
Restart=on-failure
RestartSec=10
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
        svc_daemon_reload
        svc_enable
        success "Systemd 服务已创建并设置为开机自启。"
    fi
}'''
rep(old_css, new_css, 'create_systemd_service')

# ===== 4. 整段替换 start_singbox_service =====
old_sss = '''start_singbox_service() {
    info "正在启动 Sing-box 服务..."
    systemctl restart sing-box
    sleep 2
    if systemctl is-active --quiet sing-box; then
        success "Sing-box 服务启动成功。"
    else
        error "Sing-box 服务启动失败。"
        journalctl -u sing-box -n 20 --no-pager
        warn "请使用 'systemctl status sing-box' 或 'journalctl -u sing-box -e' 查看详细日志。"
        return 1
    fi
}'''
new_sss = '''start_singbox_service() {
    info "正在启动 Sing-box 服务..."
    svc_restart
    sleep 2
    if svc_is_active; then
        success "Sing-box 服务启动成功。"
    else
        error "Sing-box 服务启动失败。"
        svc_log_tail 20
        warn "请用菜单 7/8 查看服务状态和日志排查。"
        return 1
    fi
}'''
rep(old_sss, new_sss, 'start_singbox_service')

# ===== 5. 替换 hostname -I 行 =====
rep(
"        host_ips=$(hostname -I 2>/dev/null || true)",
"        host_ips=$(hostname -I 2>/dev/null || ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | tr '\\n' ' ' || true)",
'hostname -I 兼容')

# ===== 6. 替换 sb 快捷命令生成（兼容无 sudo） =====
old_sb = '''    chmod 755 "$target_script"
    cat > "$shortcut" <<EOF
#!/bin/bash
exec sudo bash ${target_script} "\\$@"
EOF
    chmod 755 "$shortcut"'''
new_sb = '''    chmod 755 "$target_script"
    if command -v sudo &>/dev/null; then
        cat > "$shortcut" <<EOF
#!/bin/bash
exec sudo bash ${target_script} "\\$@"
EOF
    else
        warn "未检测到 sudo，sb 将直接以当前用户（需 root）运行脚本。"
        cat > "$shortcut" <<EOF
#!/bin/bash
exec bash ${target_script} "\\$@"
EOF
    fi
    chmod 755 "$shortcut"'''
rep(old_sb, new_sb, 'sb 快捷命令 sudo 兼容')

# ===== 7. 入口点加 detect_system =====
rep(
'''# --- Entry point ---
check_root
check_dependencies''',
'''# --- Entry point ---
check_root
detect_system
check_dependencies''',
'入口点 detect_system')

# ===== 8. 正则批量替换剩余 systemctl / journalctl =====
patterns = [
    (r'systemctl\s+start\s+sing-box\b',              'svc_start'),
    (r'systemctl\s+stop\s+sing-box\b',               'svc_stop'),
    (r'systemctl\s+restart\s+sing-box\b',            'svc_restart'),
    (r'systemctl\s+status\s+sing-box\s+--no-pager\s+-l', 'svc_status'),
    (r'systemctl\s+is-active\s+--quiet\s+sing-box',  'svc_is_active'),
    (r'systemctl\s+enable\s+sing-box\b',             'svc_enable'),
    (r'systemctl\s+disable\s+sing-box\b',            'svc_disable'),
    (r'systemctl\s+daemon-reload',                    'svc_daemon_reload'),
    (r'journalctl\s+-u\s+sing-box\s+-f\s+--no-pager\s+-n\s+50', 'svc_log_follow 50'),
    (r'journalctl\s+-u\s+sing-box\s+-n\s+20\s+--no-pager',       'svc_log_tail 20'),
    (r'journalctl\s+-u\s+sing-box\s+-e\b',                       'svc_log_tail 50'),
]
for pat, repl in patterns:
    content = re.sub(pat, repl, content)

with open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("[OK] 兼容层 + 全部替换完成")
PY_EOF

bash -n "$SCRIPT_PATH" || { echo "[ERROR] 语法检查失败"; exit 1; }
echo "[SUCCESS] 语法检查通过"

if [ -f /usr/local/bin/install.sh ]; then
    cp -f "$SCRIPT_PATH" /usr/local/bin/install.sh
    chmod 755 /usr/local/bin/install.sh
    echo "[INFO] 已同步到 /usr/local/bin/install.sh"
fi

echo ""
echo "[CHECK] 关键函数/变量:"
for k in "detect_system()" "svc_start()" "svc_restart()" "svc_log_tail()" "svc_log_follow()" "PKG_MGR"; do
    if grep -qF "$k" "$SCRIPT_PATH"; then echo "  ✓ $k"; else echo "  ✗ $k"; fi
done
echo ""
echo "[CHECK] 残留 systemctl/journalctl 数量（应为 0，除了函数定义里的）:"
echo -n "  systemctl: "; grep -c "systemctl" "$SCRIPT_PATH" || true
echo -n "  journalctl: "; grep -c "journalctl" "$SCRIPT_PATH" || true

echo ""
echo "[DONE] Debian 上运行验证: sb → 菜单7 服务状态、菜单8 实时日志、安装节点全流程"
echo "[DONE] Alpine 上首次运行: sudo bash /root/install.sh（自动装依赖）"
MULTI_OS_EOF
