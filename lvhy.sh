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
DEFAULT_HYSTERIA_MASQUERADE_CN="bing.com"
DEFAULT_REALITY_SNI="www.tesla.com"

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
LAST_REALITY_SHORT_ID="0123456789abcdef"
LAST_REALITY_FINGERPRINT="chrome"
LAST_VLESS_LINK=""
LAST_INSTALL_MODE=""
LINK_IP_MODE="4"

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
    [[ "$ip" == 10.* || "$ip" == 192.168.* ]] && return 1
    if [[ "$ip" =~ ^172\.([0-9]{1,3})\..* ]]; then
        local x="${BASH_REMATCH[1]}"
        (( x >= 16 && x <= 31 )) && return 1
    fi
    [[ "$ip" == 127.* || "$ip" == 169.254.* || "$ip" == 0.* || "$ip" == 255.* ]] && return 1
    return 0
}

is_public_ipv6() {
    local ip="$1"
    [[ "$ip" == *:* ]] || return 1
    [[ "$ip" == ::1 || "$ip" == fe80::* || "$ip" == fc* || "$ip" == fd* || "$ip" == ff* ]] && return 1
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
    [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]
}

format_host_for_uri() {
    local host="$1"
    if is_ipv6 "$host"; then echo "[$host]"; else echo "$host"; fi
}

prompt_port() {
    local prompt_msg="$1" default_val="$2" var_name="$3"
    local input
    while true; do
        read -rp "${prompt_msg} (默认: ${default_val}): " input
        input="${input:-$default_val}"
        if is_valid_port "$input"; then
            printf -v "$var_name" '%s' "$input"
            break
        else
            warn "端口号必须是 1-65535 之间的整数。"
        fi
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

    local target_script="/usr/local/bin/lvhy.sh"
    local shortcut="/usr/local/bin/sb"

    if [[ "$script_name" == "bash" || "$source_script" == "/dev/fd/"* || ! -f "$source_script" ]]; then
        warn "检测到脚本通过 pipe 或临时方式运行，无法创建 sb 快捷命令。"
        info "如需使用 sb 快捷命令，请先下载脚本文件到本地再执行安装。"
        return 1
    fi

    info "正在安装脚本快捷命令 sb ..."
    cp -f "$source_script" "$target_script"
    chmod 755 "$target_script"
    cat > "$shortcut" <<EOF
#!/bin/bash
exec sudo bash ${target_script} "\$@"
EOF
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
    } > "$PERSISTENT_INFO_FILE"
    chmod 600 "$PERSISTENT_INFO_FILE"
    success "配置信息保存成功。"
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "此脚本需要以 root 权限运行。请使用 'sudo bash $0'"
        exit 1
    fi
}

attempt_install_package() {
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
        apt-get update -y && apt-get install -y "$package_name"
    elif command -v yum &>/dev/null; then
        yum install -y "$package_name"
    elif command -v dnf &>/dev/null; then
        dnf install -y "$package_name"
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
        v4_ips=$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)[0-9]+(\.[0-9]+){3}' || true)
        for ip in $v4_ips; do
            if is_public_ipv4 "$ip" && [ -z "$LAST_SERVER_IP4" ]; then
                LAST_SERVER_IP4="$ip"
            fi
        done
        v6_ips=$(ip -6 addr show 2>/dev/null | grep -oP '(?<=inet6\s)[0-9a-fA-F:]+' || true)
        for ip in $v6_ips; do
            if is_public_ipv6 "$ip" && [ -z "$LAST_SERVER_IP6" ]; then
                LAST_SERVER_IP6="$ip"
            fi
        done
    fi

    if [ -z "$LAST_SERVER_IP4" ] && [ -z "$LAST_SERVER_IP6" ]; then
        local host_ips
        host_ips=$(hostname -I 2>/dev/null || true)
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
    openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 16
}

install_singbox_core() {
    if [ -f "$SINGBOX_INSTALL_PATH_EXPECTED" ]; then
        info "Sing-box 已检测到在 $SINGBOX_INSTALL_PATH_EXPECTED."
        find_and_set_singbox_cmd
        if [ -n "$SINGBOX_CMD" ]; then
            local current_version
            current_version=$($SINGBOX_CMD version | awk '{print $3}' 2>/dev/null || true)
            if [ -n "$current_version" ]; then
                info "当前版本: $current_version"
            else
                info "无法确定当前版本 (可能是旧版 sing-box 或命令问题)。"
            fi
        fi
        local reinstall_choice
        read -rp "是否重新安装/更新 Sing-box (beta)? (y/N): " reinstall_choice
        if [[ ! "$reinstall_choice" =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi

    info "正在安装/更新 Sing-box (beta)..."
    local install_script_url="https://sing-box.vercel.app/"
    local tmp_script
    tmp_script=$(mktemp)

    if ! curl -fsSL --proto '=https' --tlsv1.2 "$install_script_url" -o "$tmp_script"; then
        error "下载 Sing-box 安装脚本失败。"
        rm -f "$tmp_script"
        return 1
    fi

    info "安装脚本已下载到: $tmp_script，开始执行..."
    if bash "$tmp_script" install --beta; then
        rm -f "$tmp_script"
        success "Sing-box 安装/更新成功。"
        find_and_set_singbox_cmd
        if [ -z "$SINGBOX_CMD" ]; then
            error "安装后仍无法找到 sing-box 命令。请检查安装和 PATH。"
            return 1
        fi
    else
        rm -f "$tmp_script"
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
        existing_cn=$(openssl x509 -in "$HYSTERIA_CERT_PEM" -noout -subject | sed -n 's/.*CN = \([^,]*\).*/\1/p' || true)
        if [ "$existing_cn" == "$domain_cn" ]; then
            info "证书 CN ($existing_cn) 与目标 ($domain_cn) 匹配，跳过重新生成。"
            return 0
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
    openssl req -new -x509 -days 3650 -key "$HYSTERIA_CERT_KEY" -out "$HYSTERIA_CERT_PEM" -subj "/CN=${domain_cn}"
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

create_config_json() {
    local mode="$1"
    local hy2_port="$2"
    local hy2_password="$3"
    local hy2_masquerade_cn="$4"
    local reality_port="$5"
    local reality_uuid="$6"
    local reality_private_key="$7"
    local reality_sni="$8"

    if [ -z "$SINGBOX_CMD" ]; then
        error "Sing-box command (SINGBOX_CMD) 未设置。无法校验或格式化配置文件。"
        return 1
    fi

    info "正在创建配置文件: ${SINGBOX_CONFIG_FILE}"
    mkdir -p "$SINGBOX_CONFIG_DIR"
    chmod 700 "$SINGBOX_CONFIG_DIR"

    local inbounds_json="[]"

    if [ "$mode" == "all" ] || [ "$mode" == "hysteria2" ]; then
        inbounds_json=$(jq --argjson port "$hy2_port" \
            --arg password "$hy2_password" \
            --arg masquerade "https://${hy2_masquerade_cn}" \
            --arg cert "$HYSTERIA_CERT_PEM" \
            --arg key "$HYSTERIA_CERT_KEY" \
            --arg sni "$hy2_masquerade_cn" \
            '. + [{
                type: "hysteria2",
                tag: "hy2-in",
                listen: "::",
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
            }]' <<< "$inbounds_json")
    fi

    if [ "$mode" == "all" ] || [ "$mode" == "reality" ]; then
        inbounds_json=$(jq --argjson port "$reality_port" \
            --arg uuid "$reality_uuid" \
            --arg sni "$reality_sni" \
            --arg private_key "$reality_private_key" \
            --arg short_id "$LAST_REALITY_SHORT_ID" \
            '. + [{
                type: "vless",
                tag: "vless-in",
                listen: "::",
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
            }]' <<< "$inbounds_json")
    fi

    jq -n --argjson inbounds "$inbounds_json" '{
        log: {level: "info", timestamp: true},
        inbounds: $inbounds,
        outbounds: [
            {type: "direct", tag: "direct"},
            {type: "block", tag: "block"}
        ],
        route: {rules: [{protocol: "dns", outbound: "direct"}]}
    }' > "$SINGBOX_CONFIG_FILE"

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
ExecReload=/bin/kill -HUP \$MAINPID
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
}

start_singbox_service() {
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
}

display_and_store_config_info() {
    local mode="$1"
    LAST_INSTALL_MODE="$mode"

    local qrencode_is_ready=false
    if check_and_prepare_qrencode; then qrencode_is_ready=true; fi

    gen_hy2_link() {
        local ip="$1"
        local h
        h=$(format_host_for_uri "$ip")
        echo "hy2://${LAST_HY2_PASSWORD}@${h}:${LAST_HY2_PORT}?sni=${LAST_HY2_MASQUERADE_CN}&alpn=h3&insecure=1#Hy2-${ip}-$(date +%s)"
    }
    gen_vless_link() {
        local ip="$1"
        local h
        h=$(format_host_for_uri "$ip")
        echo "vless://${LAST_REALITY_UUID}@${h}:${LAST_REALITY_PORT}?security=reality&sni=${LAST_REALITY_SNI}&fp=${LAST_REALITY_FINGERPRINT}&pbk=${LAST_REALITY_PUBLIC_KEY}&sid=${LAST_REALITY_SHORT_ID}&flow=xtls-rprx-vision&type=tcp#Reality-${ip}-$(date +%s)"
    }

    echo -e "----------------------------------------------------"
    if [[ "$mode" == "all" || "$mode" == "hysteria2" ]]; then
        echo -e "${GREEN}${BOLD} Hysteria2 配置信息:${NC}"
        echo -e "SNI/主机名 (证书/客户端): ${GREEN}${LAST_HY2_MASQUERADE_CN}${NC}"
        echo -e "端口: ${GREEN}${LAST_HY2_PORT}${NC}"
        echo -e "密码/Auth: ${GREEN}${LAST_HY2_PASSWORD}${NC}"
        echo -e "ALPN: ${GREEN}h3${NC}  自签证书: ${GREEN}启用(insecure=1)${NC}"

        if [[ "$LINK_IP_MODE" == "4" || "$LINK_IP_MODE" == "both" ]]; then
            if [[ -n "$LAST_SERVER_IP4" ]]; then
                LAST_HY2_LINK="$(gen_hy2_link "$LAST_SERVER_IP4")"
                echo -e "${CYAN}Hysteria2 导入链接(IPv4):${NC} ${GREEN}${LAST_HY2_LINK}${NC}"
                $qrencode_is_ready && command -v qrencode &>/dev/null && { echo "二维码(IPv4):"; qrencode -t ANSIUTF8 "${LAST_HY2_LINK}"; }
            fi
        fi
        if [[ "$LINK_IP_MODE" == "6" || "$LINK_IP_MODE" == "both" ]]; then
            if [[ -n "$LAST_SERVER_IP6" ]]; then
                local link6
                link6="$(gen_hy2_link "$LAST_SERVER_IP6")"
                echo -e "${CYAN}Hysteria2 导入链接(IPv6):${NC} ${GREEN}${link6}${NC}"
                $qrencode_is_ready && command -v qrencode &>/dev/null && { echo "二维码(IPv6):"; qrencode -t ANSIUTF8 "${link6}"; }
            fi
        fi
        echo -e "----------------------------------------------------"
    fi

    if [[ "$mode" == "all" || "$mode" == "reality" ]]; then
        echo -e "${GREEN}${BOLD} Reality (VLESS) 配置信息:${NC}"
        echo -e "端口: ${GREEN}${LAST_REALITY_PORT}${NC}"
        echo -e "UUID: ${GREEN}${LAST_REALITY_UUID}${NC}"
        echo -e "SNI: ${GREEN}${LAST_REALITY_SNI}${NC}   FP: ${GREEN}${LAST_REALITY_FINGERPRINT}${NC}"
        echo -e "PublicKey: ${GREEN}${LAST_REALITY_PUBLIC_KEY}${NC}   ShortID: ${GREEN}${LAST_REALITY_SHORT_ID}${NC}"
        echo -e "传输: ${GREEN}tcp${NC}  安全: ${GREEN}reality${NC}  Flow: ${GREEN}xtls-rprx-vision${NC}"

        if [[ "$LINK_IP_MODE" == "4" || "$LINK_IP_MODE" == "both" ]]; then
            if [[ -n "$LAST_SERVER_IP4" ]]; then
                LAST_VLESS_LINK="$(gen_vless_link "$LAST_SERVER_IP4")"
                echo -e "${CYAN}VLESS Reality 导入链接(IPv4):${NC} ${GREEN}${LAST_VLESS_LINK}${NC}"
                $qrencode_is_ready && command -v qrencode &>/dev/null && { echo "二维码(IPv4):"; qrencode -t ANSIUTF8 "${LAST_VLESS_LINK}"; }
            fi
        fi
        if [[ "$LINK_IP_MODE" == "6" || "$LINK_IP_MODE" == "both" ]]; then
            if [[ -n "$LAST_SERVER_IP6" ]]; then
                local link6
                link6="$(gen_vless_link "$LAST_SERVER_IP6")"
                echo -e "${CYAN}VLESS Reality 导入链接(IPv6):${NC} ${GREEN}${link6}${NC}"
                $qrencode_is_ready && command -v qrencode &>/dev/null && { echo "二维码(IPv6):"; qrencode -t ANSIUTF8 "${link6}"; }
            fi
        fi
        echo -e "----------------------------------------------------"
    fi

    save_persistent_info
}

# --- Installation functions ---
install_hysteria2_reality() {
    info "开始安装 Hysteria2 + Reality (共存)..."
    install_singbox_core || return 1
    get_server_ips
    choose_link_ip_mode

    prompt_port "请输入 Hysteria2 监听端口" "$DEFAULT_HYSTERIA_PORT" LAST_HY2_PORT
    prompt_domain "请输入 Hysteria2 伪装域名/证书CN" "$DEFAULT_HYSTERIA_MASQUERADE_CN" LAST_HY2_MASQUERADE_CN

    prompt_port "请输入 Reality (VLESS) 监听端口" "$DEFAULT_REALITY_PORT" LAST_REALITY_PORT
    prompt_domain "请输入 Reality 目标SNI/握手服务器" "$DEFAULT_REALITY_SNI" LAST_REALITY_SNI

    LAST_HY2_PASSWORD=$(generate_random_password)
    info "生成的 Hysteria2 密码: ${LAST_HY2_PASSWORD}"

    generate_self_signed_cert "$LAST_HY2_MASQUERADE_CN" || return 1
    generate_reality_credentials || return 1

    create_config_json "all" \
        "$LAST_HY2_PORT" "$LAST_HY2_PASSWORD" "$LAST_HY2_MASQUERADE_CN" \
        "$LAST_REALITY_PORT" "$LAST_REALITY_UUID" "$TEMP_REALITY_PRIVATE_KEY" "$LAST_REALITY_SNI" \
        || return 1

    create_systemd_service
    start_singbox_service || return 1
    install_script_shortcut || true

    success "Hysteria2 + Reality 安装配置完成！"
    display_and_store_config_info "all"
}

install_hysteria2_only() {
    info "开始单独安装 Hysteria2..."
    install_singbox_core || return 1
    get_server_ips
    choose_link_ip_mode

    prompt_port "请输入 Hysteria2 监听端口" "$DEFAULT_HYSTERIA_PORT" LAST_HY2_PORT
    prompt_domain "请输入 Hysteria2 伪装域名/证书CN" "$DEFAULT_HYSTERIA_MASQUERADE_CN" LAST_HY2_MASQUERADE_CN

    LAST_HY2_PASSWORD=$(generate_random_password)
    info "生成的 Hysteria2 密码: ${LAST_HY2_PASSWORD}"

    generate_self_signed_cert "$LAST_HY2_MASQUERADE_CN" || return 1

    LAST_REALITY_PORT=""
    LAST_REALITY_UUID=""
    LAST_REALITY_PUBLIC_KEY=""
    LAST_REALITY_SNI=""
    LAST_VLESS_LINK=""

    create_config_json "hysteria2" \
        "$LAST_HY2_PORT" "$LAST_HY2_PASSWORD" "$LAST_HY2_MASQUERADE_CN" \
        "" "" "" "" \
        || return 1

    create_systemd_service
    start_singbox_service || return 1
    install_script_shortcut || true

    success "Hysteria2 单独安装配置完成！"
    display_and_store_config_info "hysteria2"
}

install_reality_only() {
    info "开始单独安装 Reality (VLESS)..."
    install_singbox_core || return 1
    get_server_ips
    choose_link_ip_mode

    prompt_port "请输入 Reality (VLESS) 监听端口" "$DEFAULT_REALITY_PORT" LAST_REALITY_PORT
    prompt_domain "请输入 Reality 目标SNI/握手服务器" "$DEFAULT_REALITY_SNI" LAST_REALITY_SNI

    generate_reality_credentials || return 1

    LAST_HY2_PORT=""
    LAST_HY2_PASSWORD=""
    LAST_HY2_MASQUERADE_CN=""
    LAST_HY2_LINK=""

    create_config_json "reality" \
        "" "" "" \
        "$LAST_REALITY_PORT" "$LAST_REALITY_UUID" "$TEMP_REALITY_PRIVATE_KEY" "$LAST_REALITY_SNI" \
        || return 1

    create_systemd_service
    start_singbox_service || return 1
    install_script_shortcut || true

    success "Reality (VLESS) 单独安装配置完成！"
    display_and_store_config_info "reality"
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
    systemctl stop sing-box &>/dev/null || true
    info "正在禁用 sing-box 服务..."
    systemctl disable sing-box &>/dev/null || true

    if [ -f "$SINGBOX_SERVICE_FILE" ]; then
        info "正在删除 systemd 服务文件: ${SINGBOX_SERVICE_FILE}"
        rm -f "$SINGBOX_SERVICE_FILE"
        systemctl daemon-reload
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

    success "Sing-box 卸载完成。"
    LAST_INSTALL_MODE=""
    SINGBOX_CMD=""
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
            systemctl start sing-box
            if systemctl is-active --quiet sing-box; then success "Sing-box 服务已启动。"; else error "Sing-box 服务启动失败。"; fi
            ;;
        stop)
            systemctl stop sing-box
            if ! systemctl is-active --quiet sing-box; then success "Sing-box 服务已停止。"; else error "Sing-box 服务停止失败。"; fi
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
            systemctl restart sing-box
            sleep 1
            if systemctl is-active --quiet sing-box; then success "Sing-box 服务已重启。"; else error "Sing-box 服务重启失败。"; fi
            ;;
        status)
            systemctl status sing-box --no-pager -l
            ;;
        log)
            journalctl -u sing-box -f --no-pager -n 50
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
    echo "  1. 安装 Hysteria2 + Reality (共存)"
    echo "  2. 单独安装 Hysteria2"
    echo "  3. 单独安装 Reality (VLESS)"
    echo "------------------------------------------------"
    echo -e "${YELLOW}${BOLD}管理选项:${NC}"
    echo "  4. 启动 Sing-box 服务"
    echo "  5. 停止 Sing-box 服务"
    echo "  6. 重启 Sing-box 服务"
    echo "  7. 查看 Sing-box 服务状态"
    echo "  8. 查看 Sing-box 实时日志"
    echo "  9. 查看当前配置文件"
    echo "  10. 编辑当前配置文件 (nano/vim)"
    echo "  11. 显示上次保存的导入信息 (含二维码)"
    echo "  14. 切换导入链接使用的 IP（IPv4 / IPv6 / 同时）"
    echo "------------------------------------------------"
    echo -e "${RED}${BOLD}其他选项:${NC}"
    echo "  12. 更新 Sing-box 内核 (使用官方beta脚本)"
    echo "  13. 卸载 Sing-box"
    echo "  0.  退出脚本"
    echo "================================================"
    local choice
    read -rp "请输入选项 [0-14]: " choice

    case "$choice" in
        1) install_hysteria2_reality ;;
        2) install_hysteria2_only ;;
        3) install_reality_only ;;
        4) manage_singbox "start" ;;
        5) manage_singbox "stop" ;;
        6) manage_singbox "restart" ;;
        7) manage_singbox "status" ;;
        8) manage_singbox "log" ;;
        9) manage_singbox "view_config" ;;
        10) manage_singbox "edit_config" ;;
        11) show_current_import_info ;;
        12) install_singbox_core && manage_singbox "restart" ;;
        13) uninstall_singbox ;;
        14) get_server_ips; choose_link_ip_mode; save_persistent_info ;;
        0) exit 0 ;;
        *) error "无效选项，请输入 0 到 14 之间的数字。" ;;
    esac
    echo ""
}

# --- Entry point ---
check_root
check_dependencies
find_and_set_singbox_cmd
load_persistent_info

while true; do
    show_menu
    read -n 1 -s -r -p "按任意键返回主菜单 (或按 Ctrl+C 退出)..."
done
