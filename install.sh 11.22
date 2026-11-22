#!/bin/bash

# Hardened Sing-Box Hysteria2 & Reality Management Script
# 安全优先：本地化、输入校验、安全权限、无 pipe-to-bash

set -euo pipefail
IFS=$' \t\n'

# --- Configuration ---
SINGBOX_INSTALL_PATH_EXPECTED="/usr/local/bin/sing-box"
SINGBOX_CONFIG_DIR="/usr/local/etc/sing-box"
SINGBOX_CONFIG_FILE="${SINGBOX_CONFIG_DIR}/config.json"
SINGBOX_SERVICE_FILE="/etc/systemd/system/sing-box.service"

HYSTERIA_CERT_DIR="/etc/hysteria"
HYSTERIA_CERT_KEY="${HYSTERIA_CERT_DIR}/private.key"
HYSTERIA_CERT_PEM="${HYSTERIA_CERT_DIR}/cert.pem"

PERSISTENT_INFO_FILE="${SINGBOX_CONFIG_DIR}/.last_singbox_script_info"

# Defaults
DEFAULT_HYSTERIA_PORT="8443"
DEFAULT_REALITY_PORT="443"
DEFAULT_HYSTERIA_MASQUERADE_CN="www.washington.edu"
DEFAULT_REALITY_SNI="www.washington.edu"

SINGBOX_CMD=""

LAST_SERVER_IP=""
LAST_SERVER_IP4=""
LAST_SERVER_IP6=""
LAST_HY2_PORT=""
LAST_HY2_PASSWORD=""
LAST_HY2_MASQUERADE_CN=""
LAST_HY2_LINK=""
LAST_REALITY_PORT=""
LAST_REALITY_UUID=""
LAST_REALITY_PUBLIC_KEY=""
LAST_REALITY_SNI=""
LAST_REALITY_SHORT_ID=""
LAST_REALITY_FINGERPRINT="chrome"
LAST_VLESS_LINK=""
LAST_INSTALL_MODE=""
LINK_IP_MODE="4"
TEMP_REALITY_PRIVATE_KEY=""
LAST_HY2_OBFS_PASSWORD=""

# 多节点持久化（关联数组：key=端口号）
declare -A NODE_HY2_PASSWORD=()
declare -A NODE_HY2_OBFS=()
declare -A NODE_HY2_SNI=()
declare -A NODE_REALITY_UUID=()
declare -A NODE_REALITY_PUBLIC_KEY=()
declare -A NODE_REALITY_SNI=()
declare -A NODE_REALITY_SHORT_ID=()
declare -A NODE_REALITY_FP=()
LAST_HY2_OBFS_PASSWORD=""

# 入站/出站 IP 模式：v4 / v6 / both
INBOUND_MODE="${INBOUND_MODE:-both}"
OUTBOUND_MODE="${OUTBOUND_MODE:-both}"

# 中转管理（按端口绑定）
declare -A RELAY_JSON=()
declare -A RELAY_DESC=()
declare -A NODE_HY2_RELAY=()
declare -A NODE_REALITY_RELAY=()
RELAY_FILE="${SINGBOX_CONFIG_DIR}/relays.conf"
declare -a DOMAIN_ROUTES=()

# VLESS + TLS 节点
declare -A NODE_VLESS_TLS_UUID=()
declare -A NODE_VLESS_TLS_TYPE=()
declare -A NODE_VLESS_TLS_SNI=()
declare -A NODE_VLESS_TLS_PATH=()
declare -A NODE_VLESS_TLS_SVC=()
declare -A NODE_VLESS_TLS_RELAY=()
declare -A NODE_VLESS_TLS_CDN=()
VLESS_TLS_CERT_DIR="/etc/sing-box/vless-tls"
VLESS_TLS_CERT_PEM="${VLESS_TLS_CERT_DIR}/cert.pem"
VLESS_TLS_CERT_KEY="${VLESS_TLS_CERT_DIR}/private.key"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

print_header() {
    echo -e "${MAGENTA}${BOLD}================================================${NC}"
    echo -e "${CYAN}${BOLD} Sing-Box Hysteria2 & Reality 管理脚本 ${NC}"
    echo -e "${MAGENTA}${BOLD}================================================${NC}"
}

# --- Validation helpers ---
is_public_ipv4() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
    local a="${BASH_REMATCH[1]}" b="${BASH_REMATCH[2]}" c="${BASH_REMATCH[3]}" d="${BASH_REMATCH[4]}"
    (( a <= 255 && b <= 255 && c <= 255 && d <= 255 )) || return 1
    # 排除私有/保留/特殊用途地址段
    (( a == 0 )) && return 1                              # 0.0.0.0/8
    (( a == 10 )) && return 1                              # 10.0.0.0/8 私网
    (( a == 100 && b >= 64 && b <= 127 )) && return 1      # 100.64.0.0/10 CGNAT
    (( a == 127 )) && return 1                              # 127.0.0.0/8 回环
    (( a == 169 && b == 254 )) && return 1                  # 169.254.0.0/16 链路本地
    (( a == 172 && b >= 16 && b <= 31 )) && return 1        # 172.16.0.0/12 私网
    (( a == 192 && b == 0 && c == 0 )) && return 1           # 192.0.0.0/24 IETF 保留
    (( a == 192 && b == 0 && c == 2 )) && return 1           # 192.0.2.0/24 TEST-NET-1
    (( a == 192 && b == 168 )) && return 1                   # 192.168.0.0/16 私网
    (( a == 198 && ( b == 18 || b == 19 ) )) && return 1     # 198.18.0.0/15 基准测试
    (( a == 198 && b == 51 && c == 100 )) && return 1        # 198.51.100.0/24 TEST-NET-2
    (( a == 203 && b == 0 && c == 113 )) && return 1         # 203.0.113.0/24 TEST-NET-3
    (( a >= 224 )) && return 1                               # 224.0.0.0/3 组播/保留/广播
    return 0
}

is_public_ipv6() {
    local ip="$1"
    [[ "$ip" == *:* ]] || return 1
    [[ "$ip" == "::" ]] && return 1
    [[ "$ip" == ::1 ]] && return 1
    [[ "$ip" == ::ffff:* ]] && return 1
    [[ "$ip" == fe80::* ]] && return 1
    [[ "$ip" == fc* || "$ip" == fd* ]] && return 1
    [[ "$ip" == ff* ]] && return 1
    [[ "$ip" == 2001:db8::* ]] && return 1
    [[ "$ip" == 2002:* ]] && return 1
    [[ "$ip" == 64:ff9b::* ]] && return 1
    [[ "$ip" == 100::* ]] && return 1
    return 0
}

is_ipv6() { [[ "$1" == *:* ]]; }

is_valid_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] || return 1
    (( port >= 1 && port <= 65535 ))
}

is_valid_domain() {
    local domain="$1"
    [[ -n "$domain" ]] || return 1
    [[ "$domain" == *.* ]] || return 1
    [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]
}

format_host_for_uri() {
    local host="$1"
    if is_ipv6 "$host"; then echo "[$host]"; else echo "$host"; fi
}

is_port_in_use() {
    local port="$1"
    local proto="${2:-both}"
    local ss_flag="-tuln"
    case "$proto" in
        udp) ss_flag="-uln" ;;
        tcp) ss_flag="-tln" ;;
    esac
    local lines=""
    if command -v ss &>/dev/null && ss -H -tln 2>/dev/null >/dev/null; then
        lines=$(ss -H $ss_flag -p 2>/dev/null \
                | grep -E ":${port}[[:space:]]" \
                | grep -vE 'users:\(\("sing-box"' || true)
        [[ -n "$lines" ]]
        return
    fi
    if command -v netstat &>/dev/null; then
        lines=$(netstat -tulnp 2>/dev/null \
                | grep -E ":${port}[[:space:]]" \
                | grep -v 'sing-box' || true)
        [[ -n "$lines" ]]
        return
    fi
    return 1
}

prompt_port() {
    local prompt_msg="$1" default_val="$2" var_name="$3"
    local proto="${4:-both}"
    local input
    while true; do
        read -rp "${prompt_msg} (默认: ${default_val}): " input
        input="${input:-$default_val}"
        if ! is_valid_port "$input"; then
            warn "端口号必须是 1-65535 之间的整数。"
            continue
        fi
        if is_port_in_use "$input" "$proto"; then
            warn "端口 ${input} 已被其他进程占用，请更换端口。"
            continue
        fi
        printf -v "$var_name" '%s' "$input"
        break
    done
}

prompt_domain() {
    local prompt_msg="$1" default_val="$2" var_name="$3"
    local input
    while true; do
        read -rp "${prompt_msg} (默认: ${default_val}): " input
        input="${input:-$default_val}"
        if is_valid_domain "$input"; then
            printf -v "$var_name" '%s' "$input"
            break
        else
            warn "请输入有效的域名。"
        fi
    done
}

install_script_shortcut() {
    local script_dir script_name source_script
    script_dir=$(cd "$(dirname "$0")" && pwd)
    script_name=$(basename "$0")
    source_script="${script_dir}/${script_name}"

    local target_script="/usr/local/bin/install.sh"
    local shortcut="/usr/local/bin/sb"

    if [[ "$script_name" == "bash" || "$source_script" == "/dev/fd/"* || ! -f "$source_script" ]]; then
        warn "检测到脚本通过 pipe 或临时方式运行，无法创建 sb 快捷命令。"
        info "如需使用 sb 快捷命令，请先下载脚本文件到本地再执行安装。"
        return 1
    fi

    info "正在安装脚本快捷命令 sb ..."
    if [[ "$source_script" != "$target_script" ]]; then
        cp -f "$source_script" "$target_script"
    fi
    chmod 755 "$target_script"
    if command -v sudo &>/dev/null; then
        cat > "$shortcut" <<EOF
#!/bin/bash
exec sudo bash ${target_script} "\$@"
EOF
    else
        warn "未检测到 sudo，sb 将直接以 root 用户运行"
        cat > "$shortcut" <<EOF
#!/bin/bash
exec bash ${target_script} "\$@"
EOF
    fi
    chmod 755 "$shortcut"
    success "快捷命令 sb 安装完成。之后可直接输入 sb 进入菜单。"
}

# --- Persistent info (safe loader) ---
load_persistent_info() {
    if [ ! -f "$PERSISTENT_INFO_FILE" ]; then
        info "未找到持久化的配置信息文件。"
        return
    fi

    local key value
    while IFS='=' read -r key value; do
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
        value="${value%\"}"; value="${value#\"}"
        value="${value%\'}"; value="${value#\'}"
        case "$key" in
            LAST_SERVER_IP) LAST_SERVER_IP="$value" ;;
            LAST_SERVER_IP4) LAST_SERVER_IP4="$value" ;;
            LAST_SERVER_IP6) LAST_SERVER_IP6="$value" ;;
            LAST_HY2_PORT) LAST_HY2_PORT="$value" ;;
            LAST_HY2_PASSWORD) LAST_HY2_PASSWORD="$value" ;;
            LAST_HY2_OBFS_PASSWORD) LAST_HY2_OBFS_PASSWORD="$value" ;;
            LAST_HY2_MASQUERADE_CN) LAST_HY2_MASQUERADE_CN="$value" ;;
            LAST_HY2_LINK) LAST_HY2_LINK="$value" ;;
            LAST_REALITY_PORT) LAST_REALITY_PORT="$value" ;;
            LAST_REALITY_UUID) LAST_REALITY_UUID="$value" ;;
            LAST_REALITY_PUBLIC_KEY) LAST_REALITY_PUBLIC_KEY="$value" ;;
            LAST_REALITY_SNI) LAST_REALITY_SNI="$value" ;;
            LAST_REALITY_SHORT_ID) LAST_REALITY_SHORT_ID="$value" ;;
            LAST_REALITY_FINGERPRINT) LAST_REALITY_FINGERPRINT="$value" ;;
            LAST_VLESS_LINK) LAST_VLESS_LINK="$value" ;;
            LAST_INSTALL_MODE) LAST_INSTALL_MODE="$value" ;;
            LINK_IP_MODE) LINK_IP_MODE="$value" ;;
            INBOUND_MODE) INBOUND_MODE="$value" ;;
            OUTBOUND_MODE) OUTBOUND_MODE="$value" ;;
            NODE_HY2_*)
                local rest="${key#NODE_HY2_}"
                local port="${rest%%_*}"
                local field="${rest#*_}"
                case "$field" in
                    PASSWORD) NODE_HY2_PASSWORD["$port"]="$value" ;;
                    OBFS) NODE_HY2_OBFS["$port"]="$value" ;;
                    SNI) NODE_HY2_SNI["$port"]="$value" ;;
                esac
                ;;
            NODE_REALITY_*)
                local rest2="${key#NODE_REALITY_}"
                local port2="${rest2%%_*}"
                local field2="${rest2#*_}"
                case "$field2" in
                    UUID) NODE_REALITY_UUID["$port2"]="$value" ;;
                    PUBLIC_KEY) NODE_REALITY_PUBLIC_KEY["$port2"]="$value" ;;
                    SNI) NODE_REALITY_SNI["$port2"]="$value" ;;
                    SHORT_ID) NODE_REALITY_SHORT_ID["$port2"]="$value" ;;
                    FP) NODE_REALITY_FP["$port2"]="$value" ;;
                esac
                ;;
            NODE_VLESS_TLS_*)
                local rest3="${key#NODE_VLESS_TLS_}"
                local port3="${rest3%%_*}"
                local field3="${rest3#*_}"
                case "$field3" in
                    UUID) NODE_VLESS_TLS_UUID["$port3"]="$value" ;;
                    TYPE) NODE_VLESS_TLS_TYPE["$port3"]="$value" ;;
                    SNI) NODE_VLESS_TLS_SNI["$port3"]="$value" ;;
                    PATH) NODE_VLESS_TLS_PATH["$port3"]="$value" ;;
                    SVC) NODE_VLESS_TLS_SVC["$port3"]="$value" ;;
                    CDN) NODE_VLESS_TLS_CDN["$port3"]="$value" ;;
                esac
                ;;
        esac
    done < "$PERSISTENT_INFO_FILE"

    success "配置信息加载完成。"
}

save_persistent_info() {
    info "正在保存当前配置信息到: $PERSISTENT_INFO_FILE"
    mkdir -p "$(dirname "$PERSISTENT_INFO_FILE")"
    {
        echo "LAST_SERVER_IP=\"${LAST_SERVER_IP}\""
        echo "LAST_SERVER_IP4=\"${LAST_SERVER_IP4}\""
        echo "LAST_SERVER_IP6=\"${LAST_SERVER_IP6}\""
        echo "LAST_HY2_PORT=\"${LAST_HY2_PORT}\""
        echo "LAST_HY2_PASSWORD=\"${LAST_HY2_PASSWORD}\""
        echo "LAST_HY2_OBFS_PASSWORD=\"${LAST_HY2_OBFS_PASSWORD}\""
        echo "LAST_HY2_MASQUERADE_CN=\"${LAST_HY2_MASQUERADE_CN}\""
        echo "LAST_HY2_LINK=\"${LAST_HY2_LINK}\""
        echo "LAST_REALITY_PORT=\"${LAST_REALITY_PORT}\""
        echo "LAST_REALITY_UUID=\"${LAST_REALITY_UUID}\""
        echo "LAST_REALITY_PUBLIC_KEY=\"${LAST_REALITY_PUBLIC_KEY}\""
        echo "LAST_REALITY_SNI=\"${LAST_REALITY_SNI}\""
        echo "LAST_REALITY_SHORT_ID=\"${LAST_REALITY_SHORT_ID}\""
        echo "LAST_REALITY_FINGERPRINT=\"${LAST_REALITY_FINGERPRINT}\""
        echo "LAST_VLESS_LINK=\"${LAST_VLESS_LINK}\""
        echo "LAST_INSTALL_MODE=\"${LAST_INSTALL_MODE}\""
        echo "LINK_IP_MODE=\"${LINK_IP_MODE}\""
        echo "INBOUND_MODE=\"${INBOUND_MODE}\""
        echo "OUTBOUND_MODE=\"${OUTBOUND_MODE}\""
    } > "$PERSISTENT_INFO_FILE"

    # 追加多节点
    local p
    for p in "${!NODE_HY2_PASSWORD[@]}"; do
        echo "NODE_HY2_${p}_PASSWORD=\"${NODE_HY2_PASSWORD[$p]}\""
        echo "NODE_HY2_${p}_OBFS=\"${NODE_HY2_OBFS[$p]:-}\""
        echo "NODE_HY2_${p}_SNI=\"${NODE_HY2_SNI[$p]:-}\""
    done >> "$PERSISTENT_INFO_FILE"
    for p in "${!NODE_REALITY_UUID[@]}"; do
        echo "NODE_REALITY_${p}_UUID=\"${NODE_REALITY_UUID[$p]}\""
        echo "NODE_REALITY_${p}_PUBLIC_KEY=\"${NODE_REALITY_PUBLIC_KEY[$p]:-}\""
        echo "NODE_REALITY_${p}_SNI=\"${NODE_REALITY_SNI[$p]:-}\""
        echo "NODE_REALITY_${p}_SHORT_ID=\"${NODE_REALITY_SHORT_ID[$p]:-}\""
        echo "NODE_REALITY_${p}_FP=\"${NODE_REALITY_FP[$p]:-chrome}\""
    done >> "$PERSISTENT_INFO_FILE"
    for p in "${!NODE_VLESS_TLS_UUID[@]}"; do
        echo "NODE_VLESS_TLS_${p}_UUID=\"${NODE_VLESS_TLS_UUID[$p]}\""
        echo "NODE_VLESS_TLS_${p}_TYPE=\"${NODE_VLESS_TLS_TYPE[$p]:-ws}\""
        echo "NODE_VLESS_TLS_${p}_SNI=\"${NODE_VLESS_TLS_SNI[$p]:-}\""
        echo "NODE_VLESS_TLS_${p}_PATH=\"${NODE_VLESS_TLS_PATH[$p]:-}\""
        echo "NODE_VLESS_TLS_${p}_SVC=\"${NODE_VLESS_TLS_SVC[$p]:-}\""
        echo "NODE_VLESS_TLS_${p}_CDN=\"${NODE_VLESS_TLS_CDN[$p]:-}\""
    done >> "$PERSISTENT_INFO_FILE"

    chmod 600 "$PERSISTENT_INFO_FILE"
    success "配置信息保存成功。"
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "此脚本需要以 root 权限运行。请使用 'sudo bash $0'"
        exit 1
    fi
}

# ==================== 系统兼容层（Debian / Alpine） ====================
OS_TYPE=""
INIT_SYSTEM=""
PKG_MGR=""
SVC_SYSTEMCTL="systemctl"
SVC_JOURNALCTL="journalctl"

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
        command -v bash    &>/dev/null || need_install+=("bash")
        command -v curl    &>/dev/null || need_install+=("curl")
        command -v jq      &>/dev/null || need_install+=("jq")
        command -v openssl &>/dev/null || need_install+=("openssl")
        command -v ip      &>/dev/null || need_install+=("iproute2")
        [ -f /etc/ssl/certs/ca-certificates.crt ] || need_install+=("ca-certificates")
        if [ ${#need_install[@]} -gt 0 ]; then
            info "Alpine 基础依赖安装: ${need_install[*]}"
            apk add --no-cache "${need_install[@]}" 2>/dev/null || apk add --no-cache bash curl jq openssl ca-certificates iproute2
        fi
    fi
    info "系统: $OS_TYPE | 包管理器: $PKG_MGR | 初始化: $INIT_SYSTEM"
}

svc_start()   { if [ "$INIT_SYSTEM" == "openrc" ]; then rc-service sing-box start;   else $SVC_SYSTEMCTL start sing-box;   fi; }
svc_stop()    { if [ "$INIT_SYSTEM" == "openrc" ]; then rc-service sing-box stop;    else $SVC_SYSTEMCTL stop sing-box;    fi; }
svc_restart() { if [ "$INIT_SYSTEM" == "openrc" ]; then rc-service sing-box restart; else $SVC_SYSTEMCTL restart sing-box; fi; }
svc_status()  { if [ "$INIT_SYSTEM" == "openrc" ]; then rc-service sing-box status;  else $SVC_SYSTEMCTL status sing-box --no-pager -l; fi; }
svc_is_active() {
    if [ "$INIT_SYSTEM" == "openrc" ]; then rc-service sing-box status &>/dev/null
    else $SVC_SYSTEMCTL is-active --quiet sing-box; fi
}
svc_enable()  { if [ "$INIT_SYSTEM" == "openrc" ]; then rc-update add sing-box default &>/dev/null; else $SVC_SYSTEMCTL enable sing-box &>/dev/null; fi; }
svc_disable() { if [ "$INIT_SYSTEM" == "openrc" ]; then rc-update del sing-box default &>/dev/null; else $SVC_SYSTEMCTL disable sing-box &>/dev/null; fi; }
svc_daemon_reload() { if [ "$INIT_SYSTEM" == "openrc" ]; then true; else $SVC_SYSTEMCTL daemon-reload; fi; }
svc_log_tail() {
    local n="${1:-20}"
    if [ "$INIT_SYSTEM" == "openrc" ]; then
        logread 2>/dev/null | grep -i sing-box | tail -n "$n" || tail -n "$n" /var/log/messages 2>/dev/null || true
    else
        $SVC_JOURNALCTL -u sing-box -n "$n" --no-pager
    fi
}
svc_log_follow() {
    local n="${1:-50}"
    if [ "$INIT_SYSTEM" == "openrc" ]; then
        logread -f 2>/dev/null || tail -f /var/log/messages
    else
        $SVC_JOURNALCTL -u sing-box -f --no-pager -n "$n"
    fi
}

attempt_install_package() {
    local package_name="$1"
    local friendly_name="${2:-$package_name}"

    if command -v "$package_name" &>/dev/null; then
        return 0
    fi

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
}

check_dependencies() {
    info "检查核心依赖..."
    local core_deps=("curl" "openssl" "jq")
    local all_deps_met=true
    for dep in "${core_deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            if ! attempt_install_package "$dep"; then
                all_deps_met=false
            fi
        fi
    done

    if ! $all_deps_met; then
        error "部分核心依赖未能安装。脚本可能无法正常运行。请手动安装后重试。"
        exit 1
    fi
    success "核心依赖检查通过。"
}

check_and_prepare_qrencode() {
    if ! command -v qrencode &>/dev/null; then
        if attempt_install_package "qrencode" "二维码生成工具(qrencode)"; then
            return 0
        else
            warn "未安装 'qrencode'。将无法生成二维码。"
            return 1
        fi
    fi
    return 0
}

find_and_set_singbox_cmd() {
    if [ -x "$SINGBOX_INSTALL_PATH_EXPECTED" ]; then
        SINGBOX_CMD="$SINGBOX_INSTALL_PATH_EXPECTED"
    elif command -v sing-box &>/dev/null; then
        SINGBOX_CMD=$(command -v sing-box)
    else
        SINGBOX_CMD=""
    fi
    if [ -n "$SINGBOX_CMD" ]; then
        info "Sing-box 命令已设置为: $SINGBOX_CMD"
    else
        warn "初始未找到 Sing-box 命令。"
    fi
}

# --- IP detection: local-first, no external services ---
get_server_ips() {
    LAST_SERVER_IP4=""
    LAST_SERVER_IP6=""

    if command -v ip &>/dev/null; then
        local v4_ips v6_ips
        v4_ips=$(ip -o -4 addr show 2>/dev/null | awk '{print $4}' | cut -d/ -f1 || true)
        for ip in $v4_ips; do
            if is_public_ipv4 "$ip" && [ -z "$LAST_SERVER_IP4" ]; then
                LAST_SERVER_IP4="$ip"
            fi
        done
        v6_ips=$(ip -o -6 addr show 2>/dev/null | awk '{print $4}' | cut -d/ -f1 || true)
        for ip in $v6_ips; do
            if is_public_ipv6 "$ip" && [ -z "$LAST_SERVER_IP6" ]; then
                LAST_SERVER_IP6="$ip"
            fi
        done
    fi

    if [ -z "$LAST_SERVER_IP4" ] && [ -z "$LAST_SERVER_IP6" ]; then
        local host_ips
        host_ips=$(hostname -I 2>/dev/null || ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | tr '\n' ' ' || true)
        if [ -n "$host_ips" ]; then
            for ip in $host_ips; do
                if is_public_ipv4 "$ip" && [ -z "$LAST_SERVER_IP4" ]; then
                    LAST_SERVER_IP4="$ip"
                elif is_public_ipv6 "$ip" && [ -z "$LAST_SERVER_IP6" ]; then
                    LAST_SERVER_IP6="$ip"
                fi
            done
        fi
    fi

    if [ -z "$LAST_SERVER_IP4" ] && [ -z "$LAST_SERVER_IP6" ]; then
        warn "未自动获取到公网 IP。"
        local manual_ip=""
        while [ -z "$manual_ip" ]; do
            read -rp "请输入服务器公网 IPv4（推荐）或 IPv6: " manual_ip
            if is_public_ipv4 "$manual_ip"; then
                LAST_SERVER_IP4="$manual_ip"
            elif is_public_ipv6 "$manual_ip"; then
                LAST_SERVER_IP6="$manual_ip"
            else
                error "输入的 IP 地址无效。"
                manual_ip=""
            fi
        done
    fi

    [ -n "$LAST_SERVER_IP4" ] && info "检测到公网 IPv4: $LAST_SERVER_IP4"
    [ -n "$LAST_SERVER_IP6" ] && info "检测到公网 IPv6: $LAST_SERVER_IP6"

    LAST_SERVER_IP="${LAST_SERVER_IP4:-$LAST_SERVER_IP6}"
}

choose_link_ip_mode() {
    echo "------------------------------------------------"
    echo "导入链接 IP 生成选项："
    if [ -n "$LAST_SERVER_IP4" ] && [ -n "$LAST_SERVER_IP6" ]; then
        echo "  1) 仅使用 IPv4 生成导入链接（默认）"
        echo "  2) 仅使用 IPv6 生成导入链接"
        echo "  3) 同时生成 IPv4 与 IPv6 的导入链接"
        local sel
        read -rp "请选择 [1-3]（默认 1）: " sel
        case "$sel" in
            2) LINK_IP_MODE="6" ;;
            3) LINK_IP_MODE="both" ;;
            *) LINK_IP_MODE="4" ;;
        esac
    elif [ -n "$LAST_SERVER_IP4" ]; then
        echo "  仅检测到 IPv4，将使用 IPv4。"
        LINK_IP_MODE="4"
    elif [ -n "$LAST_SERVER_IP6" ]; then
        echo "  仅检测到 IPv6，将使用 IPv6。"
        LINK_IP_MODE="6"
        warn "提示：部分客户端（如 v2rayN）导入 URI 对纯 IPv6 支持较差。"
    fi
    info "已设置导入链接 IP 模式：$LINK_IP_MODE"
}

generate_random_password() {
    # 16 位十六进制字符（64bit 熵），无管道截断、URI 安全
    openssl rand -hex 8
}

install_singbox_core() {
    local force="${1:-false}"
    # 两个路径任一存在即视为已安装；force=true 时强制重装（供菜单 13 使用）
    if [ "$force" != "true" ] && { [ -x "$SINGBOX_INSTALL_PATH_EXPECTED" ] || command -v sing-box &>/dev/null; }; then
        info "Sing-box 已安装，自动跳过安装步骤。"

        # 校验 drop-in 期望路径：官方 install.sh 的 drop-in 硬编码 /usr/local/bin/sing-box
        # 若该路径不存在但 command -v 能找到，则复制一份，避免 203/EXEC
        local drop_in="/etc/systemd/system/sing-box.service.d/10-donot_touch.conf"
        if [ -f "$drop_in" ] && [ ! -x "$SINGBOX_INSTALL_PATH_EXPECTED" ]; then
            local real_bin
            real_bin=$(command -v sing-box 2>/dev/null || true)
            if [ -n "$real_bin" ] && [ -x "$real_bin" ]; then
                info "检测到 drop-in 指向 ${SINGBOX_INSTALL_PATH_EXPECTED} 但该文件不存在。"
                info "正在从 ${real_bin} 复制到 ${SINGBOX_INSTALL_PATH_EXPECTED} ..."
                cp -f "$real_bin" "$SINGBOX_INSTALL_PATH_EXPECTED"
                chmod 755 "$SINGBOX_INSTALL_PATH_EXPECTED"
                success "已补齐 ${SINGBOX_INSTALL_PATH_EXPECTED}"
            fi
        fi

        find_and_set_singbox_cmd
        if [ -n "$SINGBOX_CMD" ]; then
            local current_version
            current_version=$($SINGBOX_CMD version | awk '{print $3}' 2>/dev/null || true)
            [ -n "$current_version" ] && info "当前版本: $current_version"
        fi
        info "如需强制更新，请使用菜单选项 13。"
        return 0
    fi

    info "正在安装/更新 Sing-box (beta)..."
    # 官方安装脚本（sing-box.app 为官方域名），避免第三方托管被替换的供应链风险
    local install_script_url="https://sing-box.app/install.sh"
    local tmp_script
    tmp_script=$(mktemp)
    # 函数返回或脚本退出（含 Ctrl+C）时清理临时文件
    trap 'rm -f "$tmp_script"; trap - RETURN' RETURN

    if ! curl -fsSL --proto '=https' --tlsv1.2 --connect-timeout 10 --max-time 60 "$install_script_url" -o "$tmp_script"; then
        error "下载 Sing-box 安装脚本失败。"
        return 1
    fi

    info "安装脚本已下载到: $tmp_script，开始执行..."
    if bash "$tmp_script" --beta; then
        success "Sing-box 安装/更新成功。"
        find_and_set_singbox_cmd
        if [ -z "$SINGBOX_CMD" ]; then
            error "安装后仍无法找到 sing-box 命令。请检查安装和 PATH。"
            return 1
        fi
    else
        error "Sing-box 安装失败。"
        return 1
    fi
    return 0
}

generate_self_signed_cert() {
    local domain_cn="$1"
    if [ -f "$HYSTERIA_CERT_PEM" ] && [ -f "$HYSTERIA_CERT_KEY" ]; then
        info "检测到已存在的证书: ${HYSTERIA_CERT_PEM} 和 ${HYSTERIA_CERT_KEY}"
        local existing_cn
        existing_cn=$(openssl x509 -in "$HYSTERIA_CERT_PEM" -noout -subject 2>/dev/null | sed -n 's/.*CN[[:space:]]*=[[:space:]]*\([^,]*\).*/\1/p' || true)
        if [ "$existing_cn" == "$domain_cn" ]; then
            if openssl x509 -in "$HYSTERIA_CERT_PEM" -noout -text 2>/dev/null | grep -q "Subject Alternative Name"; then
                info "证书 CN ($existing_cn) 与目标 ($domain_cn) 匹配，跳过重新生成。"
                return 0
            fi
            warn "现有证书缺少 SAN 扩展，将重新生成以兼容现代 TLS 客户端。"
        else
            warn "证书 CN ($existing_cn) 与目标 ($domain_cn) 不匹配。"
            local regen_cert_choice
            read -rp "是否使用新的 CN ($domain_cn) 重新生成证书? (y/N): " regen_cert_choice
            if [[ ! "$regen_cert_choice" =~ ^[Yy]$ ]]; then
                info "保留现有证书。"
                return 0
            fi
        fi
    fi

    info "正在为 Hysteria2 生成自签名证书 (CN=${domain_cn})..."
    mkdir -p "$HYSTERIA_CERT_DIR"
    openssl ecparam -genkey -name prime256v1 -out "$HYSTERIA_CERT_KEY"
    chmod 600 "$HYSTERIA_CERT_KEY"
    # 现代客户端只认 SAN；OpenSSL < 1.1.1 不支持 -addext 时回退为仅 CN
    if ! openssl req -new -x509 -days 3650 -key "$HYSTERIA_CERT_KEY" -out "$HYSTERIA_CERT_PEM" \
        -subj "/CN=${domain_cn}" -addext "subjectAltName=DNS:${domain_cn}" 2>/dev/null; then
        warn "当前 OpenSSL 不支持 -addext，回退为仅含 CN 的证书..."
        openssl req -new -x509 -days 3650 -key "$HYSTERIA_CERT_KEY" -out "$HYSTERIA_CERT_PEM" -subj "/CN=${domain_cn}"
    fi
    chmod 600 "$HYSTERIA_CERT_PEM"
    success "自签名证书生成成功。"
    info "证书: ${HYSTERIA_CERT_PEM}"
    info "私钥: ${HYSTERIA_CERT_KEY}"
}

generate_reality_credentials() {
    if [ -z "$SINGBOX_CMD" ]; then
        error "Sing-box command (SINGBOX_CMD) 未设置。无法生成凭证。"
        find_and_set_singbox_cmd
        if [ -z "$SINGBOX_CMD" ]; then
            error "尝试查找后 Sing-box command 仍未设置。"
            return 1
        fi
    fi

    info "使用命令 '$SINGBOX_CMD' 生成 Reality UUID 和 Keypair..."

    local reality_uuid_val key_pair_output reality_private_key_val reality_public_key_val

    reality_uuid_val=$($SINGBOX_CMD generate uuid)
    if [ -z "$reality_uuid_val" ]; then
        error "生成 UUID 失败或输出为空。"
        return 1
    fi
    info "生成的 UUID: $reality_uuid_val"
    LAST_REALITY_UUID="$reality_uuid_val"

    # 每台服务器随机生成 short_id，避免共用固定值带来的指纹特征
    LAST_REALITY_SHORT_ID=$(openssl rand -hex 8)
    info "生成的 Reality Short ID: $LAST_REALITY_SHORT_ID"

    key_pair_output=$($SINGBOX_CMD generate reality-keypair)
    if [ -z "$key_pair_output" ]; then
        error "生成 Reality keypair 失败或输出为空。"
        return 1
    fi
    echo "$key_pair_output"

    reality_private_key_val=$(echo "$key_pair_output" | awk -F': ' '/PrivateKey:/ {print $2}' | xargs)
    reality_public_key_val=$(echo "$key_pair_output" | awk -F': ' '/PublicKey:/ {print $2}' | xargs)

    if [ -z "$reality_private_key_val" ] || [ -z "$reality_public_key_val" ]; then
        error "解析 Reality keypair 失败。"
        return 1
    fi

    success "Reality UUID: $reality_uuid_val"
    success "Reality Public Key: $reality_public_key_val"
    TEMP_REALITY_PRIVATE_KEY="$reality_private_key_val"
    LAST_REALITY_PUBLIC_KEY="$reality_public_key_val"
}

get_vless_tls_cert_fp() {
    [ -f "$VLESS_TLS_CERT_PEM" ] || { echo ""; return; }
    openssl x509 -in "$VLESS_TLS_CERT_PEM" -noout -fingerprint -sha256 2>/dev/null \
        | sed 's/.*=//' | tr -d ':' | tr 'A-Z' 'a-z'
}

generate_vless_tls_cert() {
    local domain_cn="$1"
    if [ -f "$VLESS_TLS_CERT_PEM" ] && [ -f "$VLESS_TLS_CERT_KEY" ]; then
        local existing_cn
        existing_cn=$(openssl x509 -in "$VLESS_TLS_CERT_PEM" -noout -subject 2>/dev/null | sed -n 's/.*CN[[:space:]]*=[[:space:]]*\([^,]*\).*/\1/p' || true)
        if [ "$existing_cn" == "$domain_cn" ]; then
            info "VLESS+TLS 证书 CN 匹配，复用现有证书。"
            return 0
        fi
        warn "VLESS+TLS 证书 CN ($existing_cn) 与目标 ($domain_cn) 不匹配，重新生成。"
    fi
    info "生成 VLESS+TLS 自签证书 (CN=${domain_cn})..."
    mkdir -p "$VLESS_TLS_CERT_DIR"
    chmod 700 "$VLESS_TLS_CERT_DIR"
    openssl ecparam -genkey -name prime256v1 -out "$VLESS_TLS_CERT_KEY"
    chmod 600 "$VLESS_TLS_CERT_KEY"
    if ! openssl req -new -x509 -days 3650 -key "$VLESS_TLS_CERT_KEY" -out "$VLESS_TLS_CERT_PEM" \
        -subj "/CN=${domain_cn}" -addext "subjectAltName=DNS:${domain_cn}" 2>/dev/null; then
        warn "当前 OpenSSL 不支持 -addext，回退为仅含 CN 的证书..."
        openssl req -new -x509 -days 3650 -key "$VLESS_TLS_CERT_KEY" -out "$VLESS_TLS_CERT_PEM" -subj "/CN=${domain_cn}"
    fi
    chmod 600 "$VLESS_TLS_CERT_PEM"
    success "VLESS+TLS 自签证书生成成功。"
    info "证书: ${VLESS_TLS_CERT_PEM}"
    info "私钥: ${VLESS_TLS_CERT_KEY}"
}

get_listen_address() {
    # 入站固定双栈监听，客户端按需选择 v4 或 v6 链接
    if [ ! -f /proc/net/if_inet6 ]; then
        echo "0.0.0.0"
    else
        echo "::"
    fi
}

create_config_json() {
    local mode="$1"
    local hy2_port="$2"
    local hy2_password="$3"
    local hy2_masquerade_cn="$4"
    local reality_port="$5"
    local reality_uuid="$6"
    local reality_private_key="$7"
    local reality_sni="$8"
    local vtls_port="${9:-}"
    local vtls_uuid="${10:-}"
    local vtls_transport="${11:-}"
    local vtls_sni="${12:-}"
    local vtls_path="${13:-}"
    local vtls_svc="${14:-}"

    if [ -z "$SINGBOX_CMD" ]; then
        error "Sing-box command (SINGBOX_CMD) 未设置。无法校验或格式化配置文件。"
        return 1
    fi

    info "正在更新配置文件: ${SINGBOX_CONFIG_FILE}"
    mkdir -p "$SINGBOX_CONFIG_DIR"
    chmod 700 "$SINGBOX_CONFIG_DIR"

    local listen_addr
    listen_addr=$(get_listen_address)

    # 读取现有 inbounds（不存在则为空数组）
    local existing_inbounds="[]"
    if [ -f "$SINGBOX_CONFIG_FILE" ]; then
        existing_inbounds=$(jq '.inbounds // []' "$SINGBOX_CONFIG_FILE" 2>/dev/null || echo "[]")
    fi
    existing_inbounds=$(jq --arg listen "$listen_addr" 'map(if .type == "tun" then . else .listen = $listen end)' <<< "$existing_inbounds")

    if [ "$mode" == "all" ] || [ "$mode" == "hysteria2" ]; then
        local hy2_tag="hy2-in-${hy2_port}"
        existing_inbounds=$(jq --arg tag "$hy2_tag" 'map(select(.tag != $tag))' <<< "$existing_inbounds")
        existing_inbounds=$(jq --argjson port "$hy2_port" \
            --arg password "$hy2_password" \
            --arg masquerade "https://${hy2_masquerade_cn}" \
            --arg cert "$HYSTERIA_CERT_PEM" \
            --arg key "$HYSTERIA_CERT_KEY" \
            --arg sni "$hy2_masquerade_cn" \
            --arg tag "$hy2_tag" \
            --arg obfs_password "${LAST_HY2_OBFS_PASSWORD:-}" \
            --arg listen "$listen_addr" \
            '. + [({
                type: "hysteria2",
                tag: $tag,
                listen: $listen,
                listen_port: $port,
                users: [{password: $password}],
                masquerade: $masquerade,
                up_mbps: 100,
                down_mbps: 500,
                tls: {
                    enabled: true,
                    alpn: ["h3"],
                    certificate_path: $cert,
                    key_path: $key,
                    server_name: $sni
                }
            } + (if $obfs_password != "" then {obfs: {type: "salamander", password: $obfs_password}} else {} end))]' <<< "$existing_inbounds")
    fi

    if [ "$mode" == "all" ] || [ "$mode" == "reality" ]; then
        local vless_tag="vless-in-${reality_port}"
        existing_inbounds=$(jq --arg tag "$vless_tag" 'map(select(.tag != $tag))' <<< "$existing_inbounds")
        existing_inbounds=$(jq --argjson port "$reality_port" \
            --arg uuid "$reality_uuid" \
            --arg sni "$reality_sni" \
            --arg private_key "$reality_private_key" \
            --arg short_id "$LAST_REALITY_SHORT_ID" \
            --arg tag "$vless_tag" \
            --arg listen "$listen_addr" \
            '. + [{
                type: "vless",
                tag: $tag,
                listen: $listen,
                listen_port: $port,
                users: [{uuid: $uuid, flow: "xtls-rprx-vision"}],
                tls: {
                    enabled: true,
                    server_name: $sni,
                    reality: {
                        enabled: true,
                        handshake: {server: $sni, server_port: 443},
                        private_key: $private_key,
                        short_id: [$short_id]
                    }
                }
            }]' <<< "$existing_inbounds")
    fi

    if [ "$mode" == "vless_tls" ]; then
        local vtls_tag="vless-tls-in-${vtls_port}"
        existing_inbounds=$(jq --arg tag "$vtls_tag" 'map(select(.tag != $tag))' <<< "$existing_inbounds")
        existing_inbounds=$(jq --argjson port "$vtls_port" \
            --arg uuid "$vtls_uuid" \
            --arg sni "$vtls_sni" \
            --arg cert "$VLESS_TLS_CERT_PEM" \
            --arg key "$VLESS_TLS_CERT_KEY" \
            --arg tag "$vtls_tag" \
            --arg listen "$listen_addr" \
            --arg ttype "$vtls_transport" \
            --arg tpath "$vtls_path" \
            --arg tsvc "$vtls_svc" \
            '. + [(
                {
                    type: "vless",
                    tag: $tag,
                    listen: $listen,
                    listen_port: $port,
                    users: [{uuid: $uuid}],
                    tls: {
                        enabled: true,
                        server_name: $sni,
                        certificate_path: $cert,
                        key_path: $key,
                        alpn: ["h2", "http/1.1"]
                    }
                }
                + (if $ttype == "ws" then
                    {transport: {type: "ws", path: $tpath}}
                   elif $ttype == "httpupgrade" then
                    {transport: {type: "httpupgrade", path: $tpath}}
                   elif $ttype == "grpc" then
                    {transport: {type: "grpc", service_name: $tsvc}}
                   else {} end)
            )]' <<< "$existing_inbounds")
    fi

    local _direct_ob
    case "${OUTBOUND_MODE:-both}" in
        v4) _direct_ob='{"type":"direct","tag":"direct","domain_resolver":{"server":"local","strategy":"ipv4_only"}}' ;;
        v6) _direct_ob='{"type":"direct","tag":"direct","domain_resolver":{"server":"local","strategy":"ipv6_only"}}' ;;
        *)  _direct_ob='{"type":"direct","tag":"direct"}' ;;
    esac
    local _ob="[${_direct_ob},{\"type\":\"block\",\"tag\":\"block\"}]"
    local _t _p _rt _tag
    for _t in "${!RELAY_JSON[@]}"; do
        _ob=$(jq --argjson o "${RELAY_JSON[$_t]}" '. + [$o]' <<< "$_ob")
    done
    local _rules
    _rules=$(_relay_build_rules_json "$existing_inbounds")

    jq -n --argjson inbounds "$existing_inbounds" --argjson outbounds "$_ob" --argjson rules "$_rules" '
        walk(if type == "object" then del(.domain_strategy) else . end)
        | {
            log: {level: "info", timestamp: true},
            dns: {servers: [{type: "local", tag: "local"}]},
            inbounds: $inbounds,
            outbounds: $outbounds,
            route: {rules: $rules, final: "direct"}
        }
    ' > "$SINGBOX_CONFIG_FILE"

    chmod 600 "$SINGBOX_CONFIG_FILE"

    info "正在校验配置文件..."
    if $SINGBOX_CMD check -c "$SINGBOX_CONFIG_FILE"; then
        success "配置文件语法正确。"
        info "正在格式化配置文件..."
        if $SINGBOX_CMD format -c "$SINGBOX_CONFIG_FILE" -w; then
            success "配置文件格式化成功。"
        else
            warn "配置文件格式化失败，但语法可能仍正确。"
        fi
    else
        error "配置文件语法错误。请检查 ${SINGBOX_CONFIG_FILE}"
        cat "${SINGBOX_CONFIG_FILE}"
        return 1
    fi
}

create_systemd_service() {
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
ExecReload=/bin/kill -HUP \$MAINPID
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
}

start_singbox_service() {
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
}

display_and_store_config_info() {
    local mode="${1:-all}"
    LAST_INSTALL_MODE="$mode"

    local qrencode_is_ready=false
    local want_qr="n"
    read -rp "是否生成二维码？(y/N): " want_qr
    if [[ "$want_qr" =~ ^[Yy]$ ]]; then
        if check_and_prepare_qrencode; then qrencode_is_ready=true; fi
    fi

    gen_hy2_link() {
        local port="$1"
        local ip="$2"
        local h
        h=$(format_host_for_uri "$ip")
        local pass="${NODE_HY2_PASSWORD[$port]}"
        local obfs="${NODE_HY2_OBFS[$port]:-}"
        local sni="${NODE_HY2_SNI[$port]:-}"
        local link="hy2://${pass}@${h}:${port}?sni=${sni}&alpn=h3&insecure=1"
        [ -n "$obfs" ] && link="${link}&obfs=salamander&obfs-password=${obfs}"
        echo "${link}#Hy2-${port}-${ip}"
    }
    gen_vless_link() {
        local port="$1"
        local ip="$2"
        local h
        h=$(format_host_for_uri "$ip")
        local uuid="${NODE_REALITY_UUID[$port]}"
        local pub="${NODE_REALITY_PUBLIC_KEY[$port]}"
        local sni="${NODE_REALITY_SNI[$port]}"
        local sid="${NODE_REALITY_SHORT_ID[$port]}"
        local fp="${NODE_REALITY_FP[$port]:-chrome}"
        echo "vless://${uuid}@${h}:${port}?security=reality&sni=${sni}&fp=${fp}&pbk=${pub}&sid=${sid}&flow=xtls-rprx-vision&type=tcp#Reality-${port}-${ip}"
    }
    gen_vless_tls_link() {
        # 用法: gen_vless_tls_link <port> <addr> <link_port> <sni> <use_pin> <tag_sfx>
        local port="$1" addr="$2" link_port="$3" sni="$4" use_pin="$5" tag_sfx="$6"
        local uuid="${NODE_VLESS_TLS_UUID[$port]}"
        local tp="${NODE_VLESS_TLS_TYPE[$port]}"
        local path="${NODE_VLESS_TLS_PATH[$port]:-}"
        local svc="${NODE_VLESS_TLS_SVC[$port]:-}"
        local h
        h=$(format_host_for_uri "$addr")
        local link="vless://${uuid}@${h}:${link_port}?security=tls&sni=${sni}&fp=chrome&type=${tp}"
        if [ "$use_pin" = "1" ]; then
            local fp
            fp=$(get_vless_tls_cert_fp)
            [ -n "$fp" ] && link="${link}&pinnedPeerCertSha256=${fp}"
        fi
        if [[ "$tp" == "ws" || "$tp" == "httpupgrade" ]]; then
            link="${link}&path=${path}&host=${sni}"
        elif [[ "$tp" == "grpc" ]]; then
            link="${link}&serviceName=${svc}"
        fi
        echo "${link}#${tag_sfx}"
    }

    if [[ "$mode" == "all" || "$mode" == "hysteria2" ]]; then
        local p
        for p in "${!NODE_HY2_PASSWORD[@]}"; do
            echo -e "----------------------------------------------------"
            echo -e "${GREEN}${BOLD} Hysteria2 (端口 ${p}) 配置信息:${NC}"
            echo -e "SNI: ${GREEN}${NODE_HY2_SNI[$p]}${NC}   端口: ${GREEN}${p}${NC}"
            echo -e "密码/Auth: ${GREEN}${NODE_HY2_PASSWORD[$p]}${NC}"
            echo -e "混淆密码 (obfs): ${GREEN}${NODE_HY2_OBFS[$p]:-未启用}${NC}"
            if [[ "$LINK_IP_MODE" == "4" || "$LINK_IP_MODE" == "both" ]] && [[ -n "$LAST_SERVER_IP4" ]]; then
                local link
                link=$(gen_hy2_link "$p" "$LAST_SERVER_IP4")
                echo -e "${CYAN}hy2 导入链接(IPv4):${NC} ${GREEN}${link}${NC}"
                $qrencode_is_ready && command -v qrencode &>/dev/null && { echo "二维码:"; qrencode -t ANSIUTF8 "$link"; }
            fi
            if [[ "$LINK_IP_MODE" == "6" || "$LINK_IP_MODE" == "both" ]] && [[ -n "$LAST_SERVER_IP6" ]]; then
                local link6
                link6=$(gen_hy2_link "$p" "$LAST_SERVER_IP6")
                echo -e "${CYAN}hy2 导入链接(IPv6):${NC} ${GREEN}${link6}${NC}"
                $qrencode_is_ready && command -v qrencode &>/dev/null && { echo "二维码:"; qrencode -t ANSIUTF8 "$link6"; }
            fi
        done
    fi

    if [[ "$mode" == "all" || "$mode" == "reality" ]]; then
        local p
        for p in "${!NODE_REALITY_UUID[@]}"; do
            echo -e "----------------------------------------------------"
            echo -e "${GREEN}${BOLD} Reality (端口 ${p}) 配置信息:${NC}"
            echo -e "UUID: ${GREEN}${NODE_REALITY_UUID[$p]}${NC}"
            echo -e "SNI: ${GREEN}${NODE_REALITY_SNI[$p]}${NC}   FP: ${GREEN}${NODE_REALITY_FP[$p]:-chrome}${NC}"
            echo -e "PublicKey: ${GREEN}${NODE_REALITY_PUBLIC_KEY[$p]}${NC}"
            echo -e "ShortID: ${GREEN}${NODE_REALITY_SHORT_ID[$p]}${NC}"
            if [[ "$LINK_IP_MODE" == "4" || "$LINK_IP_MODE" == "both" ]] && [[ -n "$LAST_SERVER_IP4" ]]; then
                local link
                link=$(gen_vless_link "$p" "$LAST_SERVER_IP4")
                echo -e "${CYAN}Reality 导入链接(IPv4):${NC} ${GREEN}${link}${NC}"
                $qrencode_is_ready && command -v qrencode &>/dev/null && { echo "二维码:"; qrencode -t ANSIUTF8 "$link"; }
            fi
            if [[ "$LINK_IP_MODE" == "6" || "$LINK_IP_MODE" == "both" ]] && [[ -n "$LAST_SERVER_IP6" ]]; then
                local link6
                link6=$(gen_vless_link "$p" "$LAST_SERVER_IP6")
                echo -e "${CYAN}Reality 导入链接(IPv6):${NC} ${GREEN}${link6}${NC}"
                $qrencode_is_ready && command -v qrencode &>/dev/null && { echo "二维码:"; qrencode -t ANSIUTF8 "$link6"; }
            fi
        done
    fi

    if [[ "$mode" == "all" || "$mode" == "vless_tls" ]]; then
        local p
        for p in "${!NODE_VLESS_TLS_UUID[@]}"; do
            local tp="${NODE_VLESS_TLS_TYPE[$p]:-ws}"
            echo -e "----------------------------------------------------"
            echo -e "${GREEN}${BOLD} VLESS+TLS (端口 ${p}, ${tp}) 配置信息:${NC}"
            echo -e "UUID: ${GREEN}${NODE_VLESS_TLS_UUID[$p]}${NC}"
            echo -e "SNI: ${GREEN}${NODE_VLESS_TLS_SNI[$p]:-}${NC}   Type: ${GREEN}${tp}${NC}"
            [[ -n "${NODE_VLESS_TLS_PATH[$p]:-}" ]] && echo -e "Path: ${GREEN}${NODE_VLESS_TLS_PATH[$p]}${NC}"
            [[ -n "${NODE_VLESS_TLS_SVC[$p]:-}" ]] && echo -e "ServiceName: ${GREEN}${NODE_VLESS_TLS_SVC[$p]}${NC}"
            local cdn="${NODE_VLESS_TLS_CDN[$p]:-}"
            local sni="${NODE_VLESS_TLS_SNI[$p]:-}"
            if [ -n "$cdn" ]; then
                local link_cdn
                link_cdn=$(gen_vless_tls_link "$p" "$cdn" "443" "$cdn" "0" "VLESS-TLS-${p}-CDN")
                echo -e "${CYAN}CDN 链接(推荐):${NC} ${GREEN}${link_cdn}${NC}"
                $qrencode_is_ready && command -v qrencode &>/dev/null && { echo "二维码:"; qrencode -t ANSIUTF8 "$link_cdn"; }
            fi
            if [[ "$LINK_IP_MODE" == "4" || "$LINK_IP_MODE" == "both" ]] && [[ -n "$LAST_SERVER_IP4" ]]; then
                local link
                link=$(gen_vless_tls_link "$p" "$LAST_SERVER_IP4" "$p" "$sni" "1" "VLESS-TLS-${p}-IPv4-Direct")
                echo -e "${CYAN}直连链接(IPv4, 带证书指纹):${NC} ${GREEN}${link}${NC}"
            fi
            if [[ "$LINK_IP_MODE" == "6" || "$LINK_IP_MODE" == "both" ]] && [[ -n "$LAST_SERVER_IP6" ]]; then
                local link6
                link6=$(gen_vless_tls_link "$p" "$LAST_SERVER_IP6" "$p" "$sni" "1" "VLESS-TLS-${p}-IPv6-Direct")
                echo -e "${CYAN}直连链接(IPv6, 带证书指纹):${NC} ${GREEN}${link6}${NC}"
            fi
            echo -e "${YELLOW}CDN 链接用 CF 真证书，直连链接用 pinnedPeerCertSha256，均兼容 Xray 26.2.6+${NC}"
        done
    fi

    save_persistent_info
}

# --- Installation functions ---
install_hysteria2_reality() {
    info "开始安装 Hysteria2 + Reality (共存)..."
    install_singbox_core || return 1
    get_server_ips
    choose_link_ip_mode

    prompt_port "请输入 Hysteria2 监听端口" "$DEFAULT_HYSTERIA_PORT" LAST_HY2_PORT udp
    prompt_domain "请输入 Hysteria2 伪装域名/证书CN" "$DEFAULT_HYSTERIA_MASQUERADE_CN" LAST_HY2_MASQUERADE_CN

    prompt_port "请输入 Reality (VLESS) 监听端口" "$DEFAULT_REALITY_PORT" LAST_REALITY_PORT tcp
    prompt_domain "请输入 Reality 目标SNI/握手服务器" "$DEFAULT_REALITY_SNI" LAST_REALITY_SNI

    LAST_HY2_PASSWORD=$(generate_random_password)
    LAST_HY2_OBFS_PASSWORD=$(generate_random_password)
    info "生成的 Hysteria2 密码: ${LAST_HY2_PASSWORD}"
    info "生成的 Hysteria2 混淆密码: ${LAST_HY2_OBFS_PASSWORD}"

    generate_self_signed_cert "$LAST_HY2_MASQUERADE_CN" || return 1
    generate_reality_credentials || return 1

    create_config_json "all" \
        "$LAST_HY2_PORT" "$LAST_HY2_PASSWORD" "$LAST_HY2_MASQUERADE_CN" \
        "$LAST_REALITY_PORT" "$LAST_REALITY_UUID" "$TEMP_REALITY_PRIVATE_KEY" "$LAST_REALITY_SNI" \
        || return 1

    NODE_HY2_PASSWORD["$LAST_HY2_PORT"]="$LAST_HY2_PASSWORD"
    NODE_HY2_OBFS["$LAST_HY2_PORT"]="$LAST_HY2_OBFS_PASSWORD"
    NODE_HY2_SNI["$LAST_HY2_PORT"]="$LAST_HY2_MASQUERADE_CN"
    NODE_REALITY_UUID["$LAST_REALITY_PORT"]="$LAST_REALITY_UUID"
    NODE_REALITY_PUBLIC_KEY["$LAST_REALITY_PORT"]="$LAST_REALITY_PUBLIC_KEY"
    NODE_REALITY_SNI["$LAST_REALITY_PORT"]="$LAST_REALITY_SNI"
    NODE_REALITY_SHORT_ID["$LAST_REALITY_PORT"]="$LAST_REALITY_SHORT_ID"
    NODE_REALITY_FP["$LAST_REALITY_PORT"]="$LAST_REALITY_FINGERPRINT"

    create_systemd_service
    start_singbox_service || return 1
    install_script_shortcut || true

    success "Hysteria2 + Reality 安装配置完成！"
    display_and_store_config_info "all"
}

install_hysteria2_only() {
    info "开始安装 Hysteria2..."
    install_singbox_core || return 1
    get_server_ips
    choose_link_ip_mode

    prompt_port "请输入 Hysteria2 监听端口" "$DEFAULT_HYSTERIA_PORT" LAST_HY2_PORT udp
    prompt_domain "请输入 Hysteria2 伪装域名/证书CN" "$DEFAULT_HYSTERIA_MASQUERADE_CN" LAST_HY2_MASQUERADE_CN

    LAST_HY2_PASSWORD=$(generate_random_password)
    LAST_HY2_OBFS_PASSWORD=$(generate_random_password)
    info "生成的 Hysteria2 密码: ${LAST_HY2_PASSWORD}"
    info "生成的 Hysteria2 混淆密码: ${LAST_HY2_OBFS_PASSWORD}"

    generate_self_signed_cert "$LAST_HY2_MASQUERADE_CN" || return 1

    create_config_json "hysteria2" \
        "$LAST_HY2_PORT" "$LAST_HY2_PASSWORD" "$LAST_HY2_MASQUERADE_CN" \
        "" "" "" "" \
        || return 1

    # 写入多节点数组
    NODE_HY2_PASSWORD["$LAST_HY2_PORT"]="$LAST_HY2_PASSWORD"
    NODE_HY2_OBFS["$LAST_HY2_PORT"]="$LAST_HY2_OBFS_PASSWORD"
    NODE_HY2_SNI["$LAST_HY2_PORT"]="$LAST_HY2_MASQUERADE_CN"

    create_systemd_service
    start_singbox_service || return 1
    install_script_shortcut || true

    success "Hysteria2 安装配置完成！"
    display_and_store_config_info "hysteria2"
}

install_reality_only() {
    info "开始安装 Reality (VLESS)..."
    install_singbox_core || return 1
    get_server_ips
    choose_link_ip_mode

    prompt_port "请输入 Reality (VLESS) 监听端口" "$DEFAULT_REALITY_PORT" LAST_REALITY_PORT tcp
    prompt_domain "请输入 Reality 目标SNI/握手服务器" "$DEFAULT_REALITY_SNI" LAST_REALITY_SNI

    generate_reality_credentials || return 1

    create_config_json "reality" \
        "" "" "" \
        "$LAST_REALITY_PORT" "$LAST_REALITY_UUID" "$TEMP_REALITY_PRIVATE_KEY" "$LAST_REALITY_SNI" \
        || return 1

    # 写入多节点数组
    NODE_REALITY_UUID["$LAST_REALITY_PORT"]="$LAST_REALITY_UUID"
    NODE_REALITY_PUBLIC_KEY["$LAST_REALITY_PORT"]="$LAST_REALITY_PUBLIC_KEY"
    NODE_REALITY_SNI["$LAST_REALITY_PORT"]="$LAST_REALITY_SNI"
    NODE_REALITY_SHORT_ID["$LAST_REALITY_PORT"]="$LAST_REALITY_SHORT_ID"
    NODE_REALITY_FP["$LAST_REALITY_PORT"]="$LAST_REALITY_FINGERPRINT"

    create_systemd_service
    start_singbox_service || return 1
    install_script_shortcut || true

    success "Reality (VLESS) 安装配置完成！"
    display_and_store_config_info "reality"
}

install_vless_tls() {
    info "开始安装 VLESS + TLS ..."
    install_singbox_core || return 1
    get_server_ips
    choose_link_ip_mode

    echo ""
    echo "选择传输层（均支持套 CDN）:"
    echo "  1. WebSocket (ws)"
    echo "  2. gRPC"
    echo "  3. HTTPUpgrade"
    local t
    read -rp "请选择 [1-3]: " t
    local transport
    case "$t" in
        1) transport="ws" ;;
        2) transport="grpc" ;;
        3) transport="httpupgrade" ;;
        *) error "无效选择"; return 1 ;;
    esac

    echo ""
    echo "CF 支持端口（客户端可通过这些端口走 CDN，建议从下面选一个）:"
    echo "  443系: 443 2053 2083 2087 2096 8443"
    echo "  80系 : 80 8080 8880 2052 2082 2086 2095"
    echo "  提示: 从上述端口选，客户端改 address/port 即可走 CDN；也可选任意端口仅直连"
    echo ""
    local port
    prompt_port "请输入 VLESS+TLS 监听端口" "8444" port tcp

    local sni
    prompt_domain "请输入 SNI / 证书 CN" "$DEFAULT_REALITY_SNI" sni

    local path="" svc=""
    if [[ "$transport" == "ws" || "$transport" == "httpupgrade" ]]; then
        read -rp "路径 [默认 /vless]: " path
        path="${path:-/vless}"
    elif [[ "$transport" == "grpc" ]]; then
        read -rp "gRPC serviceName [默认 grpc]: " svc
        svc="${svc:-grpc}"
    fi

    echo ""
    echo "是否绑定 CDN 域名？(用于生成 CDN 链接，可留空跳过)"
    echo "  前提: 该域名已托管到 CF 且配置了 DNS（橙色云代理）"
    echo "         CF 面板 SSL/TLS 模式设为 Full 或 Full (strict)"
    local cdn=""
    read -rp "CDN 域名 [留空跳过]: " cdn
    if [ -n "$cdn" ]; then
        if is_valid_domain "$cdn"; then
            info "已绑定 CDN 域名: $cdn"
        else
            warn "CDN 域名无效，已忽略"
            cdn=""
        fi
    fi

    local uuid
    uuid=$($SINGBOX_CMD generate uuid)
    if [ -z "$uuid" ]; then
        error "生成 UUID 失败"
        return 1
    fi
    info "生成的 UUID: $uuid"

    generate_vless_tls_cert "$sni" || return 1

    create_config_json "vless_tls" "" "" "" "" "" "" "" \
        "$port" "$uuid" "$transport" "$sni" "$path" "$svc" || return 1

    NODE_VLESS_TLS_UUID["$port"]="$uuid"
    NODE_VLESS_TLS_TYPE["$port"]="$transport"
    NODE_VLESS_TLS_SNI["$port"]="$sni"
    NODE_VLESS_TLS_PATH["$port"]="$path"
    NODE_VLESS_TLS_SVC["$port"]="$svc"
    NODE_VLESS_TLS_CDN["$port"]="$cdn"

    create_systemd_service
    start_singbox_service || return 1
    install_script_shortcut || true

    success "VLESS + TLS ($transport) 安装配置完成！"
    echo ""
    if [ -n "$cdn" ]; then
        echo -e "${GREEN}${BOLD}===== CDN 节点已就绪 =====${NC}"
        echo -e "  CDN 域名: ${GREEN}${cdn}${NC}"
        echo -e "  客户端: address=${cdn}  port=443  sni=${cdn}"
        echo -e "  ${YELLOW}CF 面板请确认: DNS 橙色云开启，SSL/TLS 模式 Full 或 Full (strict)${NC}"
        echo -e "  ${YELLOW}若源站用自签证书，CF 需装 Origin Certificate 或改 Full 模式${NC}"
    else
        echo -e "${YELLOW}${BOLD}===== 直连节点已就绪 =====${NC}"
        echo -e "  链接已带 pinnedPeerCertSha256，兼容 Xray 26.2.6+"
    fi
    echo ""
    display_and_store_config_info "vless_tls"
}

vless_branch_menu() {
    while true; do
        clear
        echo "================================================"
        echo -e "${CYAN}${BOLD}          VLESS 分支安装${NC}"
        echo "================================================"
        echo "  1. VLESS + Reality + Vision (抗审查首选)"
        echo "  2. VLESS + TLS (ws / grpc / httpupgrade，支持套 CDN)"
        echo "  0. 返回"
        echo "================================================"
        local c
        read -rp "请选择 [0-2]: " c
        case "$c" in
            1) install_reality_only ;;
            2) install_vless_tls ;;
            0) return ;;
            *) warn "无效选项"; sleep 1 ;;
        esac
        read -n 1 -s -r -p "按任意键继续..."
    done
}

show_current_import_info() {
    if [ -z "$LAST_INSTALL_MODE" ]; then
        warn "尚未通过此脚本安装任何配置，或上次安装信息未保留。"
        info "请先执行安装操作 (选项 1, 2, 或 3)，或者确保 ${PERSISTENT_INFO_FILE} 文件存在且包含信息。"
        return
    fi
    info "显示上次保存的配置信息 (${LAST_INSTALL_MODE} 模式, IP 模式: ${LINK_IP_MODE})"
    display_and_store_config_info "$LAST_INSTALL_MODE"
}

uninstall_singbox() {
    warn "你确定要卸载 Sing-box 吗?"
    read -rp "此操作将停止并禁用服务，删除可执行文件和相关配置文件目录。是否继续卸载? (y/N): " confirm_uninstall
    if [[ ! "$confirm_uninstall" =~ ^[Yy]$ ]]; then
        info "卸载已取消。"
        return
    fi

    info "正在停止 sing-box 服务..."
    svc_stop &>/dev/null || true
    info "正在禁用 sing-box 服务..."
    svc_disable &>/dev/null || true

    if [ -f "$SINGBOX_SERVICE_FILE" ]; then
        info "正在删除 systemd 服务文件: ${SINGBOX_SERVICE_FILE}"
        rm -f "$SINGBOX_SERVICE_FILE"
        svc_daemon_reload
    fi

    local singbox_exe_to_remove=""
    if [ -n "$SINGBOX_CMD" ] && [ -f "$SINGBOX_CMD" ]; then
        singbox_exe_to_remove="$SINGBOX_CMD"
    elif [ -f "$SINGBOX_INSTALL_PATH_EXPECTED" ]; then
        singbox_exe_to_remove="$SINGBOX_INSTALL_PATH_EXPECTED"
    fi

    local official_install_path="/usr/local/bin/sing-box"
    if [ -f "$official_install_path" ]; then
        if [ -n "$singbox_exe_to_remove" ] && [ "$singbox_exe_to_remove" != "$official_install_path" ]; then
            info "正在删除 sing-box 执行文件: $official_install_path (官方脚本位置)"
            rm -f "$official_install_path"
        elif [ -z "$singbox_exe_to_remove" ]; then
             singbox_exe_to_remove="$official_install_path"
        fi
    fi

    if [ -n "$singbox_exe_to_remove" ] && [ -f "$singbox_exe_to_remove" ]; then
        info "正在删除 sing-box 执行文件: $singbox_exe_to_remove"
        rm -f "$singbox_exe_to_remove"
    else
        warn "未找到明确的 sing-box 执行文件进行删除 (已检查 ${SINGBOX_INSTALL_PATH_EXPECTED} 和 ${official_install_path})。"
    fi

    read -rp "是否删除配置文件目录 ${SINGBOX_CONFIG_DIR} (包含导入信息缓存)? (y/N): " delete_config_dir_confirm
    if [[ "$delete_config_dir_confirm" =~ ^[Yy]$ ]]; then
        if [ -d "$SINGBOX_CONFIG_DIR" ]; then
            info "正在删除配置目录 (包括 ${PERSISTENT_INFO_FILE})..."
            rm -rf "$SINGBOX_CONFIG_DIR"
        fi
    else
        info "配置文件目录 (${SINGBOX_CONFIG_DIR}) 已保留。"
    fi

    read -rp "是否删除 Hysteria2 证书目录 ${HYSTERIA_CERT_DIR}? (y/N): " delete_cert_dir_confirm
    if [[ "$delete_cert_dir_confirm" =~ ^[Yy]$ ]]; then
        if [ -d "$HYSTERIA_CERT_DIR" ]; then
            info "正在删除 Hysteria2 证书目录..."
            rm -rf "$HYSTERIA_CERT_DIR"
        fi
    else
        info "Hysteria2 证书目录 (${HYSTERIA_CERT_DIR}) 已保留。"
    fi

    read -rp "是否删除 VLESS+TLS 证书目录 ${VLESS_TLS_CERT_DIR}? (y/N): " delete_vtls_cert_confirm
    if [[ "$delete_vtls_cert_confirm" =~ ^[Yy]$ ]]; then
        if [ -d "$VLESS_TLS_CERT_DIR" ]; then
            info "正在删除 VLESS+TLS 证书目录..."
            rm -rf "$VLESS_TLS_CERT_DIR"
        fi
    else
        info "VLESS+TLS 证书目录 (${VLESS_TLS_CERT_DIR}) 已保留。"
    fi

    read -rp "是否删除脚本快捷命令 (sb) 与脚本文件 (/usr/local/bin/install.sh)? (y/N): " delete_script_confirm
    if [[ "$delete_script_confirm" =~ ^[Yy]$ ]]; then
        rm -f /usr/local/bin/sb /usr/local/bin/install.sh
        info "已删除 sb 快捷命令与 install.sh 脚本文件。"
    else
        info "sb 快捷命令与 install.sh 脚本文件已保留。"
    fi

    success "Sing-box 卸载完成。"
    LAST_INSTALL_MODE=""
    SINGBOX_CMD=""
}

delete_node() {
    echo "================================================"
    echo "当前所有节点："
    local any=false p
    for p in "${!NODE_HY2_PASSWORD[@]}"; do
        echo "  hy2      端口 $p"
        any=true
    done
    for p in "${!NODE_REALITY_UUID[@]}"; do
        echo "  reality  端口 $p"
        any=true
    done
    for p in "${!NODE_VLESS_TLS_UUID[@]}"; do
        echo "  vless-tls 端口 $p (${NODE_VLESS_TLS_TYPE[$p]:-})"
        any=true
    done
    $any || { warn "当前没有任何节点。"; return; }
    echo "================================================"
    local del_port
    read -rp "请输入要删除的端口号（直接回车取消）: " del_port
    [ -z "$del_port" ] && { info "已取消。"; return; }

    local found=false
    if [ -n "${NODE_HY2_PASSWORD[$del_port]:-}" ]; then
        unset 'NODE_HY2_PASSWORD[$del_port]' 'NODE_HY2_OBFS[$del_port]' 'NODE_HY2_SNI[$del_port]'
        found=true
        info "已移除 hy2 端口 $del_port"
    fi
    if [ -n "${NODE_REALITY_UUID[$del_port]:-}" ]; then
        unset 'NODE_REALITY_UUID[$del_port]' 'NODE_REALITY_PUBLIC_KEY[$del_port]' \
              'NODE_REALITY_SNI[$del_port]' 'NODE_REALITY_SHORT_ID[$del_port]' 'NODE_REALITY_FP[$del_port]'
        found=true
        info "已移除 reality 端口 $del_port"
    fi
    if [ -n "${NODE_VLESS_TLS_UUID[$del_port]:-}" ]; then
        unset 'NODE_VLESS_TLS_UUID[$del_port]' 'NODE_VLESS_TLS_TYPE[$del_port]' \
              'NODE_VLESS_TLS_SNI[$del_port]' 'NODE_VLESS_TLS_PATH[$del_port]' \
              'NODE_VLESS_TLS_SVC[$del_port]' 'NODE_VLESS_TLS_RELAY[$del_port]'
        found=true
        info "已移除 vless-tls 端口 $del_port"
    fi
    if ! $found; then
        error "未找到端口 $del_port 的节点。"
        return
    fi

    if [ -f "$SINGBOX_CONFIG_FILE" ]; then
        jq --arg ht "hy2-in-${del_port}" --arg vt "vless-in-${del_port}" --arg vtt "vless-tls-in-${del_port}" \
           '.inbounds |= map(select(.tag != $ht and .tag != $vt and .tag != $vtt))' \
           "$SINGBOX_CONFIG_FILE" > "$SINGBOX_CONFIG_FILE.tmp" \
           && mv "$SINGBOX_CONFIG_FILE.tmp" "$SINGBOX_CONFIG_FILE"
        chmod 600 "$SINGBOX_CONFIG_FILE"
    fi

    if $SINGBOX_CMD check -c "$SINGBOX_CONFIG_FILE"; then
        svc_restart
        sleep 1
        svc_is_active && success "节点已删除，服务已重启。" || error "服务重启失败。"
    else
        error "配置文件校验失败，请检查。"
        return
    fi

    save_persistent_info
}

uninstall_all() {
    warn "!!! 一键全部卸载 !!!"
    warn "将删除以下内容:"
    warn "  - sing-box 服务、二进制"
    warn "  - 配置目录 ${SINGBOX_CONFIG_DIR}"
    warn "  - 证书目录 ${HYSTERIA_CERT_DIR}"
    warn "  - sb 快捷命令与 install.sh"
    warn "  - 持久化信息"
    read -rp "输入大写 YES 确认全部删除: " confirm_all
    if [ "$confirm_all" != "YES" ]; then
        info "已取消全部卸载。"
        return
    fi

    info "停止并禁用 sing-box 服务..."
    svc_stop &>/dev/null || true
    svc_disable &>/dev/null || true

    if [ -f "$SINGBOX_SERVICE_FILE" ]; then
        rm -f "$SINGBOX_SERVICE_FILE"
    fi
    # 同时删除官方 install.sh 留下的 drop-in，避免下次装时 203/EXEC
    if [ -d "/etc/systemd/system/sing-box.service.d" ]; then
        rm -f /etc/systemd/system/sing-box.service.d/*.conf
        rmdir /etc/systemd/system/sing-box.service.d 2>/dev/null || true
    fi
    svc_daemon_reload

    rm -f "$SINGBOX_INSTALL_PATH_EXPECTED" /usr/local/bin/sing-box 2>/dev/null || true
    if [ -n "$SINGBOX_CMD" ] && [ -f "$SINGBOX_CMD" ]; then
        rm -f "$SINGBOX_CMD"
    fi

    info "删除配置目录..."
    rm -rf "$SINGBOX_CONFIG_DIR"

    info "删除证书目录..."
    rm -rf "$HYSTERIA_CERT_DIR"
    rm -rf "$VLESS_TLS_CERT_DIR"

    info "删除 sb 快捷命令与 install.sh..."
    rm -f /usr/local/bin/sb /usr/local/bin/install.sh

    success "全部卸载完成。脚本即将退出。"
    sleep 1
    exit 0
}

# --- 节点信息子菜单 ---
show_all_node_links() {
    if [ ${#NODE_HY2_PASSWORD[@]} -eq 0 ] && [ ${#NODE_REALITY_UUID[@]} -eq 0 ]; then
        warn "当前没有任何节点信息。请先安装节点。"
        return
    fi
    echo "================================================"
    echo -e "${CYAN}${BOLD} 所有节点链接（可直接复制）：${NC}"
    echo "================================================"
    local p h4 h6 l4 l6
    for p in "${!NODE_HY2_PASSWORD[@]}"; do
        local pass="${NODE_HY2_PASSWORD[$p]}"
        local obfs="${NODE_HY2_OBFS[$p]:-}"
        local sni="${NODE_HY2_SNI[$p]:-}"
        echo ""
        echo "[Hysteria2 - 端口 $p]"
        if [ -n "$LAST_SERVER_IP4" ]; then
            h4=$(format_host_for_uri "$LAST_SERVER_IP4")
            l4="hy2://${pass}@${h4}:${p}?sni=${sni}&alpn=h3&insecure=1"
            [ -n "$obfs" ] && l4="${l4}&obfs=salamander&obfs-password=${obfs}"
            echo "IPv4: ${l4}#Hy2-${p}-${LAST_SERVER_IP4}"
        fi
        if [ -n "$LAST_SERVER_IP6" ]; then
            h6=$(format_host_for_uri "$LAST_SERVER_IP6")
            l6="hy2://${pass}@${h6}:${p}?sni=${sni}&alpn=h3&insecure=1"
            [ -n "$obfs" ] && l6="${l6}&obfs=salamander&obfs-password=${obfs}"
            echo "IPv6: ${l6}#Hy2-${p}-${LAST_SERVER_IP6}"
        fi
    done
    for p in "${!NODE_REALITY_UUID[@]}"; do
        local uuid="${NODE_REALITY_UUID[$p]}"
        local pub="${NODE_REALITY_PUBLIC_KEY[$p]}"
        local sni="${NODE_REALITY_SNI[$p]}"
        local sid="${NODE_REALITY_SHORT_ID[$p]}"
        local fp="${NODE_REALITY_FP[$p]:-chrome}"
        echo ""
        echo "[Reality (VLESS) - 端口 $p]"
        if [ -n "$LAST_SERVER_IP4" ]; then
            h4=$(format_host_for_uri "$LAST_SERVER_IP4")
            echo "IPv4: vless://${uuid}@${h4}:${p}?security=reality&sni=${sni}&fp=${fp}&pbk=${pub}&sid=${sid}&flow=xtls-rprx-vision&type=tcp#Reality-${p}-${LAST_SERVER_IP4}"
        fi
        if [ -n "$LAST_SERVER_IP6" ]; then
            h6=$(format_host_for_uri "$LAST_SERVER_IP6")
            echo "IPv6: vless://${uuid}@${h6}:${p}?security=reality&sni=${sni}&fp=${fp}&pbk=${pub}&sid=${sid}&flow=xtls-rprx-vision&type=tcp#Reality-${p}-${LAST_SERVER_IP6}"
        fi
    done
    for p in "${!NODE_VLESS_TLS_UUID[@]}"; do
        local uuid="${NODE_VLESS_TLS_UUID[$p]}"
        local tp="${NODE_VLESS_TLS_TYPE[$p]:-ws}"
        local sni="${NODE_VLESS_TLS_SNI[$p]}"
        local path="${NODE_VLESS_TLS_PATH[$p]:-}"
        local svc="${NODE_VLESS_TLS_SVC[$p]:-}"
        echo ""
        echo "[VLESS+TLS (${tp}) - 端口 $p]"
        local cdn_domain="${NODE_VLESS_TLS_CDN[$p]:-}"
        local cert_fp
        cert_fp=$(get_vless_tls_cert_fp)
        _build_vtls_link() {
            local addr="$1" lp="$2" s="$3" pin="$4" tag="$5"
            local l="vless://${uuid}@${addr}:${lp}?security=tls&sni=${s}&fp=chrome&type=${tp}"
            [ "$pin" = "1" ] && [ -n "$cert_fp" ] && l="${l}&pinnedPeerCertSha256=${cert_fp}"
            if [[ "$tp" == "ws" || "$tp" == "httpupgrade" ]]; then
                l="${l}&path=${path}&host=${s}"
            elif [[ "$tp" == "grpc" ]]; then
                l="${l}&serviceName=${svc}"
            fi
            echo "${l}#${tag}"
        }
        if [ -n "$cdn_domain" ]; then
            echo "CDN: $(_build_vtls_link "$cdn_domain" "443" "$cdn_domain" "0" "VLESS-TLS-${p}-CDN")"
        fi
        if [ -n "$LAST_SERVER_IP4" ]; then
            h4=$(format_host_for_uri "$LAST_SERVER_IP4")
            echo "IPv4直连: $(_build_vtls_link "$h4" "$p" "$sni" "1" "VLESS-TLS-${p}-IPv4")"
        fi
        if [ -n "$LAST_SERVER_IP6" ]; then
            h6=$(format_host_for_uri "$LAST_SERVER_IP6")
            echo "IPv6直连: $(_build_vtls_link "$h6" "$p" "$sni" "1" "VLESS-TLS-${p}-IPv6")"
        fi
        unset -f _build_vtls_link
    done
    echo "================================================"
}

node_info_menu() {
    while true; do
        clear
        echo "================================================"
        echo -e "${CYAN}${BOLD}          节点信息子菜单${NC}"
        echo "================================================"
        echo "  1. 查看全部节点链接（纯链接，可复制）"
        echo "  2. 查看当前配置文件"
        echo "  3. 显示详细配置信息（含二维码）"
        echo "  0. 返回上级菜单"
        echo "================================================"
        local c
        read -rp "请选择 [0-3]: " c
        case "$c" in
            1) show_all_node_links; read -n 1 -s -r -p "按任意键继续..." ;;
            2) manage_singbox "view_config"; read -n 1 -s -r -p "按任意键继续..." ;;
            3) LAST_INSTALL_MODE="all"; display_and_store_config_info "all" ;;
            0) return ;;
            *) warn "无效选项，请重新输入。" ;;
        esac
    done
}

# ==================== 中转管理（按端口绑定） ====================
# 支持: socks5 / hysteria2 / vless(含reality) / vmess
# 存储: ${RELAY_FILE}
#   RELAY|<tag>|<desc>|<base64(json)>
#   BIND|<hy2|reality>|<port>|<relay_tag>

relay_gen_tag() { echo "$1-$(openssl rand -hex 4)"; }
relay_json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

relay_parse_server_port() {
    local input="$1"
    input="${input%%/*}"; input="${input%%#*}"
    if [[ "$input" =~ ^\[([^\]]+)\]:([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"; echo "${BASH_REMATCH[2]}"
    else
        echo "${input%:*}"; echo "${input##*:}"
    fi
}

save_relays_to_file() {
    mkdir -p "$(dirname "$RELAY_FILE")"
    local tmp
    tmp=$(mktemp "${RELAY_FILE}.XXXXXX.tmp" 2>/dev/null) || return 1
    {
        echo "# Sing-box 中转配置（按端口绑定）"
        echo "# RELAY|<tag>|<desc>|<base64(json)>"
        echo "# BIND|<hy2|reality>|<port>|<relay_tag>"
        local t p
        for t in "${!RELAY_JSON[@]}"; do
            local b64
            b64=$(printf '%s' "${RELAY_JSON[$t]}" | base64 | tr -d '\n')
            local d="${RELAY_DESC[$t]:-}"; d="${d//|/｜}"
            echo "RELAY|${t}|${d}|${b64}"
        done
        for p in "${!NODE_HY2_RELAY[@]}"; do
            [ -z "${NODE_HY2_PASSWORD[$p]:-}" ] && continue
            echo "BIND|hy2|${p}|${NODE_HY2_RELAY[$p]}"
        done
        for p in "${!NODE_REALITY_RELAY[@]}"; do
            [ -z "${NODE_REALITY_UUID[$p]:-}" ] && continue
            echo "BIND|reality|${p}|${NODE_REALITY_RELAY[$p]}"
        done
        for p in "${!NODE_VLESS_TLS_RELAY[@]}"; do
            [ -z "${NODE_VLESS_TLS_UUID[$p]:-}" ] && continue
            echo "BIND|vless-tls|${p}|${NODE_VLESS_TLS_RELAY[$p]}"
        done
        local _r
        for _r in "${DOMAIN_ROUTES[@]}"; do
            echo "ROUTE|${_r}"
        done
    } > "$tmp"
    if [[ -s "$tmp" ]] && mv -f "$tmp" "$RELAY_FILE"; then
        chmod 600 "$RELAY_FILE" 2>/dev/null
        return 0
    fi
    rm -f "$tmp"; return 1
}

load_relays_from_file() {
    RELAY_JSON=(); RELAY_DESC=()
    NODE_HY2_RELAY=(); NODE_REALITY_RELAY=(); NODE_VLESS_TLS_RELAY=()
    DOMAIN_ROUTES=()
    [ -f "$RELAY_FILE" ] || return 0
    local kind a b c d e
    while IFS='|' read -r kind a b c d e; do
        [[ -z "$kind" || "$kind" == \#* ]] && continue
        case "$kind" in
            RELAY)
                local json
                json=$(printf '%s' "$c" | base64 -d 2>/dev/null)
                [ -z "$json" ] && continue
                echo "$json" | jq . >/dev/null 2>&1 || continue
                RELAY_JSON["$a"]="$json"; RELAY_DESC["$a"]="$b"
                ;;
            BIND)
                case "$a" in
                    hy2) NODE_HY2_RELAY["$b"]="$c" ;;
                    reality) NODE_REALITY_RELAY["$b"]="$c" ;;
                    vless-tls) NODE_VLESS_TLS_RELAY["$b"]="$c" ;;
                esac
                ;;
            ROUTE)
                if [ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] && [ -n "$d" ]; then
                    DOMAIN_ROUTES+=("$a|$b|$c|$d")
                fi
                ;;
        esac
    done < "$RELAY_FILE"
    return 0
}

parse_relay_socks5() {
    local link="$1" custom_desc="$2"
    local data="${link#*://}"; data="${data%%#*}"
    local userinfo="" hostport=""
    if [[ "$data" == *"@"* ]]; then
        userinfo="${data%%@*}"; hostport="${data#*@}"
    else
        hostport="$data"
    fi
    hostport="${hostport%%\?*}"
    local sp server port
    sp=$(relay_parse_server_port "$hostport")
    server=$(echo "$sp" | sed -n 1p); port=$(echo "$sp" | sed -n 2p)
    [[ "$port" =~ ^[0-9]+$ ]] || { error "端口无效: $port"; return 1; }
    local username="" password=""
    if [ -n "$userinfo" ]; then
        username="${userinfo%%:*}"; password="${userinfo#*:}"
    fi
    local tag; tag=$(relay_gen_tag "socks")
    local json
    if [ -n "$username" ]; then
        json="{\"type\":\"socks\",\"tag\":\"$tag\",\"server\":\"$(relay_json_escape "$server")\",\"server_port\":$port,\"version\":\"5\",\"username\":\"$(relay_json_escape "$username")\",\"password\":\"$(relay_json_escape "$password")\"}"
    else
        json="{\"type\":\"socks\",\"tag\":\"$tag\",\"server\":\"$(relay_json_escape "$server")\",\"server_port\":$port,\"version\":\"5\"}"
    fi
    local desc="${custom_desc:-SOCKS5 ${server}:${port}}"
    RELAY_JSON["$tag"]="$json"; RELAY_DESC["$tag"]="$desc"
    success "已添加 SOCKS5: $desc"
}

parse_relay_hy2() {
    local link="$1" custom_desc="$2"
    local data="${link#*://}"
    local userinfo="${data%%@*}"; local rest="${data#*@}"
    local hostport="${rest%%\?*}"; hostport="${hostport%%#*}"
    local sp server port
    sp=$(relay_parse_server_port "$hostport")
    server=$(echo "$sp" | sed -n 1p); port=$(echo "$sp" | sed -n 2p)
    [[ "$port" =~ ^[0-9]+$ ]] || { error "端口无效: $port"; return 1; }
    local params=""
    if [[ "$rest" == *"?"* ]]; then params="${rest#*\?}"; params="${params%%#*}"; fi
    local sni="" insecure="false" obfs_type="" obfs_pw=""
    if [ -n "$params" ]; then
        local pair k v
        IFS='&' read -ra _pairs <<< "$params"
        for pair in "${_pairs[@]}"; do
            k="${pair%%=*}"; v="${pair#*=}"
            case "$k" in
                sni) sni="$v" ;;
                insecure) [[ "$v" == "1" || "$v" == "true" ]] && insecure="true" ;;
                obfs) obfs_type="$v" ;;
                obfs-password) obfs_pw="$v" ;;
            esac
        done
    fi
    local tag; tag=$(relay_gen_tag "hy2")
    local tls="{\"enabled\":true,\"server_name\":\"$(relay_json_escape "$sni")\",\"alpn\":[\"h3\"],\"min_version\":\"1.3\",\"insecure\":$insecure}"
    local obfs=""
    if [[ "$obfs_type" == "salamander" && -n "$obfs_pw" ]]; then
        obfs=",\"obfs\":{\"type\":\"salamander\",\"password\":\"$(relay_json_escape "$obfs_pw")\"}"
    fi
    local json="{\"type\":\"hysteria2\",\"tag\":\"$tag\",\"server\":\"$(relay_json_escape "$server")\",\"server_port\":$port,\"password\":\"$(relay_json_escape "$userinfo")\",\"tls\":$tls$obfs}"
    local desc="${custom_desc:-Hysteria2 ${server}:${port}}"
    RELAY_JSON["$tag"]="$json"; RELAY_DESC["$tag"]="$desc"
    success "已添加 Hysteria2: $desc"
}

parse_relay_vless() {
    local link="$1" custom_desc="$2"
    local data="${link#*://}"
    local uuid="${data%%@*}"; local rest="${data#*@}"
    local hostport="${rest%%\?*}"; hostport="${hostport%%#*}"
    local sp server port
    sp=$(relay_parse_server_port "$hostport")
    server=$(echo "$sp" | sed -n 1p); port=$(echo "$sp" | sed -n 2p)
    [[ "$port" =~ ^[0-9]+$ ]] || { error "端口无效: $port"; return 1; }
    local params=""
    if [[ "$rest" == *"?"* ]]; then params="${rest#*\?}"; params="${params%%#*}"; fi
    local security="none" sni="" flow="" pbk="" sid="" fp="chrome" net="tcp" path="" host="" svc=""
    if [ -n "$params" ]; then
        local pair k v
        IFS='&' read -ra _pairs <<< "$params"
        for pair in "${_pairs[@]}"; do
            k="${pair%%=*}"; v="${pair#*=}"
            case "$k" in
                security) security="$v" ;;
                sni) sni="$v" ;;
                flow) flow="$v" ;;
                pbk) pbk="$v" ;;
                sid) sid="$v" ;;
                fp) fp="$v" ;;
                type) net="$v" ;;
                path) path="$v" ;;
                host) host="$v" ;;
                serviceName) svc="$v" ;;
            esac
        done
    fi
    local tag; tag=$(relay_gen_tag "vless")
    local tls
    if [[ "$security" == "reality" ]]; then
        [ -z "$pbk" ] && { error "REALITY 缺少公钥(pbk)"; return 1; }
        tls="\"tls\":{\"enabled\":true,\"server_name\":\"$(relay_json_escape "$sni")\",\"min_version\":\"1.3\",\"utls\":{\"enabled\":true,\"fingerprint\":\"$(relay_json_escape "$fp")\"},\"reality\":{\"enabled\":true,\"public_key\":\"$(relay_json_escape "$pbk")\",\"short_id\":\"$(relay_json_escape "$sid")\"}}"
    elif [[ "$security" == "tls" ]]; then
        tls="\"tls\":{\"enabled\":true,\"server_name\":\"$(relay_json_escape "$sni")\",\"alpn\":[\"h2\",\"http/1.1\"],\"min_version\":\"1.3\",\"utls\":{\"enabled\":true,\"fingerprint\":\"$(relay_json_escape "$fp")\"}}"
    else
        tls="\"tls\":{\"enabled\":false}"
    fi
    local flow_c=""
    [ -n "$flow" ] && flow_c=",\"flow\":\"$(relay_json_escape "$flow")\""
    local transport=""
    if [[ "$security" == "tls" && "$net" != "tcp" ]]; then
        case "$net" in
            ws|httpupgrade)
                local hdr=""
                [ -n "$host" ] && hdr=",\"headers\":{\"Host\":\"$(relay_json_escape "$host")\"}"
                transport=",\"transport\":{\"type\":\"$(relay_json_escape "$net")\",\"path\":\"$(relay_json_escape "${path:-/}")\"$hdr}"
                ;;
            grpc)
                transport=",\"transport\":{\"type\":\"grpc\",\"service_name\":\"$(relay_json_escape "${svc:-grpc}")\"}"
                ;;
        esac
    fi
    local json="{\"type\":\"vless\",\"tag\":\"$tag\",\"server\":\"$(relay_json_escape "$server")\",\"server_port\":$port,\"uuid\":\"$(relay_json_escape "$uuid")\"$flow_c,$tls$transport}"
    local desc
    if [[ "$security" == "reality" ]]; then
        desc="${custom_desc:-VLESS+REALITY ${server}:${port} (SNI: ${sni})}"
    else
        desc="${custom_desc:-VLESS ${server}:${port}}"
    fi
    RELAY_JSON["$tag"]="$json"; RELAY_DESC["$tag"]="$desc"
    success "已添加 VLESS: $desc"
}

parse_relay_vmess() {
    local link="$1" custom_desc="$2"
    local b64="${link#vmess://}"
    local json_in
    json_in=$(printf '%s' "$b64" | base64 -d 2>/dev/null)
    [ -z "$json_in" ] && { error "VMess 解码失败"; return 1; }
    command -v jq &>/dev/null || { error "需要 jq"; return 1; }
    local server port uuid aid security net path host tls_mode sni
    server=$(echo "$json_in" | jq -r '.add // .address // empty')
    port=$(echo "$json_in" | jq -r '.port // empty')
    uuid=$(echo "$json_in" | jq -r '.id // empty')
    aid=$(echo "$json_in" | jq -r '.aid // 0')
    security=$(echo "$json_in" | jq -r '.scy // "auto"')
    net=$(echo "$json_in" | jq -r '.net // "tcp"')
    path=$(echo "$json_in" | jq -r '.path // ""')
    host=$(echo "$json_in" | jq -r '.host // ""')
    tls_mode=$(echo "$json_in" | jq -r '.tls // ""')
    sni=$(echo "$json_in" | jq -r '.sni // ""')
    [ -z "$server" ] && { error "VMess 缺少 server"; return 1; }
    [[ "$port" =~ ^[0-9]+$ ]] || { error "VMess 端口无效: $port"; return 1; }
    [[ "$aid" =~ ^[0-9]+$ ]] || aid=0
    local tag; tag=$(relay_gen_tag "vmess")
    local transport=""
    if [[ "$net" == "ws" ]]; then
        local hdr=""
        [ -n "$host" ] && hdr=",\"headers\":{\"Host\":\"$(relay_json_escape "$host")\"}"
        transport=",\"transport\":{\"type\":\"ws\",\"path\":\"$(relay_json_escape "${path:-/}")\"$hdr}"
    elif [[ "$net" == "grpc" ]]; then
        transport=",\"transport\":{\"type\":\"grpc\",\"service_name\":\"$(relay_json_escape "${path:-grpc}")\"}"
    fi
    local tls_c=""
    if [[ "$tls_mode" == "tls" ]]; then
        local sn="$sni"
        [ -z "$sn" ] && [ -n "$host" ] && sn="$host"
        tls_c=",\"tls\":{\"enabled\":true,\"server_name\":\"$(relay_json_escape "$sn")\",\"min_version\":\"1.3\"}"
    fi
    local json="{\"type\":\"vmess\",\"tag\":\"$tag\",\"server\":\"$(relay_json_escape "$server")\",\"server_port\":$port,\"uuid\":\"$(relay_json_escape "$uuid")\",\"alter_id\":$aid,\"security\":\"$(relay_json_escape "$security")\"$transport$tls_c}"
    local desc="${custom_desc:-VMess ${server}:${port}}"
    RELAY_JSON["$tag"]="$json"; RELAY_DESC["$tag"]="$desc"
    success "已添加 VMess: $desc"
}

add_relay_from_link() {
    local link="$1" desc="$2"
    if [[ "$link" =~ ^socks ]]; then
        parse_relay_socks5 "$link" "$desc"
    elif [[ "$link" =~ ^(hy2|hysteria2):// ]]; then
        parse_relay_hy2 "$link" "$desc"
    elif [[ "$link" =~ ^vless:// ]]; then
        parse_relay_vless "$link" "$desc"
    elif [[ "$link" =~ ^vmess:// ]]; then
        parse_relay_vmess "$link" "$desc"
    else
        error "仅支持: socks5:// hy2:// vless:// vmess://"
        return 1
    fi
}

rebuild_route_and_outbounds() {
    [ -f "$SINGBOX_CONFIG_FILE" ] || { warn "配置文件不存在，请先安装节点"; return 1; }
    [ -n "$SINGBOX_CMD" ] || { error "SINGBOX_CMD 未设置"; return 1; }
    local _direct_ob
    case "${OUTBOUND_MODE:-both}" in
        v4) _direct_ob='{"type":"direct","tag":"direct","domain_resolver":{"server":"local","strategy":"ipv4_only"}}' ;;
        v6) _direct_ob='{"type":"direct","tag":"direct","domain_resolver":{"server":"local","strategy":"ipv6_only"}}' ;;
        *)  _direct_ob='{"type":"direct","tag":"direct"}' ;;
    esac
    local ob="[${_direct_ob},{\"type\":\"block\",\"tag\":\"block\"}]"
    local t p rt tag
    for t in "${!RELAY_JSON[@]}"; do
        ob=$(jq --argjson o "${RELAY_JSON[$t]}" '. + [$o]' <<< "$ob")
    done
    local rules
    rules=$(_relay_build_rules_json "")
    jq --argjson ob "$ob" --argjson rules "$rules" '
        walk(if type == "object" then del(.domain_strategy) else . end)
        | .dns = {servers: [{type: "local", tag: "local"}]}
        | .outbounds = $ob
        | .route = {rules: $rules, final: "direct"}
    ' "$SINGBOX_CONFIG_FILE" > "${SINGBOX_CONFIG_FILE}.tmp" \
       && mv "${SINGBOX_CONFIG_FILE}.tmp" "$SINGBOX_CONFIG_FILE"
    chmod 600 "$SINGBOX_CONFIG_FILE"
    if $SINGBOX_CMD check -c "$SINGBOX_CONFIG_FILE" >/dev/null 2>&1; then
        svc_restart
        sleep 1
        if svc_is_active; then
            success "配置已更新，服务已重启"
        else
            error "服务重启失败，查看: svc_log_tail 50"
            return 1
        fi
    else
        error "配置校验失败: $SINGBOX_CONFIG_FILE"
        return 1
    fi
}

relay_list_nodes_status() {
    local p rt desc any=false
    for p in "${!NODE_HY2_PASSWORD[@]}"; do
        desc="直连"; rt="${NODE_HY2_RELAY[$p]:-}"
        [ -n "$rt" ] && [ "$rt" != "direct" ] && desc="中转: ${RELAY_DESC[$rt]:-$rt}"
        echo "  hy2      端口 $p → $desc"; any=true
    done
    for p in "${!NODE_REALITY_UUID[@]}"; do
        desc="直连"; rt="${NODE_REALITY_RELAY[$p]:-}"
        [ -n "$rt" ] && [ "$rt" != "direct" ] && desc="中转: ${RELAY_DESC[$rt]:-$rt}"
        echo "  reality  端口 $p → $desc"; any=true
    done
    for p in "${!NODE_VLESS_TLS_UUID[@]}"; do
        desc="直连"; rt="${NODE_VLESS_TLS_RELAY[$p]:-}"
        [ -n "$rt" ] && [ "$rt" != "direct" ] && desc="中转: ${RELAY_DESC[$rt]:-$rt}"
        echo "  vless-tls 端口 $p → $desc"; any=true
    done
    $any || echo "  （无节点）"
}

_relay_add_ui() {
    echo ""
    echo "支持格式:"
    echo "  socks5://user:pass@host:port"
    echo "  socks5://host:port"
    echo "  hy2://pass@host:port?sni=...&insecure=1&obfs=salamander&obfs-password=..."
    echo "  vless://uuid@host:port?security=reality&sni=...&pbk=...&sid=...&flow=xtls-rprx-vision"
    echo "  vless://uuid@host:port?security=tls&sni=...&type=tcp|ws|grpc"
    echo "  vmess://base64(json)"
    echo ""
    local link desc
    read -rp "粘贴中转链接: " link
    [ -z "$link" ] && { info "已取消"; return; }
    read -rp "描述（可留空自动生成）: " desc
    if add_relay_from_link "$link" "$desc"; then
        save_relays_to_file
        rebuild_route_and_outbounds || true
    fi
    read -n 1 -s -r -p "按任意键继续..."
}

_relay_bind_ui() {
    if [ ${#RELAY_JSON[@]} -eq 0 ]; then
        warn "请先添加中转"; read -n 1 -s -r -p "按任意键继续..."; return
    fi
    local -a ports=() types=()
    local i=1 p
    echo ""
    echo "选择要绑定的节点:"
    for p in "${!NODE_HY2_PASSWORD[@]}"; do
        echo "  [$i] hy2 端口 $p"
        ports+=("$p"); types+=("hy2"); i=$((i+1))
    done
    for p in "${!NODE_REALITY_UUID[@]}"; do
        echo "  [$i] reality 端口 $p"
        ports+=("$p"); types+=("reality"); i=$((i+1))
    done
    for p in "${!NODE_VLESS_TLS_UUID[@]}"; do
        echo "  [$i] vless-tls 端口 $p"
        ports+=("$p"); types+=("vless-tls"); i=$((i+1))
    done
    if [ ${#ports[@]} -eq 0 ]; then
        warn "没有节点"; read -n 1 -s -r -p "按任意键继续..."; return
    fi
    local idx
    read -rp "节点序号: " idx
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || (( idx < 1 || idx > ${#ports[@]} )); then
        error "无效序号"; read -n 1 -s -r -p "按任意键继续..."; return
    fi
    local sel_port="${ports[$((idx-1))]}" sel_type="${types[$((idx-1))]}"
    local -a tags=(); local j=1
    echo ""; echo "可用中转:"
    for t in "${!RELAY_JSON[@]}"; do
        echo "  [$j] ${RELAY_DESC[$t]}"
        tags+=("$t"); j=$((j+1))
    done
    local ri
    read -rp "中转序号: " ri
    if ! [[ "$ri" =~ ^[0-9]+$ ]] || (( ri < 1 || ri > ${#tags[@]} )); then
        error "无效序号"; read -n 1 -s -r -p "按任意键继续..."; return
    fi
    local sel_tag="${tags[$((ri-1))]}"
    if [ "$sel_type" == "hy2" ]; then
        NODE_HY2_RELAY["$sel_port"]="$sel_tag"
    elif [ "$sel_type" == "reality" ]; then
        NODE_REALITY_RELAY["$sel_port"]="$sel_tag"
    elif [ "$sel_type" == "vless-tls" ]; then
        NODE_VLESS_TLS_RELAY["$sel_port"]="$sel_tag"
    fi
    success "已绑定: $sel_type 端口 $sel_port → ${RELAY_DESC[$sel_tag]}"
    save_relays_to_file
    rebuild_route_and_outbounds || true
    read -n 1 -s -r -p "按任意键继续..."
}

_relay_unbind_ui() {
    echo ""
    relay_list_nodes_status
    local up
    read -rp "输入要取消中转的端口号（回车取消）: " up
    [ -z "$up" ] && { info "已取消"; return; }
    local found=0
    if [ -n "${NODE_HY2_RELAY[$up]:-}" ]; then unset "NODE_HY2_RELAY[$up]"; found=1; fi
    if [ -n "${NODE_REALITY_RELAY[$up]:-}" ]; then unset "NODE_REALITY_RELAY[$up]"; found=1; fi
    if [ -n "${NODE_VLESS_TLS_RELAY[$up]:-}" ]; then unset "NODE_VLESS_TLS_RELAY[$up]"; found=1; fi
    if [ $found -eq 0 ]; then
        warn "该端口没有中转"; read -n 1 -s -r -p "按任意键继续..."; return
    fi
    success "已取消端口 $up 的中转"
    save_relays_to_file
    rebuild_route_and_outbounds || true
    read -n 1 -s -r -p "按任意键继续..."
}

_relay_delete_ui() {
    if [ ${#RELAY_JSON[@]} -eq 0 ]; then
        warn "没有中转"; read -n 1 -s -r -p "按任意键继续..."; return
    fi
    local -a tags=(); local j=1
    echo ""
    for t in "${!RELAY_JSON[@]}"; do
        echo "  [$j] ${RELAY_DESC[$t]} (tag: $t)"
        tags+=("$t"); j=$((j+1))
    done
    local di
    read -rp "要删除的中转序号: " di
    if ! [[ "$di" =~ ^[0-9]+$ ]] || (( di < 1 || di > ${#tags[@]} )); then
        error "无效序号"; read -n 1 -s -r -p "按任意键继续..."; return
    fi
    local dt="${tags[$((di-1))]}"
    local yn
    read -rp "确认删除 ${RELAY_DESC[$dt]}? (y/N): " yn
    [[ "$yn" =~ ^[Yy]$ ]] || { info "已取消"; return; }
    unset "RELAY_JSON[$dt]"; unset "RELAY_DESC[$dt]"
    local p
    for p in "${!NODE_HY2_RELAY[@]}"; do
        [ "${NODE_HY2_RELAY[$p]}" == "$dt" ] && unset "NODE_HY2_RELAY[$p]"
    done
    for p in "${!NODE_REALITY_RELAY[@]}"; do
        [ "${NODE_REALITY_RELAY[$p]}" == "$dt" ] && unset "NODE_REALITY_RELAY[$p]"
    done
    for p in "${!NODE_VLESS_TLS_RELAY[@]}"; do
        [ "${NODE_VLESS_TLS_RELAY[$p]}" == "$dt" ] && unset "NODE_VLESS_TLS_RELAY[$p]"
    done
    # 清除该中转的域名分流规则
    local -a _new_dr=()
    local _r _inb _m _v _rt2
    for _r in "${DOMAIN_ROUTES[@]}"; do
        IFS='|' read -r _inb _m _v _rt2 <<< "$_r"
        if [ "$_rt2" != "$dt" ]; then
            _new_dr+=("$_r")
        fi
    done
    DOMAIN_ROUTES=("${_new_dr[@]}")
    success "已删除中转 $dt"
    save_relays_to_file
    rebuild_route_and_outbounds || true
    read -n 1 -s -r -p "按任意键继续..."
}

# ==================== 域名分流规则 ====================
_relay_build_rules_json() {
    local existing="${1:-}"
    local rules='[]'
    local _rt _tag _p _m _v _inb _it _r

    _relay_check_inb() {
        local t="$1"
        if [ -n "$existing" ]; then
            jq -e --arg tag "$t" '.[] | select(.tag == $tag)' <<< "$existing" >/dev/null 2>&1
        else
            jq -e --arg tag "$t" '.inbounds[] | select(.tag == $tag)' "$SINGBOX_CONFIG_FILE" >/dev/null 2>&1
        fi
    }

    # 域名规则在前（更具体）
    for _r in "${DOMAIN_ROUTES[@]}"; do
        IFS='|' read -r _inb _m _v _rt <<< "$_r"
        if [ -z "$_inb" ] || [ -z "$_m" ] || [ -z "$_v" ] || [ -z "$_rt" ]; then continue; fi
        if [ -z "${RELAY_JSON[$_rt]:-}" ]; then continue; fi
        local -a _inbounds=()
        if [ "$_inb" == "all" ]; then
            for _p in "${!NODE_HY2_PASSWORD[@]}"; do _inbounds+=("hy2-in-${_p}"); done
            for _p in "${!NODE_REALITY_UUID[@]}"; do _inbounds+=("vless-in-${_p}"); done
            for _p in "${!NODE_VLESS_TLS_UUID[@]}"; do _inbounds+=("vless-tls-in-${_p}"); done
        else
            _inbounds=("$_inb")
        fi
        for _it in "${_inbounds[@]}"; do
            _relay_check_inb "$_it" || continue
            case "$_m" in
                domain) rules=$(jq --arg inb "$_it" --arg v "$_v" --arg out "$_rt" '. + [{inbound: [$inb], domain: [$v], outbound: $out}]' <<< "$rules") ;;
                domain_suffix) rules=$(jq --arg inb "$_it" --arg v "$_v" --arg out "$_rt" '. + [{inbound: [$inb], domain_suffix: [$v], outbound: $out}]' <<< "$rules") ;;
                domain_keyword) rules=$(jq --arg inb "$_it" --arg v "$_v" --arg out "$_rt" '. + [{inbound: [$inb], domain_keyword: [$v], outbound: $out}]' <<< "$rules") ;;
                ip_cidr) rules=$(jq --arg inb "$_it" --arg v "$_v" --arg out "$_rt" '. + [{inbound: [$inb], ip_cidr: [$v], outbound: $out}]' <<< "$rules") ;;
            esac
        done
    done

    # 端口级规则在后（更宽泛）
    for _p in "${!NODE_HY2_RELAY[@]}"; do
        _rt="${NODE_HY2_RELAY[$_p]}"
        if [ -z "$_rt" ] || [ "$_rt" == "direct" ]; then continue; fi
        if [ -z "${RELAY_JSON[$_rt]:-}" ]; then continue; fi
        _tag="hy2-in-${_p}"
        _relay_check_inb "$_tag" || continue
        rules=$(jq --arg inb "$_tag" --arg out "$_rt" '. + [{inbound: [$inb], outbound: $out}]' <<< "$rules")
    done
    for _p in "${!NODE_REALITY_RELAY[@]}"; do
        _rt="${NODE_REALITY_RELAY[$_p]}"
        if [ -z "$_rt" ] || [ "$_rt" == "direct" ]; then continue; fi
        if [ -z "${RELAY_JSON[$_rt]:-}" ]; then continue; fi
        _tag="vless-in-${_p}"
        _relay_check_inb "$_tag" || continue
        rules=$(jq --arg inb "$_tag" --arg out "$_rt" '. + [{inbound: [$inb], outbound: $out}]' <<< "$rules")
    done
    for _p in "${!NODE_VLESS_TLS_RELAY[@]}"; do
        _rt="${NODE_VLESS_TLS_RELAY[$_p]}"
        if [ -z "$_rt" ] || [ "$_rt" == "direct" ]; then continue; fi
        if [ -z "${RELAY_JSON[$_rt]:-}" ]; then continue; fi
        _tag="vless-tls-in-${_p}"
        _relay_check_inb "$_tag" || continue
        rules=$(jq --arg inb "$_tag" --arg out "$_rt" '. + [{inbound: [$inb], outbound: $out}]' <<< "$rules")
    done

    unset -f _relay_check_inb
    echo "$rules"
}

domain_route_menu() {
    while true; do
        clear
        echo "================================================"
        echo -e "${CYAN}${BOLD}          域名分流规则配置${NC}"
        echo "================================================"
        if [ ${#DOMAIN_ROUTES[@]} -eq 0 ]; then
            echo "  （暂无规则）"
        else
            local i=1 _r _inb _m _v _rt _indesc
            for _r in "${DOMAIN_ROUTES[@]}"; do
                IFS='|' read -r _inb _m _v _rt <<< "$_r"
                if [ "$_inb" == "all" ]; then _indesc="全部节点"; else _indesc="$_inb"; fi
                echo "  [$i] ${_indesc}  →  ${_m}: ${_v}  →  ${RELAY_DESC[$_rt]:-$_rt}"
                i=$((i+1))
            done
        fi
        echo "------------------------------------------------"
        echo "  1. 添加规则"
        echo "  2. 删除规则"
        echo "  3. 清空所有规则"
        echo "  0. 返回"
        echo "================================================"
        local c
        read -rp "请选择 [0-3]: " c
        case "$c" in
            1) _domain_route_add_ui ;;
            2) _domain_route_del_ui ;;
            3) _domain_route_clear_ui ;;
            0) return ;;
            *) warn "无效选项"; sleep 1 ;;
        esac
    done
}

_domain_route_add_ui() {
    if [ ${#RELAY_JSON[@]} -eq 0 ]; then
        warn "请先添加中转"; read -n 1 -s -r -p "按任意键继续..."; return
    fi
    local -a inb_list=() inb_show=()
    local p i=1
    inb_list+=("all"); inb_show+=("全部节点 (所有 inbound)")
    for p in "${!NODE_HY2_PASSWORD[@]}"; do
        inb_list+=("hy2-in-${p}"); inb_show+=("hy2 端口 $p"); i=$((i+1))
    done
    for p in "${!NODE_REALITY_UUID[@]}"; do
        inb_list+=("vless-in-${p}"); inb_show+=("reality 端口 $p"); i=$((i+1))
    done
    for p in "${!NODE_VLESS_TLS_UUID[@]}"; do
        inb_list+=("vless-tls-in-${p}"); inb_show+=("vless-tls 端口 $p"); i=$((i+1))
    done
    echo ""
    echo "选择应用的节点:"
    local j=1 s
    for s in "${inb_show[@]}"; do
        echo "  [$j] $s"; j=$((j+1))
    done
    local idx
    read -rp "节点序号: " idx
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || (( idx < 1 || idx > ${#inb_list[@]} )); then
        error "无效序号"; read -n 1 -s -r -p "按任意键继续..."; return
    fi
    local sel_inb="${inb_list[$((idx-1))]}"

    echo ""
    echo "匹配类型:"
    echo "  [1] domain_suffix  域名后缀 (如 google.com 匹配 *.google.com)"
    echo "  [2] domain         完整域名 (精确匹配)"
    echo "  [3] domain_keyword 关键词匹配"
    echo "  [4] ip_cidr        IP/CIDR (如 8.8.8.8/32)"
    local mt
    read -rp "选择 [1-4]: " mt
    local m
    case "$mt" in
        1) m="domain_suffix" ;;
        2) m="domain" ;;
        3) m="domain_keyword" ;;
        4) m="ip_cidr" ;;
        *) error "无效选项"; read -n 1 -s -r -p "按任意键继续..."; return ;;
    esac

    local val
    read -rp "输入匹配值: " val
    if [ -z "$val" ]; then info "已取消"; return; fi
    if [[ "$val" == *"|"* ]]; then
        error "值不能包含 | 字符"; read -n 1 -s -r -p "按任意键继续..."; return
    fi

    local -a tags=(); local k=1
    echo ""; echo "选择目标中转:"
    local t
    for t in "${!RELAY_JSON[@]}"; do
        echo "  [$k] ${RELAY_DESC[$t]}"
        tags+=("$t"); k=$((k+1))
    done
    local ri
    read -rp "中转序号: " ri
    if ! [[ "$ri" =~ ^[0-9]+$ ]] || (( ri < 1 || ri > ${#tags[@]} )); then
        error "无效序号"; read -n 1 -s -r -p "按任意键继续..."; return
    fi
    local sel_tag="${tags[$((ri-1))]}"

    DOMAIN_ROUTES+=("${sel_inb}|${m}|${val}|${sel_tag}")
    success "已添加: ${sel_inb} → ${m}:${val} → ${RELAY_DESC[$sel_tag]}"
    save_relays_to_file
    rebuild_route_and_outbounds || true
    read -n 1 -s -r -p "按任意键继续..."
}

_domain_route_del_ui() {
    if [ ${#DOMAIN_ROUTES[@]} -eq 0 ]; then
        warn "暂无规则"; read -n 1 -s -r -p "按任意键继续..."; return
    fi
    local di
    read -rp "要删除的规则序号: " di
    if ! [[ "$di" =~ ^[0-9]+$ ]] || (( di < 1 || di > ${#DOMAIN_ROUTES[@]} )); then
        error "无效序号"; read -n 1 -s -r -p "按任意键继续..."; return
    fi
    local -a new=()
    local i=1 r
    for r in "${DOMAIN_ROUTES[@]}"; do
        if [ "$i" -ne "$di" ]; then new+=("$r"); fi
        i=$((i+1))
    done
    DOMAIN_ROUTES=("${new[@]}")
    success "已删除规则 #$di"
    save_relays_to_file
    rebuild_route_and_outbounds || true
    read -n 1 -s -r -p "按任意键继续..."
}

_domain_route_clear_ui() {
    if [ ${#DOMAIN_ROUTES[@]} -eq 0 ]; then
        warn "暂无规则"; read -n 1 -s -r -p "按任意键继续..."; return
    fi
    local yn
    read -rp "确认清空所有域名分流规则? (y/N): " yn
    if [[ ! "$yn" =~ ^[Yy]$ ]]; then info "已取消"; return; fi
    DOMAIN_ROUTES=()
    success "已清空所有规则"
    save_relays_to_file
    rebuild_route_and_outbounds || true
    read -n 1 -s -r -p "按任意键继续..."
}


# ==================== 入站/出站 IP 模式 ====================
_io_mode_label() {
    case "$1" in
        v4) echo "仅 IPv4" ;;
        v6) echo "仅 IPv6" ;;
        *)  echo "双栈 (v4+v6)" ;;
    esac
}

apply_outbound_mode() {
    [ -f "$SINGBOX_CONFIG_FILE" ] || { warn "配置文件不存在，请先安装节点"; return 1; }
    [ -n "$SINGBOX_CMD" ] || { error "SINGBOX_CMD 未设置"; return 1; }
    local new_direct
    case "${OUTBOUND_MODE:-both}" in
        v4) new_direct='{"type":"direct","tag":"direct","domain_resolver":{"server":"local","strategy":"ipv4_only"}}' ;;
        v6) new_direct='{"type":"direct","tag":"direct","domain_resolver":{"server":"local","strategy":"ipv6_only"}}' ;;
        *)  new_direct='{"type":"direct","tag":"direct"}' ;;
    esac
    local tmp
    tmp=$(mktemp)
    if jq --argjson direct "$new_direct" '
        walk(if type == "object" then del(.domain_strategy) else . end)
        | .dns = ((.dns // {}) | .servers = ((.servers // []) | if any(.tag == "local") then . else . + [{type: "local", tag: "local"}] end))
        | .outbounds = ([$direct] + ((.outbounds // []) | map(select(.tag != "direct"))))
    ' "$SINGBOX_CONFIG_FILE" > "$tmp"; then
        mv "$tmp" "$SINGBOX_CONFIG_FILE"
        chmod 600 "$SINGBOX_CONFIG_FILE"
    else
        rm -f "$tmp"
        error "修改配置失败"
        return 1
    fi
    info "正在校验配置..."
    if $SINGBOX_CMD check -c "$SINGBOX_CONFIG_FILE" >/dev/null 2>&1; then
        svc_restart
        sleep 1
        if svc_is_active; then
            success "已应用: 出站=$(_io_mode_label "$OUTBOUND_MODE")"
            info "direct.domain_resolver.strategy=$(echo "$new_direct" | jq -r '.domain_resolver.strategy // "default"')"
        else
            error "服务重启失败，请查看 svc_log_tail 50"
            return 1
        fi
    else
        error "配置校验失败，请检查 $SINGBOX_CONFIG_FILE"
        return 1
    fi
    save_persistent_info
}

_io_pick_inbound() {
    echo ""
    echo "选择入站模式:"
    echo "  [1] 双栈  (listen \"::\"，bindv6only=0 时同时接受 v4+v6)"
    echo "  [2] 仅 v4 (listen \"0.0.0.0\")"
    echo "  [3] 仅 v6 (listen 具体公网 IPv6，无 v6 时退化为 \"::\")"
    local c
    read -rp "选择 [1-3]: " c
    case "$c" in
        1) echo "both" ;;
        2) echo "v4" ;;
        3) echo "v6" ;;
        *) echo "" ;;
    esac
}

_io_pick_outbound() {
    echo ""
    echo "选择出站模式（仅影响直连流量，不影响中转）:"
    echo "  [1] 双栈 (domain_strategy 不设)"
    echo "  [2] 仅 v4 (ipv4_only)"
    echo "  [3] 仅 v6 (ipv6_only)"
    local c
    read -rp "选择 [1-3]: " c
    case "$c" in
        1) echo "both" ;;
        2) echo "v4" ;;
        3) echo "v6" ;;
        *) echo "" ;;
    esac
}

io_mode_menu() {
    info "正在刷新服务器 IP 检测..."
    get_server_ips || true
    while true; do
        clear
        echo "================================================"
        echo -e "${CYAN}${BOLD}          出站 IP 模式${NC}"
        echo "================================================"
        echo "  当前出站: $(_io_mode_label "$OUTBOUND_MODE")"
        echo "  服务器 IP: v4=${LAST_SERVER_IP4:-无}  v6=${LAST_SERVER_IP6:-无}"
        echo ""
        echo "  说明: 入站固定双栈（listen ::），客户端按需选择 v4 或 v6 链接。"
        echo "        这里只控制 VPS 访问外网时使用的 IP 版本。"
        echo "------------------------------------------------"
        echo "  1. 双栈出站（默认 / 还原，系统自动选择）"
        echo "  2. 仅 IPv4 出站"
        echo "  3. 仅 IPv6 出站"
        echo "  0. 返回"
        echo "================================================"
        local c
        read -rp "请选择 [0-3]: " c
        local new_out=""
        case "$c" in
            1) new_out="both" ;;
            2) new_out="v4" ;;
            3) new_out="v6" ;;
            0) return ;;
            *) warn "无效选项"; sleep 1; continue ;;
        esac
        if [ "$new_out" = "v6" ] && [ -z "${LAST_SERVER_IP6:-}" ]; then
            error "服务器未检测到公网 IPv6，无法启用仅 v6 出站"
            read -n 1 -s -r -p "按任意键继续..."
            continue
        fi
        OUTBOUND_MODE="$new_out"
        echo ""
        info "即将应用: 出站=$(_io_mode_label "$OUTBOUND_MODE")"
        local yn
        read -rp "确认应用并重启 sing-box? (y/N): " yn
        if [[ "$yn" =~ ^[Yy]$ ]]; then
            apply_outbound_mode || warn "应用失败，请检查日志"
        else
            info "已取消"
        fi
        read -n 1 -s -r -p "按任意键继续..."
    done
}

relay_menu() {
    load_relays_from_file
    while true; do
        clear
        echo "================================================"
        echo -e "${CYAN}${BOLD}          中转管理（按端口绑定）${NC}"
        echo "================================================"
        echo "当前中转列表:"
        if [ ${#RELAY_JSON[@]} -eq 0 ]; then
            echo "  （空，请先添加中转）"
        else
            local i=1
            for t in "${!RELAY_JSON[@]}"; do
                echo "  [$i] ${RELAY_DESC[$t]}"
                i=$((i+1))
            done
        fi
        echo "------------------------------------------------"
        echo "节点端口绑定状态:"
        relay_list_nodes_status
        if [ ${#DOMAIN_ROUTES[@]} -gt 0 ]; then
            echo "域名分流规则: ${#DOMAIN_ROUTES[@]} 条"
        else
            echo "域名分流规则: 无"
        fi
        echo "------------------------------------------------"
        echo "  1. 添加中转（粘贴链接）"
        echo "  2. 为节点端口绑定中转"
        echo "  3. 取消端口的中转（改为直连）"
        echo "  4. 删除中转"
        echo "  5. 域名分流规则配置"
        echo "  0. 返回主菜单"
        echo "================================================"
        local c
        read -rp "请选择 [0-5]: " c
        case "$c" in
            1) _relay_add_ui ;;
            2) _relay_bind_ui ;;
            3) _relay_unbind_ui ;;
            4) _relay_delete_ui ;;
            5) domain_route_menu ;;
            0) return ;;
            *) warn "无效选项"; sleep 1 ;;
        esac
    done
}

# --- Management functions ---
manage_singbox() {
    local action=$1
    if [ -z "$SINGBOX_CMD" ]; then
        warn "Sing-box command 未设置, 尝试查找..."
        find_and_set_singbox_cmd
        if [ -z "$SINGBOX_CMD" ]; then
            error "仍然无法找到 Sing-box command. 操作中止。"
            return 1
        fi
    fi

    case "$action" in
        start)
            svc_start
            if svc_is_active; then success "Sing-box 服务已启动。"; else error "Sing-box 服务启动失败。"; fi
            ;;
        stop)
            svc_stop
            if ! svc_is_active; then success "Sing-box 服务已停止。"; else error "Sing-box 服务停止失败。"; fi
            ;;
        restart)
            if [ -f "$SINGBOX_CONFIG_FILE" ]; then
                info "重启前检查配置文件..."
                if ! $SINGBOX_CMD check -c "$SINGBOX_CONFIG_FILE"; then
                    error "配置文件检查失败，无法重启。请先修复配置文件。"
                    return 1
                fi
                success "配置文件检查通过。"
            fi
            svc_restart
            sleep 1
            if svc_is_active; then success "Sing-box 服务已重启。"; else error "Sing-box 服务重启失败。"; fi
            ;;
        status)
            svc_status
            ;;
        log)
            svc_log_follow 50
            ;;
        view_config)
            if [ -f "$SINGBOX_CONFIG_FILE" ]; then
                info "当前配置文件 (${SINGBOX_CONFIG_FILE}):"
                cat "$SINGBOX_CONFIG_FILE"
            else
                error "配置文件不存在: ${SINGBOX_CONFIG_FILE}"
            fi
            ;;
        edit_config)
            if [ -f "$SINGBOX_CONFIG_FILE" ]; then
                if command -v nano &> /dev/null; then
                    nano "$SINGBOX_CONFIG_FILE"
                elif command -v vim &> /dev/null; then
                    vim "$SINGBOX_CONFIG_FILE"
                else
                    error "'nano' 或 'vim' 未安装。请手动编辑: ${SINGBOX_CONFIG_FILE}"
                    return
                fi
                read -rp "配置文件已编辑，是否立即重启 sing-box 服务? (y/N): " restart_confirm
                if [[ "$restart_confirm" =~ ^[Yy]$ ]]; then
                    manage_singbox "restart"
                fi
            else
                error "配置文件不存在: ${SINGBOX_CONFIG_FILE}"
            fi
            ;;
        *)
            error "无效的管理操作: $action"
            ;;
    esac
}

# --- Main menu ---
show_menu() {
    clear
    print_header

    echo -e "${GREEN}${BOLD}安装选项:${NC}"
    echo "  1. VLESS 分支安装（Reality+Vision / TLS+ws/grpc/httpupgrade，支持套CDN）"
    echo "  2. 安装 Hysteria2"
    echo "  3. 安装 Reality (VLESS)【菜单1-1 快捷方式】"
    echo "------------------------------------------------"
    echo -e "${YELLOW}${BOLD}管理选项:${NC}"
    echo "  4. 启动 Sing-box 服务"
    echo "  5. 停止 Sing-box 服务"
    echo "  6. 重启 Sing-box 服务"
    echo "  7. 查看 Sing-box 服务状态"
    echo "  8. 查看 Sing-box 实时日志"
    echo "  9. 节点信息子菜单 (全部链接 / 配置文件 / 详细配置)"
    echo "  10. 编辑当前配置文件 (nano/vim)"
    echo "  11. 显示上次保存的导入信息 (含二维码)"
    echo "  12. 切换导入链接使用的 IP（IPv4 / IPv6 / 同时）"
    echo "------------------------------------------------"
    echo -e "${RED}${BOLD}其他选项:${NC}"
    echo "  13. 更新 Sing-box 内核 (使用官方beta脚本)"
    echo "  14. 卸载 Sing-box（单协议）"
    echo "  15. 删除指定端口节点（多节点管理）"
    echo "  16. 一键全部卸载（含脚本、证书、配置、sb）"
    echo "  17. 中转管理（按端口绑定 socks5/hy2/vless/vmess）"
    echo "  18. 出站 IP 模式（v4/v6/双栈，入站固定双栈）"
    echo "  0.  退出脚本"
    echo "================================================"
    local choice
    read -rp "请输入选项 [0-16]: " choice

    case "$choice" in
        1) vless_branch_menu ;;
        2) install_hysteria2_only ;;
        3) install_reality_only ;;
        4) manage_singbox "start" ;;
        5) manage_singbox "stop" ;;
        6) manage_singbox "restart" ;;
        7) manage_singbox "status" ;;
        8) manage_singbox "log" ;;
        9) node_info_menu ;;
        10) manage_singbox "edit_config" ;;
        11) LAST_INSTALL_MODE="all"; display_and_store_config_info "all" ;;
        12) get_server_ips; choose_link_ip_mode; save_persistent_info ;;
        13) install_singbox_core "force" && manage_singbox "restart" ;;
        14) uninstall_singbox ;;
        15) delete_node ;;
        16) uninstall_all ;;
        17) relay_menu ;;
        18) io_mode_menu ;;
        0) exit 0 ;;
        *) error "无效选项，请输入 0 到 16 之间的数字。" ;;
    esac
    echo ""
}

# --- Entry point ---
check_root
detect_system
check_dependencies
find_and_set_singbox_cmd
load_persistent_info
load_relays_from_file

while true; do
    show_menu
    # 保留此暂停：若去掉，show_menu 开头的 clear 会立即清掉操作输出
    read -n 1 -s -r -p "按任意键返回主菜单..."
done
