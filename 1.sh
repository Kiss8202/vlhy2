bash << 'VLESS_FINAL_EOF'
set -e

SCRIPT_PATH="/root/install.sh"
[ -f "$SCRIPT_PATH" ] || { echo "[ERROR] 脚本不存在: $SCRIPT_PATH"; exit 1; }
BACKUP="${SCRIPT_PATH}.bak.vless.$(date +%Y%m%d_%H%M%S)"
cp -a "$SCRIPT_PATH" "$BACKUP"
echo "[INFO] 已备份: $BACKUP"

python3 << 'PY_EOF'
import sys
path = "/root/install.sh"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

if 'NODE_VLESS_TLS_UUID' in content:
    print("[WARN] 已存在 VLESS 分支补丁，跳过"); sys.exit(0)

def rep(old, new, tag):
    global content
    if old not in content:
        print(f"[ERROR] 未找到: {tag}"); sys.exit(1)
    content = content.replace(old, new, 1)

# ========== 1. 变量声明 ==========
rep(
'''RELAY_FILE="${SINGBOX_CONFIG_DIR}/relays.conf"
declare -a DOMAIN_ROUTES=()''',
'''RELAY_FILE="${SINGBOX_CONFIG_DIR}/relays.conf"
declare -a DOMAIN_ROUTES=()

# VLESS + TLS 节点
declare -A NODE_VLESS_TLS_UUID=()
declare -A NODE_VLESS_TLS_TYPE=()
declare -A NODE_VLESS_TLS_SNI=()
declare -A NODE_VLESS_TLS_PATH=()
declare -A NODE_VLESS_TLS_HOST=()
declare -A NODE_VLESS_TLS_SVC=()
declare -A NODE_VLESS_TLS_CDN=()
declare -A NODE_VLESS_TLS_RELAY=()
VLESS_TLS_CERT_DIR="/etc/sing-box/vless-tls"
VLESS_TLS_CERT_PEM="${VLESS_TLS_CERT_DIR}/cert.pem"
VLESS_TLS_CERT_KEY="${VLESS_TLS_CERT_DIR}/private.key"''',
'变量声明')

# ========== 2. load_persistent_info ==========
rep(
'''            NODE_REALITY_*)
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
        esac''',
'''            NODE_REALITY_*)
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
                    HOST) NODE_VLESS_TLS_HOST["$port3"]="$value" ;;
                    SVC) NODE_VLESS_TLS_SVC["$port3"]="$value" ;;
                    CDN) NODE_VLESS_TLS_CDN["$port3"]="$value" ;;
                esac
                ;;
        esac''',
'load_persistent_info')

# ========== 3. save_persistent_info ==========
rep(
'''        echo "NODE_REALITY_${p}_FP=\\"${NODE_REALITY_FP[$p]:-chrome}\\""
    done >> "$PERSISTENT_INFO_FILE"

    chmod 600 "$PERSISTENT_INFO_FILE"''',
'''        echo "NODE_REALITY_${p}_FP=\\"${NODE_REALITY_FP[$p]:-chrome}\\""
    done >> "$PERSISTENT_INFO_FILE"
    for p in "${!NODE_VLESS_TLS_UUID[@]}"; do
        echo "NODE_VLESS_TLS_${p}_UUID=\\"${NODE_VLESS_TLS_UUID[$p]}\\""
        echo "NODE_VLESS_TLS_${p}_TYPE=\\"${NODE_VLESS_TLS_TYPE[$p]:-ws}\\""
        echo "NODE_VLESS_TLS_${p}_SNI=\\"${NODE_VLESS_TLS_SNI[$p]:-}\\""
        echo "NODE_VLESS_TLS_${p}_PATH=\\"${NODE_VLESS_TLS_PATH[$p]:-}\\""
        echo "NODE_VLESS_TLS_${p}_HOST=\\"${NODE_VLESS_TLS_HOST[$p]:-}\\""
        echo "NODE_VLESS_TLS_${p}_SVC=\\"${NODE_VLESS_TLS_SVC[$p]:-}\\""
        echo "NODE_VLESS_TLS_${p}_CDN=\\"${NODE_VLESS_TLS_CDN[$p]:-}\\""
    done >> "$PERSISTENT_INFO_FILE"

    chmod 600 "$PERSISTENT_INFO_FILE"''',
'save_persistent_info')

# ========== 4. generate_vless_tls_cert ==========
rep(
'get_listen_address() {',
'''generate_vless_tls_cert() {
    local domain_cn="$1"
    if [ -f "$VLESS_TLS_CERT_PEM" ] && [ -f "$VLESS_TLS_CERT_KEY" ]; then
        local existing_cn
        existing_cn=$(openssl x509 -in "$VLESS_TLS_CERT_PEM" -noout -subject 2>/dev/null | sed -n 's/.*CN[[:space:]]*=[[:space:]]*\\([^,]*\\).*/\\1/p' || true)
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
    if ! openssl req -new -x509 -days 3650 -key "$VLESS_TLS_CERT_KEY" -out "$VLESS_TLS_CERT_PEM" \\
        -subj "/CN=${domain_cn}" -addext "subjectAltName=DNS:${domain_cn}" 2>/dev/null; then
        warn "当前 OpenSSL 不支持 -addext，回退为仅含 CN 的证书..."
        openssl req -new -x509 -days 3650 -key "$VLESS_TLS_CERT_KEY" -out "$VLESS_TLS_CERT_PEM" -subj "/CN=${domain_cn}"
    fi
    chmod 600 "$VLESS_TLS_CERT_PEM"
    success "VLESS+TLS 自签证书生成成功。"
}

get_listen_address() {''',
'generate_vless_tls_cert')

# ========== 5. create_config_json 签名 ==========
rep(
'''    local reality_private_key="$7"
    local reality_sni="$8"

    if [ -z "$SINGBOX_CMD" ]; then
        error "Sing-box command (SINGBOX_CMD) 未设置。无法校验或格式化配置文件。"
        return 1
    fi''',
'''    local reality_private_key="$7"
    local reality_sni="$8"
    local vtls_port="${9:-}"
    local vtls_uuid="${10:-}"
    local vtls_transport="${11:-}"
    local vtls_sni="${12:-}"
    local vtls_path="${13:-}"
    local vtls_host="${14:-}"
    local vtls_svc="${15:-}"

    if [ -z "$SINGBOX_CMD" ]; then
        error "Sing-box command (SINGBOX_CMD) 未设置。无法校验或格式化配置文件。"
        return 1
    fi''',
'create_config_json 签名')

# ========== 6. create_config_json 加 vless_tls 分支 ==========
rep(
'''    local _direct_ob
    case "${OUTBOUND_MODE:-both}" in
        v4) _direct_ob='{"type":"direct","tag":"direct","domain_resolver":{"server":"local","strategy":"ipv4_only"}}' ;;
        v6) _direct_ob='{"type":"direct","tag":"direct","domain_resolver":{"server":"local","strategy":"ipv6_only"}}' ;;
        *)  _direct_ob='{"type":"direct","tag":"direct"}' ;;
    esac
    local _ob="[${_direct_ob},{\\"type\\":\\"block\\",\\"tag\\":\\"block\\"}]"''',
'''    if [ "$mode" == "vless_tls" ]; then
        local vtls_tag="vless-tls-in-${vtls_port}"
        existing_inbounds=$(jq --arg tag "$vtls_tag" 'map(select(.tag != $tag))' <<< "$existing_inbounds")
        existing_inbounds=$(jq --argjson port "$vtls_port" \\
            --arg uuid "$vtls_uuid" \\
            --arg sni "$vtls_sni" \\
            --arg cert "$VLESS_TLS_CERT_PEM" \\
            --arg key "$VLESS_TLS_CERT_KEY" \\
            --arg tag "$vtls_tag" \\
            --arg listen "$listen_addr" \\
            --arg ttype "$vtls_transport" \\
            --arg tpath "$vtls_path" \\
            --arg thost "$vtls_host" \\
            --arg tsvc "$vtls_svc" \\
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
                    {transport: {type: "ws", path: $tpath, headers: {Host: $thost}}}
                   elif $ttype == "httpupgrade" then
                    {transport: {type: "httpupgrade", path: $tpath, headers: {Host: $thost}}}
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
    local _ob="[${_direct_ob},{\\"type\\":\\"block\\",\\"tag\\":\\"block\\"}]"''',
'create_config_json vless_tls 分支')

# ========== 7. display_and_store_config_info 加 gen_vless_tls_link ==========
rep(
'''        echo "vless://${uuid}@${h}:${port}?security=reality&sni=${sni}&fp=${fp}&pbk=${pub}&sid=${sid}&flow=xtls-rprx-vision&type=tcp#Reality-${port}-${ip}"
    }

    if [[ "$mode" == "all" || "$mode" == "hysteria2" ]]; then''',
'''        echo "vless://${uuid}@${h}:${port}?security=reality&sni=${sni}&fp=${fp}&pbk=${pub}&sid=${sid}&flow=xtls-rprx-vision&type=tcp#Reality-${port}-${ip}"
    }
    gen_vless_tls_link() {
        local port="$1"
        local ip="$2"
        local uuid="${NODE_VLESS_TLS_UUID[$port]}"
        local tp="${NODE_VLESS_TLS_TYPE[$port]}"
        local sni="${NODE_VLESS_TLS_SNI[$port]}"
        local path="${NODE_VLESS_TLS_PATH[$port]:-}"
        local svc="${NODE_VLESS_TLS_SVC[$port]:-}"
        local cdn="${NODE_VLESS_TLS_CDN[$port]:-}"
        local addr="$ip"
        local link_port="$port"
        local link_sni="$sni"
        local allow_insecure="1"
        if [ -n "$cdn" ]; then
            addr="$cdn"
            link_port="443"
            link_sni="$cdn"
            allow_insecure="0"
        fi
        local h
        h=$(format_host_for_uri "$addr")
        local link="vless://${uuid}@${h}:${link_port}?security=tls&sni=${link_sni}&fp=chrome&allowInsecure=${allow_insecure}&type=${tp}"
        if [[ "$tp" == "ws" || "$tp" == "httpupgrade" ]]; then
            link="${link}&path=${path}&host=${link_sni}"
        elif [[ "$tp" == "grpc" ]]; then
            link="${link}&serviceName=${svc}"
        fi
        echo "${link}#VLESS-TLS-${port}-${addr}"
    }

    if [[ "$mode" == "all" || "$mode" == "hysteria2" ]]; then''',
'display_and_store_config_info gen_vless_tls_link')

# ========== 8. display_and_store_config_info 加 VLESS+TLS 显示 ==========
rep(
'''    save_persistent_info
}

# --- Installation functions ---
install_hysteria2_reality() {''',
'''    if [[ "$mode" == "all" || "$mode" == "vless_tls" ]]; then
        local p
        for p in "${!NODE_VLESS_TLS_UUID[@]}"; do
            local tp="${NODE_VLESS_TLS_TYPE[$p]:-ws}"
            local cdn="${NODE_VLESS_TLS_CDN[$p]:-}"
            echo -e "----------------------------------------------------"
            echo -e "${GREEN}${BOLD} VLESS+TLS (端口 ${p}, ${tp}) 配置信息:${NC}"
            echo -e "UUID: ${GREEN}${NODE_VLESS_TLS_UUID[$p]}${NC}"
            echo -e "SNI: ${GREEN}${NODE_VLESS_TLS_SNI[$p]:-}${NC}   Type: ${GREEN}${tp}${NC}"
            [[ -n "${NODE_VLESS_TLS_PATH[$p]:-}" ]] && echo -e "Path: ${GREEN}${NODE_VLESS_TLS_PATH[$p]}${NC}"
            [[ -n "${NODE_VLESS_TLS_HOST[$p]:-}" ]] && echo -e "Host: ${GREEN}${NODE_VLESS_TLS_HOST[$p]}${NC}"
            [[ -n "${NODE_VLESS_TLS_SVC[$p]:-}" ]] && echo -e "ServiceName: ${GREEN}${NODE_VLESS_TLS_SVC[$p]}${NC}"
            if [ -n "$cdn" ]; then
                echo -e "${YELLOW}已套 CDN: ${cdn} (客户端连接 ${cdn}:443)${NC}"
            fi
            if [ -n "$cdn" ]; then
                local link
                link=$(gen_vless_tls_link "$p" "$LAST_SERVER_IP4")
                echo -e "${CYAN}VLESS+TLS 导入链接 (CDN):${NC} ${GREEN}${link}${NC}"
                $qrencode_is_ready && command -v qrencode &>/dev/null && { echo "二维码:"; qrencode -t ANSIUTF8 "$link"; }
            else
                if [[ "$LINK_IP_MODE" == "4" || "$LINK_IP_MODE" == "both" ]] && [[ -n "$LAST_SERVER_IP4" ]]; then
                    local link
                    link=$(gen_vless_tls_link "$p" "$LAST_SERVER_IP4")
                    echo -e "${CYAN}VLESS+TLS 导入链接(IPv4):${NC} ${GREEN}${link}${NC}"
                    $qrencode_is_ready && command -v qrencode &>/dev/null && { echo "二维码:"; qrencode -t ANSIUTF8 "$link"; }
                fi
                if [[ "$LINK_IP_MODE" == "6" || "$LINK_IP_MODE" == "both" ]] && [[ -n "$LAST_SERVER_IP6" ]]; then
                    local link6
                    link6=$(gen_vless_tls_link "$p" "$LAST_SERVER_IP6")
                    echo -e "${CYAN}VLESS+TLS 导入链接(IPv6):${NC} ${GREEN}${link6}${NC}"
                    $qrencode_is_ready && command -v qrencode &>/dev/null && { echo "二维码:"; qrencode -t ANSIUTF8 "$link6"; }
                fi
            fi
        done
    fi

    save_persistent_info
}

# --- Installation functions ---
install_hysteria2_reality() {''',
'display_and_store_config_info vless_tls 显示')

# ========== 9. show_all_node_links 加 VLESS+TLS ==========
rep(
'''        if [ -n "$LAST_SERVER_IP6" ]; then
            h6=$(format_host_for_uri "$LAST_SERVER_IP6")
            echo "IPv6: vless://${uuid}@${h6}:${p}?security=reality&sni=${sni}&fp=${fp}&pbk=${pub}&sid=${sid}&flow=xtls-rprx-vision&type=tcp#Reality-${p}-${LAST_SERVER_IP6}"
        fi
    done
    echo "================================================"
}''',
'''        if [ -n "$LAST_SERVER_IP6" ]; then
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
        local cdn="${NODE_VLESS_TLS_CDN[$p]:-}"
        echo ""
        echo "[VLESS+TLS (${tp}) - 端口 $p]"
        local _build_link() {
            local addr="$1" link_port="$2" link_sni="$3" ai="$4"
            local l="vless://${uuid}@${addr}:${link_port}?security=tls&sni=${link_sni}&fp=chrome&allowInsecure=${ai}&type=${tp}"
            if [[ "$tp" == "ws" || "$tp" == "httpupgrade" ]]; then
                l="${l}&path=${path}&host=${link_sni}"
            elif [[ "$tp" == "grpc" ]]; then
                l="${l}&serviceName=${svc}"
            fi
            echo "${l}#VLESS-TLS-${p}-${addr}"
        }
        if [ -n "$cdn" ]; then
            echo "CDN: $(_build_link "$cdn" "443" "$cdn" "0")"
        else
            if [ -n "$LAST_SERVER_IP4" ]; then
                h4=$(format_host_for_uri "$LAST_SERVER_IP4")
                echo "IPv4: $(_build_link "$h4" "$p" "$sni" "1")"
            fi
            if [ -n "$LAST_SERVER_IP6" ]; then
                h6=$(format_host_for_uri "$LAST_SERVER_IP6")
                echo "IPv6: $(_build_link "$h6" "$p" "$sni" "1")"
            fi
        fi
        unset -f _build_link
    done
    echo "================================================"
}''',
'show_all_node_links vless_tls')

# ========== 10. install_vless_tls + vless_branch_menu ==========
rep(
'show_current_import_info() {',
'''install_vless_tls() {
    info "开始安装 VLESS + TLS ..."
    install_singbox_core || return 1
    get_server_ips
    choose_link_ip_mode

    echo ""
    echo "选择传输层（都支持套 CDN）:"
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

    local port
    prompt_port "请输入 VLESS+TLS 监听端口" "8444" port tcp

    local sni
    prompt_domain "请输入 SNI / 证书 CN" "$DEFAULT_REALITY_SNI" sni

    local path="" host="" svc=""
    if [[ "$transport" == "ws" || "$transport" == "httpupgrade" ]]; then
        read -rp "WS 路径 [默认 /vless]: " path
        path="${path:-/vless}"
        read -rp "Host 头 [留空与 SNI 一致]: " host
        [ -z "$host" ] && host="$sni"
    elif [[ "$transport" == "grpc" ]]; then
        read -rp "gRPC serviceName [默认 grpc]: " svc
        svc="${svc:-grpc}"
    fi

    local cdn=""
    read -rp "是否套 CDN? (y/N): " use_cdn
    if [[ "$use_cdn" =~ ^[Yy]$ ]]; then
        local cdn_domain
        read -rp "CDN 域名 (如 cdn.example.com): " cdn_domain
        if is_valid_domain "$cdn_domain"; then
            cdn="$cdn_domain"
        else
            warn "CDN 域名无效，忽略"
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

    create_config_json "vless_tls" "" "" "" "" "" "" "" \\
        "$port" "$uuid" "$transport" "$sni" "$path" "$host" "$svc" || return 1

    NODE_VLESS_TLS_UUID["$port"]="$uuid"
    NODE_VLESS_TLS_TYPE["$port"]="$transport"
    NODE_VLESS_TLS_SNI["$port"]="$sni"
    NODE_VLESS_TLS_PATH["$port"]="$path"
    NODE_VLESS_TLS_HOST["$port"]="$host"
    NODE_VLESS_TLS_SVC["$port"]="$svc"
    NODE_VLESS_TLS_CDN["$port"]="$cdn"

    create_systemd_service
    start_singbox_service || return 1
    install_script_shortcut || true

    success "VLESS + TLS ($transport) 安装配置完成！"
    if [ -n "$cdn" ]; then
        info "已套 CDN：客户端连接地址为 ${cdn}:443（TLS 走真证书，allowInsecure=0）"
    fi
    display_and_store_config_info "vless_tls"
}

vless_branch_menu() {
    while true; do
        clear
        echo "================================================"
        echo -e "${CYAN}${BOLD}          VLESS 分支安装${NC}"
        echo "================================================"
        echo "  1. VLESS + Reality + Vision (抗审查首选)"
        echo "  2. VLESS + TLS (ws/grpc/httpupgrade，支持套 CDN)"
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

show_current_import_info() {''',
'install_vless_tls + vless_branch_menu')

# ========== 11. 菜单 1 改为 VLESS 分支 ==========
rep(
'''    echo -e "${GREEN}${BOLD}安装选项:${NC}"
    echo "  1. 安装 Hysteria2 + Reality "
    echo "  2. 安装 Hysteria2"
    echo "  3. 安装 Reality (VLESS)"''',
'''    echo -e "${GREEN}${BOLD}安装选项:${NC}"
    echo "  1. VLESS 分支安装（Reality+Vision / TLS+ws/grpc/httpupgrade，支持套CDN）"
    echo "  2. 安装 Hysteria2"
    echo "  3. 安装 Reality (VLESS)"''',
'菜单 1 文案')

rep(
'        1) install_hysteria2_reality ;;',
'        1) vless_branch_menu ;;',
'菜单 1 case')

# ========== 12. delete_node 扩展 ==========
rep(
'''    for p in "${!NODE_REALITY_UUID[@]}"; do
        echo "  reality  端口 $p"
        any=true
    done
    $any || { warn "当前没有任何节点。"; return; }''',
'''    for p in "${!NODE_REALITY_UUID[@]}"; do
        echo "  reality  端口 $p"
        any=true
    done
    for p in "${!NODE_VLESS_TLS_UUID[@]}"; do
        echo "  vless-tls 端口 $p (${NODE_VLESS_TLS_TYPE[$p]:-})"
        any=true
    done
    $any || { warn "当前没有任何节点。"; return; }''',
'delete_node 列表')

rep(
'''    if [ -n "${NODE_REALITY_UUID[$del_port]:-}" ]; then
        unset 'NODE_REALITY_UUID[$del_port]' 'NODE_REALITY_PUBLIC_KEY[$del_port]' \\
              'NODE_REALITY_SNI[$del_port]' 'NODE_REALITY_SHORT_ID[$del_port]' 'NODE_REALITY_FP[$del_port]'
        found=true
        info "已移除 reality 端口 $del_port"
    fi
    if ! $found; then''',
'''    if [ -n "${NODE_REALITY_UUID[$del_port]:-}" ]; then
        unset 'NODE_REALITY_UUID[$del_port]' 'NODE_REALITY_PUBLIC_KEY[$del_port]' \\
              'NODE_REALITY_SNI[$del_port]' 'NODE_REALITY_SHORT_ID[$del_port]' 'NODE_REALITY_FP[$del_port]'
        found=true
        info "已移除 reality 端口 $del_port"
    fi
    if [ -n "${NODE_VLESS_TLS_UUID[$del_port]:-}" ]; then
        unset 'NODE_VLESS_TLS_UUID[$del_port]' 'NODE_VLESS_TLS_TYPE[$del_port]' \\
              'NODE_VLESS_TLS_SNI[$del_port]' 'NODE_VLESS_TLS_PATH[$del_port]' \\
              'NODE_VLESS_TLS_HOST[$del_port]' 'NODE_VLESS_TLS_SVC[$del_port]' \\
              'NODE_VLESS_TLS_CDN[$del_port]' 'NODE_VLESS_TLS_RELAY[$del_port]'
        found=true
        info "已移除 vless-tls 端口 $del_port"
    fi
    if ! $found; then''',
'delete_node unset')

rep(
'''        jq --arg ht "hy2-in-${del_port}" --arg vt "vless-in-${del_port}" \\
           '.inbounds |= map(select(.tag != $ht and .tag != $vt))' \\
           "$SINGBOX_CONFIG_FILE" > "$SINGBOX_CONFIG_FILE.tmp" \\
           && mv "$SINGBOX_CONFIG_FILE.tmp" "$SINGBOX_CONFIG_FILE"''',
'''        jq --arg ht "hy2-in-${del_port}" --arg vt "vless-in-${del_port}" --arg vtt "vless-tls-in-${del_port}" \\
           '.inbounds |= map(select(.tag != $ht and .tag != $vt and .tag != $vtt))' \\
           "$SINGBOX_CONFIG_FILE" > "$SINGBOX_CONFIG_FILE.tmp" \\
           && mv "$SINGBOX_CONFIG_FILE.tmp" "$SINGBOX_CONFIG_FILE"''',
'delete_node jq')

# ========== 13. relay save/load 支持 vless-tls ==========
rep(
'''        for p in "${!NODE_REALITY_RELAY[@]}"; do
            [ -z "${NODE_REALITY_UUID[$p]:-}" ] && continue
            echo "BIND|reality|${p}|${NODE_REALITY_RELAY[$p]}"
        done
        local _r''',
'''        for p in "${!NODE_REALITY_RELAY[@]}"; do
            [ -z "${NODE_REALITY_UUID[$p]:-}" ] && continue
            echo "BIND|reality|${p}|${NODE_REALITY_RELAY[$p]}"
        done
        for p in "${!NODE_VLESS_TLS_RELAY[@]}"; do
            [ -z "${NODE_VLESS_TLS_UUID[$p]:-}" ] && continue
            echo "BIND|vless-tls|${p}|${NODE_VLESS_TLS_RELAY[$p]}"
        done
        local _r''',
'save_relays_to_file vless-tls')

rep(
'''            BIND)
                case "$a" in
                    hy2) NODE_HY2_RELAY["$b"]="$c" ;;
                    reality) NODE_REALITY_RELAY["$b"]="$c" ;;
                esac
                ;;''',
'''            BIND)
                case "$a" in
                    hy2) NODE_HY2_RELAY["$b"]="$c" ;;
                    reality) NODE_REALITY_RELAY["$b"]="$c" ;;
                    vless-tls) NODE_VLESS_TLS_RELAY["$b"]="$c" ;;
                esac
                ;;''',
'load_relays_from_file vless-tls')

# load_relays_from_file 清空时也清 vless-tls
rep(
'''    RELAY_JSON=(); RELAY_DESC=()
    NODE_HY2_RELAY=(); NODE_REALITY_RELAY=()
    DOMAIN_ROUTES=()''',
'''    RELAY_JSON=(); RELAY_DESC=()
    NODE_HY2_RELAY=(); NODE_REALITY_RELAY=(); NODE_VLESS_TLS_RELAY=()
    DOMAIN_ROUTES=()''',
'load_relays_from_file 清空')

# ========== 14. _relay_build_rules_json 加 vless-tls ==========
rep(
'''        if [ "$_inb" == "all" ]; then
            for _p in "${!NODE_HY2_PASSWORD[@]}"; do _inbounds+=("hy2-in-${_p}"); done
            for _p in "${!NODE_REALITY_UUID[@]}"; do _inbounds+=("vless-in-${_p}"); done
        else''',
'''        if [ "$_inb" == "all" ]; then
            for _p in "${!NODE_HY2_PASSWORD[@]}"; do _inbounds+=("hy2-in-${_p}"); done
            for _p in "${!NODE_REALITY_UUID[@]}"; do _inbounds+=("vless-in-${_p}"); done
            for _p in "${!NODE_VLESS_TLS_UUID[@]}"; do _inbounds+=("vless-tls-in-${_p}"); done
        else''',
'_relay_build_rules_json all 展开')

rep(
'''    for _p in "${!NODE_REALITY_RELAY[@]}"; do
        _rt="${NODE_REALITY_RELAY[$_p]}"
        if [ -z "$_rt" ] || [ "$_rt" == "direct" ]; then continue; fi
        if [ -z "${RELAY_JSON[$_rt]:-}" ]; then continue; fi
        _tag="vless-in-${_p}"
        _relay_check_inb "$_tag" || continue
        rules=$(jq --arg inb "$_tag" --arg out "$_rt" '. + [{inbound: [$inb], outbound: $out}]' <<< "$rules")
    done

    unset -f _relay_check_inb''',
'''    for _p in "${!NODE_REALITY_RELAY[@]}"; do
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

    unset -f _relay_check_inb''',
'_relay_build_rules_json 端口级 vless-tls')

# ========== 15. relay_list_nodes_status 加 vless-tls ==========
rep(
'''    for p in "${!NODE_REALITY_UUID[@]}"; do
        desc="直连"; rt="${NODE_REALITY_RELAY[$p]:-}"
        [ -n "$rt" ] && [ "$rt" != "direct" ] && desc="中转: ${RELAY_DESC[$rt]:-$rt}"
        echo "  reality  端口 $p → $desc"; any=true
    done
    $any || echo "  （无节点）"''',
'''    for p in "${!NODE_REALITY_UUID[@]}"; do
        desc="直连"; rt="${NODE_REALITY_RELAY[$p]:-}"
        [ -n "$rt" ] && [ "$rt" != "direct" ] && desc="中转: ${RELAY_DESC[$rt]:-$rt}"
        echo "  reality  端口 $p → $desc"; any=true
    done
    for p in "${!NODE_VLESS_TLS_UUID[@]}"; do
        desc="直连"; rt="${NODE_VLESS_TLS_RELAY[$p]:-}"
        [ -n "$rt" ] && [ "$rt" != "direct" ] && desc="中转: ${RELAY_DESC[$rt]:-$rt}"
        echo "  vless-tls 端口 $p → $desc"; any=true
    done
    $any || echo "  （无节点）"''',
'relay_list_nodes_status vless-tls')

# ========== 16. _relay_bind_ui 加 vless-tls ==========
rep(
'''    for p in "${!NODE_REALITY_UUID[@]}"; do
        echo "  [$i] reality 端口 $p"
        ports+=("$p"); types+=("reality"); i=$((i+1))
    done
    if [ ${#ports[@]} -eq 0 ]; then''',
'''    for p in "${!NODE_REALITY_UUID[@]}"; do
        echo "  [$i] reality 端口 $p"
        ports+=("$p"); types+=("reality"); i=$((i+1))
    done
    for p in "${!NODE_VLESS_TLS_UUID[@]}"; do
        echo "  [$i] vless-tls 端口 $p"
        ports+=("$p"); types+=("vless-tls"); i=$((i+1))
    done
    if [ ${#ports[@]} -eq 0 ]; then''',
'_relay_bind_ui 列表')

rep(
'''    if [ "$sel_type" == "hy2" ]; then
        NODE_HY2_RELAY["$sel_port"]="$sel_tag"
    else
        NODE_REALITY_RELAY["$sel_port"]="$sel_tag"
    fi
    success "已绑定: $sel_type 端口 $sel_port → ${RELAY_DESC[$sel_tag]}"''',
'''    if [ "$sel_type" == "hy2" ]; then
        NODE_HY2_RELAY["$sel_port"]="$sel_tag"
    elif [ "$sel_type" == "reality" ]; then
        NODE_REALITY_RELAY["$sel_port"]="$sel_tag"
    elif [ "$sel_type" == "vless-tls" ]; then
        NODE_VLESS_TLS_RELAY["$sel_port"]="$sel_tag"
    fi
    success "已绑定: $sel_type 端口 $sel_port → ${RELAY_DESC[$sel_tag]}"''',
'_relay_bind_ui 绑定')

# ========== 17. _relay_unbind_ui 加 vless-tls ==========
rep(
'''    if [ -n "${NODE_REALITY_RELAY[$up]:-}" ]; then unset "NODE_REALITY_RELAY[$up]"; found=1; fi
    if [ $found -eq 0 ]; then''',
'''    if [ -n "${NODE_REALITY_RELAY[$up]:-}" ]; then unset "NODE_REALITY_RELAY[$up]"; found=1; fi
    if [ -n "${NODE_VLESS_TLS_RELAY[$up]:-}" ]; then unset "NODE_VLESS_TLS_RELAY[$up]"; found=1; fi
    if [ $found -eq 0 ]; then''',
'_relay_unbind_ui')

# ========== 18. _relay_delete_ui 加 vless-tls ==========
rep(
'''    for p in "${!NODE_REALITY_RELAY[@]}"; do
        [ "${NODE_REALITY_RELAY[$p]}" == "$dt" ] && unset "NODE_REALITY_RELAY[$p]"
    done
    # 清除该中转的域名分流规则''',
'''    for p in "${!NODE_REALITY_RELAY[@]}"; do
        [ "${NODE_REALITY_RELAY[$p]}" == "$dt" ] && unset "NODE_REALITY_RELAY[$p]"
    done
    for p in "${!NODE_VLESS_TLS_RELAY[@]}"; do
        [ "${NODE_VLESS_TLS_RELAY[$p]}" == "$dt" ] && unset "NODE_VLESS_TLS_RELAY[$p]"
    done
    # 清除该中转的域名分流规则''',
'_relay_delete_ui vless-tls')

# ========== 19. _domain_route_add_ui 加 vless-tls ==========
rep(
'''    for p in "${!NODE_REALITY_UUID[@]}"; do
        inb_list+=("vless-in-${p}"); inb_show+=("reality 端口 $p"); i=$((i+1))
    done
    echo ""''',
'''    for p in "${!NODE_REALITY_UUID[@]}"; do
        inb_list+=("vless-in-${p}"); inb_show+=("reality 端口 $p"); i=$((i+1))
    done
    for p in "${!NODE_VLESS_TLS_UUID[@]}"; do
        inb_list+=("vless-tls-in-${p}"); inb_show+=("vless-tls 端口 $p"); i=$((i+1))
    done
    echo ""''',
'_domain_route_add_ui 列表')

# ========== 20. uninstall_singbox 清理 VLESS_TLS_CERT_DIR ==========
rep(
'''    read -rp "是否删除 Hysteria2 证书目录 ${HYSTERIA_CERT_DIR}? (y/N): " delete_cert_dir_confirm
    if [[ "$delete_cert_dir_confirm" =~ ^[Yy]$ ]]; then
        if [ -d "$HYSTERIA_CERT_DIR" ]; then
            info "正在删除 Hysteria2 证书目录..."
            rm -rf "$HYSTERIA_CERT_DIR"
        fi
    else
        info "Hysteria2 证书目录 (${HYSTERIA_CERT_DIR}) 已保留。"
    fi''',
'''    read -rp "是否删除 Hysteria2 证书目录 ${HYSTERIA_CERT_DIR}? (y/N): " delete_cert_dir_confirm
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
    fi''',
'uninstall_singbox vless-tls cert')

# ========== 21. uninstall_all 清理 VLESS_TLS_CERT_DIR ==========
rep(
'''    info "删除证书目录..."
    rm -rf "$HYSTERIA_CERT_DIR"

    info "删除 sb 快捷命令与 install.sh..."''',
'''    info "删除证书目录..."
    rm -rf "$HYSTERIA_CERT_DIR"
    rm -rf "$VLESS_TLS_CERT_DIR"

    info "删除 sb 快捷命令与 install.sh..."''',
'uninstall_all vless-tls cert')

with open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("[OK] 所有改动已写入")
PY_EOF

bash -n "$SCRIPT_PATH" || { echo "[ERROR] 语法检查失败"; exit 1; }
echo "[SUCCESS] 语法检查通过"

# 同步到 sb 指向的副本
if [ -f /usr/local/bin/install.sh ]; then
    cp -f "$SCRIPT_PATH" /usr/local/bin/install.sh
    chmod 755 /usr/local/bin/install.sh
    echo "[INFO] 已同步到 /usr/local/bin/install.sh"
fi

echo ""
echo "[CHECK] 关键函数/变量:"
for k in "vless_branch_menu()" "install_vless_tls()" "generate_vless_tls_cert()" "NODE_VLESS_TLS_UUID" "NODE_VLESS_TLS_RELAY" "NODE_VLESS_TLS_CDN"; do
    if grep -qF "$k" "$SCRIPT_PATH"; then
        echo "  ✓ $k"
    else
        echo "  ✗ $k 缺失"
    fi
done

echo ""
echo "[DONE] 重新运行 sb，主菜单 1 现在是 VLESS 分支安装"
VLESS_FINAL_EOF
