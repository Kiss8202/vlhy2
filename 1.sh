bash << 'ANYTLS_EOF'
set -e

SCRIPT_PATH="/root/install.sh"
[ -f "$SCRIPT_PATH" ] || { echo "[ERROR] 脚本不存在: $SCRIPT_PATH"; exit 1; }
cp -a "$SCRIPT_PATH" "${SCRIPT_PATH}.bak.anytls.$(date +%Y%m%d_%H%M%S)"
echo "[INFO] 已备份"

python3 << 'PY_EOF'
import sys
path = "/root/install.sh"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

if 'NODE_ANYTLS_PASSWORD' in content:
    print("[WARN] 已存在 AnyTLS 补丁，跳过"); sys.exit(0)

def rep(old, new, tag):
    global content
    if old not in content:
        print(f"[ERROR] 未找到: {tag}"); sys.exit(1)
    content = content.replace(old, new, 1)

# ========== 1. 变量声明 ==========
rep(
'''# SOCKS5 落地节点
declare -A NODE_SOCKS5_USER=()
declare -A NODE_SOCKS5_PASS=()
declare -A NODE_SOCKS5_RELAY=()''',
'''# SOCKS5 落地节点
declare -A NODE_SOCKS5_USER=()
declare -A NODE_SOCKS5_PASS=()
declare -A NODE_SOCKS5_RELAY=()

# AnyTLS 节点
declare -A NODE_ANYTLS_PASSWORD=()
declare -A NODE_ANYTLS_SNI=()
declare -A NODE_ANYTLS_RELAY=()
ANYTLS_CERT_DIR="/etc/sing-box/anytls"
ANYTLS_CERT_PEM="${ANYTLS_CERT_DIR}/cert.pem"
ANYTLS_CERT_KEY="${ANYTLS_CERT_DIR}/private.key"''',
'变量声明')

# ========== 2. load_persistent_info ==========
rep(
'''                    PASS) NODE_SOCKS5_PASS["$port4"]="$value" ;;
                esac
                ;;
        esac''',
'''                    PASS) NODE_SOCKS5_PASS["$port4"]="$value" ;;
                esac
                ;;
            NODE_ANYTLS_*)
                local rest5="${key#NODE_ANYTLS_}"
                local port5="${rest5%%_*}"
                local field5="${rest5#*_}"
                case "$field5" in
                    PASSWORD) NODE_ANYTLS_PASSWORD["$port5"]="$value" ;;
                    SNI) NODE_ANYTLS_SNI["$port5"]="$value" ;;
                esac
                ;;
        esac''',
'load_persistent_info')

# ========== 3. save_persistent_info ==========
rep(
'''    for p in "${!NODE_SOCKS5_USER[@]}"; do
        echo "NODE_SOCKS5_${p}_USER=\\"${NODE_SOCKS5_USER[$p]}\\""
        echo "NODE_SOCKS5_${p}_PASS=\\"${NODE_SOCKS5_PASS[$p]:-}\\""
    done >> "$PERSISTENT_INFO_FILE"''',
'''    for p in "${!NODE_SOCKS5_USER[@]}"; do
        echo "NODE_SOCKS5_${p}_USER=\\"${NODE_SOCKS5_USER[$p]}\\""
        echo "NODE_SOCKS5_${p}_PASS=\\"${NODE_SOCKS5_PASS[$p]:-}\\""
    done >> "$PERSISTENT_INFO_FILE"
    for p in "${!NODE_ANYTLS_PASSWORD[@]}"; do
        echo "NODE_ANYTLS_${p}_PASSWORD=\\"${NODE_ANYTLS_PASSWORD[$p]}\\""
        echo "NODE_ANYTLS_${p}_SNI=\\"${NODE_ANYTLS_SNI[$p]:-}\\""
    done >> "$PERSISTENT_INFO_FILE"''',
'save_persistent_info')

# ========== 4. create_config_json：签名 + anytls 分支 ==========
rep(
'''    local socks5_port="${15:-}"
    local socks5_user="${16:-}"
    local socks5_pass="${17:-}"''',
'''    local socks5_port="${15:-}"
    local socks5_user="${16:-}"
    local socks5_pass="${17:-}"
    local anytls_port="${18:-}"
    local anytls_password="${19:-}"
    local anytls_sni="${20:-}"''',
'create_config_json 签名')

rep(
'''    if [ "$mode" == "socks5" ]; then
        local socks_tag="socks-in-${socks5_port}"
        existing_inbounds=$(jq --arg tag "$socks_tag" 'map(select(.tag != $tag))' <<< "$existing_inbounds")
        existing_inbounds=$(jq --argjson port "$socks5_port" \\
            --arg user "$socks5_user" \\
            --arg pass "$socks5_pass" \\
            --arg tag "$socks_tag" \\
            --arg listen "$listen_addr" \\
            '. + [{
                type: "socks",
                tag: $tag,
                listen: $listen,
                listen_port: $port,
                users: [{username: $user, password: $pass}]
            }]' <<< "$existing_inbounds")
    fi''',
'''    if [ "$mode" == "socks5" ]; then
        local socks_tag="socks-in-${socks5_port}"
        existing_inbounds=$(jq --arg tag "$socks_tag" 'map(select(.tag != $tag))' <<< "$existing_inbounds")
        existing_inbounds=$(jq --argjson port "$socks5_port" \\
            --arg user "$socks5_user" \\
            --arg pass "$socks5_pass" \\
            --arg tag "$socks_tag" \\
            --arg listen "$listen_addr" \\
            '. + [{
                type: "socks",
                tag: $tag,
                listen: $listen,
                listen_port: $port,
                users: [{username: $user, password: $pass}]
            }]' <<< "$existing_inbounds")
    fi

    if [ "$mode" == "anytls" ]; then
        local anytls_tag="anytls-in-${anytls_port}"
        existing_inbounds=$(jq --arg tag "$anytls_tag" 'map(select(.tag != $tag))' <<< "$existing_inbounds")
        existing_inbounds=$(jq --argjson port "$anytls_port" \\
            --arg password "$anytls_password" \\
            --arg sni "$anytls_sni" \\
            --arg cert "$ANYTLS_CERT_PEM" \\
            --arg key "$ANYTLS_CERT_KEY" \\
            --arg tag "$anytls_tag" \\
            --arg listen "$listen_addr" \\
            '. + [{
                type: "anytls",
                tag: $tag,
                listen: $listen,
                listen_port: $port,
                users: [{password: $password}],
                tls: {
                    enabled: true,
                    server_name: $sni,
                    certificate_path: $cert,
                    key_path: $key
                }
            }]' <<< "$existing_inbounds")
    fi''',
'create_config_json anytls 分支')

# ========== 5. generate_anytls_cert ==========
rep(
'get_vless_tls_cert_fp() {',
'''generate_anytls_cert() {
    local domain_cn="$1"
    if [ -f "$ANYTLS_CERT_PEM" ] && [ -f "$ANYTLS_CERT_KEY" ]; then
        local existing_cn
        existing_cn=$(openssl x509 -in "$ANYTLS_CERT_PEM" -noout -subject 2>/dev/null | sed -n 's/.*CN[[:space:]]*=[[:space:]]*\\([^,]*\\).*/\\1/p' || true)
        if [ "$existing_cn" == "$domain_cn" ]; then
            info "AnyTLS 证书 CN 匹配，复用现有证书。"
            return 0
        fi
        warn "AnyTLS 证书 CN ($existing_cn) 与目标 ($domain_cn) 不匹配，重新生成。"
    fi
    info "生成 AnyTLS 自签证书 (CN=${domain_cn})..."
    mkdir -p "$ANYTLS_CERT_DIR"
    chmod 700 "$ANYTLS_CERT_DIR"
    openssl ecparam -genkey -name prime256v1 -out "$ANYTLS_CERT_KEY"
    chmod 600 "$ANYTLS_CERT_KEY"
    if ! openssl req -new -x509 -days 3650 -key "$ANYTLS_CERT_KEY" -out "$ANYTLS_CERT_PEM" \\
        -subj "/CN=${domain_cn}" -addext "subjectAltName=DNS:${domain_cn}" 2>/dev/null; then
        warn "当前 OpenSSL 不支持 -addext，回退为仅含 CN 的证书..."
        openssl req -new -x509 -days 3650 -key "$ANYTLS_CERT_KEY" -out "$ANYTLS_CERT_PEM" -subj "/CN=${domain_cn}"
    fi
    chmod 600 "$ANYTLS_CERT_PEM"
    success "AnyTLS 自签证书生成成功。"
    info "证书: ${ANYTLS_CERT_PEM}"
    info "私钥: ${ANYTLS_CERT_KEY}"
}

get_vless_tls_cert_fp() {''',
'generate_anytls_cert')

# ========== 6. install_anytls ==========
rep(
'install_socks5() {',
'''install_anytls() {
    info "开始安装 AnyTLS ..."
    install_singbox_core || return 1
    get_server_ips
    choose_link_ip_mode

    local port
    prompt_port "请输入 AnyTLS 监听端口" "8445" port tcp

    local sni
    prompt_domain "请输入 SNI / 证书 CN" "$DEFAULT_REALITY_SNI" sni

    local password
    read -rp "密码 [留空自动生成]: " password
    if [ -z "$password" ]; then
        password=$(openssl rand -hex 16)
        info "已生成密码: $password"
    fi

    generate_anytls_cert "$sni" || return 1

    create_config_json "anytls" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" \\
        "$port" "$password" "$sni" || return 1

    NODE_ANYTLS_PASSWORD["$port"]="$password"
    NODE_ANYTLS_SNI["$port"]="$sni"

    create_systemd_service
    start_singbox_service || return 1

    success "AnyTLS 安装配置完成！"
    echo ""
    echo -e "${YELLOW}${BOLD}===== AnyTLS 使用说明 =====${NC}"
    echo -e "  客户端: address=VPS IP  port=${port}  password=${password}  sni=${sni}"
    echo -e "  AnyTLS 基于 TLS，客户端需信任证书或设置 insecure"
    echo ""
    display_and_store_config_info "anytls"
}

install_socks5() {''',
'install_anytls')

# ========== 7. 菜单：安装节点 ==========
rep(
'''        echo "  3. Hysteria2（UDP 高速）"
        echo "  4. SOCKS5 落地（明文协议，仅中转/落地用）"''',
'''        echo "  3. Hysteria2（UDP 高速）"
        echo "  4. SOCKS5 落地（明文协议，仅中转/落地用）"
        echo "  5. AnyTLS（TLS 伪装，补充协议）"''',
'install_node_menu 文案')

rep(
'''        case "$c" in
            1) install_reality_only ;;
            2) install_vless_tls ;;
            3) install_hysteria2_only ;;
            4) install_socks5 ;;
            0) return ;;''',
'''        case "$c" in
            1) install_reality_only ;;
            2) install_vless_tls ;;
            3) install_hysteria2_only ;;
            4) install_socks5 ;;
            5) install_anytls ;;
            0) return ;;''',
'install_node_menu case')

# ========== 8. display_and_store_config_info：AnyTLS 显示 ==========
rep(
'''    if [[ "$mode" == "all" || "$mode" == "socks5" ]]; then
        local p
        for p in "${!NODE_SOCKS5_USER[@]}"; do''',
'''    if [[ "$mode" == "all" || "$mode" == "anytls" ]]; then
        local p
        for p in "${!NODE_ANYTLS_PASSWORD[@]}"; do
            local password="${NODE_ANYTLS_PASSWORD[$p]}"
            local sni="${NODE_ANYTLS_SNI[$p]:-}"
            echo -e "----------------------------------------------------"
            echo -e "${GREEN}${BOLD} AnyTLS (端口 ${p}) 配置信息:${NC}"
            echo -e "密码: ${GREEN}${password}${NC}"
            echo -e "SNI: ${GREEN}${sni}${NC}"
            if [[ "$LINK_IP_MODE" == "4" || "$LINK_IP_MODE" == "both" ]] && [[ -n "$LAST_SERVER_IP4" ]]; then
                local h4
                h4=$(format_host_for_uri "$LAST_SERVER_IP4")
                echo -e "${CYAN}AnyTLS 链接(IPv4):${NC} ${GREEN}anytls://${password}@${h4}:${p}?sni=${sni}&insecure=1#AnyTLS-${p}-${LAST_SERVER_IP4}${NC}"
            fi
            if [[ "$LINK_IP_MODE" == "6" || "$LINK_IP_MODE" == "both" ]] && [[ -n "$LAST_SERVER_IP6" ]]; then
                local h6
                h6=$(format_host_for_uri "$LAST_SERVER_IP6")
                echo -e "${CYAN}AnyTLS 链接(IPv6):${NC} ${GREEN}anytls://${password}@${h6}:${p}?sni=${sni}&insecure=1#AnyTLS-${p}-${LAST_SERVER_IP6}${NC}"
            fi
        done
    fi

    if [[ "$mode" == "all" || "$mode" == "socks5" ]]; then
        local p
        for p in "${!NODE_SOCKS5_USER[@]}"; do''',
'display AnyTLS')

# ========== 9. show_all_node_links：AnyTLS ==========
rep(
'''    echo "================================================"
}

node_info_menu() {''',
'''    for p in "${!NODE_ANYTLS_PASSWORD[@]}"; do
        local password="${NODE_ANYTLS_PASSWORD[$p]}"
        local sni="${NODE_ANYTLS_SNI[$p]:-}"
        echo ""
        echo "[AnyTLS - 端口 $p]"
        if [ -n "$LAST_SERVER_IP4" ]; then
            h4=$(format_host_for_uri "$LAST_SERVER_IP4")
            echo "IPv4: anytls://${password}@${h4}:${p}?sni=${sni}&insecure=1#AnyTLS-${p}-${LAST_SERVER_IP4}"
        fi
        if [ -n "$LAST_SERVER_IP6" ]; then
            h6=$(format_host_for_uri "$LAST_SERVER_IP6")
            echo "IPv6: anytls://${password}@${h6}:${p}?sni=${sni}&insecure=1#AnyTLS-${p}-${LAST_SERVER_IP6}"
        fi
    done
    echo "================================================"
}

node_info_menu() {''',
'show_all_node_links AnyTLS')

# ========== 10. delete_node ==========
rep(
'''    for p in "${!NODE_SOCKS5_USER[@]}"; do
        echo "  socks5    端口 $p"
        any=true
    done
    $any || { warn "当前没有任何节点。"; return; }''',
'''    for p in "${!NODE_SOCKS5_USER[@]}"; do
        echo "  socks5    端口 $p"
        any=true
    done
    for p in "${!NODE_ANYTLS_PASSWORD[@]}"; do
        echo "  anytls    端口 $p"
        any=true
    done
    $any || { warn "当前没有任何节点。"; return; }''',
'delete_node 列表')

rep(
'''    if [ -n "${NODE_SOCKS5_USER[$del_port]:-}" ]; then
        unset 'NODE_SOCKS5_USER[$del_port]' 'NODE_SOCKS5_PASS[$del_port]' 'NODE_SOCKS5_RELAY[$del_port]'
        found=true
        info "已移除 socks5 端口 $del_port"
    fi
    if ! $found; then''',
'''    if [ -n "${NODE_SOCKS5_USER[$del_port]:-}" ]; then
        unset 'NODE_SOCKS5_USER[$del_port]' 'NODE_SOCKS5_PASS[$del_port]' 'NODE_SOCKS5_RELAY[$del_port]'
        found=true
        info "已移除 socks5 端口 $del_port"
    fi
    if [ -n "${NODE_ANYTLS_PASSWORD[$del_port]:-}" ]; then
        unset 'NODE_ANYTLS_PASSWORD[$del_port]' 'NODE_ANYTLS_SNI[$del_port]' 'NODE_ANYTLS_RELAY[$del_port]'
        found=true
        info "已移除 anytls 端口 $del_port"
    fi
    if ! $found; then''',
'delete_node unset')

rep(
'''        jq --arg ht "hy2-in-${del_port}" --arg vt "vless-in-${del_port}" --arg vtt "vless-tls-in-${del_port}" --arg st "socks-in-${del_port}" \\
           '.inbounds |= map(select(.tag != $ht and .tag != $vt and .tag != $vtt and .tag != $st))' \\
           "$SINGBOX_CONFIG_FILE" > "$SINGBOX_CONFIG_FILE.tmp" \\
           && mv "$SINGBOX_CONFIG_FILE.tmp" "$SINGBOX_CONFIG_FILE"''',
'''        jq --arg ht "hy2-in-${del_port}" --arg vt "vless-in-${del_port}" --arg vtt "vless-tls-in-${del_port}" --arg st "socks-in-${del_port}" --arg at "anytls-in-${del_port}" \\
           '.inbounds |= map(select(.tag != $ht and .tag != $vt and .tag != $vtt and .tag != $st and .tag != $at))' \\
           "$SINGBOX_CONFIG_FILE" > "$SINGBOX_CONFIG_FILE.tmp" \\
           && mv "$SINGBOX_CONFIG_FILE.tmp" "$SINGBOX_CONFIG_FILE"''',
'delete_node jq')

# ========== 11. 中转绑定相关 ==========
rep(
'''        for p in "${!NODE_SOCKS5_RELAY[@]}"; do
            [ -z "${NODE_SOCKS5_USER[$p]:-}" ] && continue
            echo "BIND|socks5|${p}|${NODE_SOCKS5_RELAY[$p]}"
        done
        local _r''',
'''        for p in "${!NODE_SOCKS5_RELAY[@]}"; do
            [ -z "${NODE_SOCKS5_USER[$p]:-}" ] && continue
            echo "BIND|socks5|${p}|${NODE_SOCKS5_RELAY[$p]}"
        done
        for p in "${!NODE_ANYTLS_RELAY[@]}"; do
            [ -z "${NODE_ANYTLS_PASSWORD[$p]:-}" ] && continue
            echo "BIND|anytls|${p}|${NODE_ANYTLS_RELAY[$p]}"
        done
        local _r''',
'save_relays AnyTLS')

rep(
'''                    socks5) NODE_SOCKS5_RELAY["$b"]="$c" ;;
                esac''',
'''                    socks5) NODE_SOCKS5_RELAY["$b"]="$c" ;;
                    anytls) NODE_ANYTLS_RELAY["$b"]="$c" ;;
                esac''',
'load_relays AnyTLS')

rep(
'''    NODE_HY2_RELAY=(); NODE_REALITY_RELAY=(); NODE_VLESS_TLS_RELAY=(); NODE_SOCKS5_RELAY=()
    DOMAIN_ROUTES=()''',
'''    NODE_HY2_RELAY=(); NODE_REALITY_RELAY=(); NODE_VLESS_TLS_RELAY=(); NODE_SOCKS5_RELAY=(); NODE_ANYTLS_RELAY=()
    DOMAIN_ROUTES=()''',
'load_relays 清空')

rep(
'''            for _p in "${!NODE_SOCKS5_USER[@]}"; do _inbounds+=("socks-in-${_p}"); done
        else''',
'''            for _p in "${!NODE_SOCKS5_USER[@]}"; do _inbounds+=("socks-in-${_p}"); done
            for _p in "${!NODE_ANYTLS_PASSWORD[@]}"; do _inbounds+=("anytls-in-${_p}"); done
        else''',
'_relay_build_rules all')

rep(
'''    for _p in "${!NODE_SOCKS5_RELAY[@]}"; do
        _rt="${NODE_SOCKS5_RELAY[$_p]}"
        if [ -z "$_rt" ] || [ "$_rt" == "direct" ]; then continue; fi
        if [ -z "${RELAY_JSON[$_rt]:-}" ]; then continue; fi
        _tag="socks-in-${_p}"
        _relay_check_inb "$_tag" || continue
        rules=$(jq --arg inb "$_tag" --arg out "$_rt" '. + [{inbound: [$inb], outbound: $out}]' <<< "$rules")
    done

    unset -f _relay_check_inb''',
'''    for _p in "${!NODE_SOCKS5_RELAY[@]}"; do
        _rt="${NODE_SOCKS5_RELAY[$_p]}"
        if [ -z "$_rt" ] || [ "$_rt" == "direct" ]; then continue; fi
        if [ -z "${RELAY_JSON[$_rt]:-}" ]; then continue; fi
        _tag="socks-in-${_p}"
        _relay_check_inb "$_tag" || continue
        rules=$(jq --arg inb "$_tag" --arg out "$_rt" '. + [{inbound: [$inb], outbound: $out}]' <<< "$rules")
    done
    for _p in "${!NODE_ANYTLS_RELAY[@]}"; do
        _rt="${NODE_ANYTLS_RELAY[$_p]}"
        if [ -z "$_rt" ] || [ "$_rt" == "direct" ]; then continue; fi
        if [ -z "${RELAY_JSON[$_rt]:-}" ]; then continue; fi
        _tag="anytls-in-${_p}"
        _relay_check_inb "$_tag" || continue
        rules=$(jq --arg inb "$_tag" --arg out "$_rt" '. + [{inbound: [$inb], outbound: $out}]' <<< "$rules")
    done

    unset -f _relay_check_inb''',
'_relay_build_rules 端口级')

rep(
'''    for p in "${!NODE_SOCKS5_USER[@]}"; do
        desc="直连"; rt="${NODE_SOCKS5_RELAY[$p]:-}"
        [ -n "$rt" ] && [ "$rt" != "direct" ] && desc="中转: ${RELAY_DESC[$rt]:-$rt}"
        echo "  socks5    端口 $p → $desc"; any=true
    done
    $any || echo "  （无节点）"''',
'''    for p in "${!NODE_SOCKS5_USER[@]}"; do
        desc="直连"; rt="${NODE_SOCKS5_RELAY[$p]:-}"
        [ -n "$rt" ] && [ "$rt" != "direct" ] && desc="中转: ${RELAY_DESC[$rt]:-$rt}"
        echo "  socks5    端口 $p → $desc"; any=true
    done
    for p in "${!NODE_ANYTLS_PASSWORD[@]}"; do
        desc="直连"; rt="${NODE_ANYTLS_RELAY[$p]:-}"
        [ -n "$rt" ] && [ "$rt" != "direct" ] && desc="中转: ${RELAY_DESC[$rt]:-$rt}"
        echo "  anytls    端口 $p → $desc"; any=true
    done
    $any || echo "  （无节点）"''',
'relay_list_nodes_status AnyTLS')

rep(
'''    for p in "${!NODE_SOCKS5_USER[@]}"; do
        echo "  [$i] socks5 端口 $p"
        ports+=("$p"); types+=("socks5"); i=$((i+1))
    done
    if [ ${#ports[@]} -eq 0 ]; then''',
'''    for p in "${!NODE_SOCKS5_USER[@]}"; do
        echo "  [$i] socks5 端口 $p"
        ports+=("$p"); types+=("socks5"); i=$((i+1))
    done
    for p in "${!NODE_ANYTLS_PASSWORD[@]}"; do
        echo "  [$i] anytls 端口 $p"
        ports+=("$p"); types+=("anytls"); i=$((i+1))
    done
    if [ ${#ports[@]} -eq 0 ]; then''',
'_relay_bind_ui 列表')

rep(
'''    elif [ "$sel_type" == "socks5" ]; then
        NODE_SOCKS5_RELAY["$sel_port"]="$sel_tag"
    fi
    success "已绑定: $sel_type 端口 $sel_port → ${RELAY_DESC[$sel_tag]}"''',
'''    elif [ "$sel_type" == "socks5" ]; then
        NODE_SOCKS5_RELAY["$sel_port"]="$sel_tag"
    elif [ "$sel_type" == "anytls" ]; then
        NODE_ANYTLS_RELAY["$sel_port"]="$sel_tag"
    fi
    success "已绑定: $sel_type 端口 $sel_port → ${RELAY_DESC[$sel_tag]}"''',
'_relay_bind_ui 绑定')

rep(
'''    if [ -n "${NODE_SOCKS5_RELAY[$up]:-}" ]; then unset "NODE_SOCKS5_RELAY[$up]"; found=1; fi
    if [ $found -eq 0 ]; then''',
'''    if [ -n "${NODE_SOCKS5_RELAY[$up]:-}" ]; then unset "NODE_SOCKS5_RELAY[$up]"; found=1; fi
    if [ -n "${NODE_ANYTLS_RELAY[$up]:-}" ]; then unset "NODE_ANYTLS_RELAY[$up]"; found=1; fi
    if [ $found -eq 0 ]; then''',
'_relay_unbind_ui')

rep(
'''    for p in "${!NODE_SOCKS5_RELAY[@]}"; do
        [ "${NODE_SOCKS5_RELAY[$p]}" == "$dt" ] && unset "NODE_SOCKS5_RELAY[$p]"
    done
    # 清除该中转的域名分流规则''',
'''    for p in "${!NODE_SOCKS5_RELAY[@]}"; do
        [ "${NODE_SOCKS5_RELAY[$p]}" == "$dt" ] && unset "NODE_SOCKS5_RELAY[$p]"
    done
    for p in "${!NODE_ANYTLS_RELAY[@]}"; do
        [ "${NODE_ANYTLS_RELAY[$p]}" == "$dt" ] && unset "NODE_ANYTLS_RELAY[$p]"
    done
    # 清除该中转的域名分流规则''',
'_relay_delete_ui')

rep(
'''    for p in "${!NODE_SOCKS5_USER[@]}"; do
        inb_list+=("socks-in-${p}"); inb_show+=("socks5 端口 $p"); i=$((i+1))
    done
    echo ""''',
'''    for p in "${!NODE_SOCKS5_USER[@]}"; do
        inb_list+=("socks-in-${p}"); inb_show+=("socks5 端口 $p"); i=$((i+1))
    done
    for p in "${!NODE_ANYTLS_PASSWORD[@]}"; do
        inb_list+=("anytls-in-${p}"); inb_show+=("anytls 端口 $p"); i=$((i+1))
    done
    echo ""''',
'_domain_route_add_ui')

# ========== 12. 卸载清理 ==========
rep(
'''    read -rp "是否删除 VLESS+TLS 证书目录 ${VLESS_TLS_CERT_DIR}? (y/N): " delete_vtls_cert_confirm''',
'''    read -rp "是否删除 AnyTLS 证书目录 ${ANYTLS_CERT_DIR}? (y/N): " delete_anytls_cert_confirm
    if [[ "$delete_anytls_cert_confirm" =~ ^[Yy]$ ]]; then
        if [ -d "$ANYTLS_CERT_DIR" ]; then
            info "正在删除 AnyTLS 证书目录..."
            rm -rf "$ANYTLS_CERT_DIR"
        fi
    else
        info "AnyTLS 证书目录 (${ANYTLS_CERT_DIR}) 已保留。"
    fi

    read -rp "是否删除 VLESS+TLS 证书目录 ${VLESS_TLS_CERT_DIR}? (y/N): " delete_vtls_cert_confirm''',
'uninstall_singbox AnyTLS cert')

rep(
'''    info "删除证书目录..."
    rm -rf "$HYSTERIA_CERT_DIR"
    rm -rf "$VLESS_TLS_CERT_DIR"''',
'''    info "删除证书目录..."
    rm -rf "$HYSTERIA_CERT_DIR"
    rm -rf "$VLESS_TLS_CERT_DIR"
    rm -rf "$ANYTLS_CERT_DIR"''',
'uninstall_all AnyTLS cert')

with open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("[OK] AnyTLS 全部改动完成")
PY_EOF

bash -n "$SCRIPT_PATH" || { echo "[ERROR] 语法检查失败"; exit 1; }
echo "[SUCCESS] 语法检查通过"

if [ -f /usr/local/bin/install.sh ]; then
    cp -f "$SCRIPT_PATH" /usr/local/bin/install.sh
    chmod 755 /usr/local/bin/install.sh
    echo "[INFO] 已同步"
fi

echo ""
echo "[CHECK] 关键函数/变量:"
for k in "install_anytls()" "generate_anytls_cert()" "NODE_ANYTLS_PASSWORD" "NODE_ANYTLS_RELAY"; do
    if grep -qF "$k" "$SCRIPT_PATH"; then echo "  ✓ $k"; else echo "  ✗ $k"; fi
done

echo ""
echo "[DONE] sb → 菜单 1 → 5 测试 AnyTLS"
ANYTLS_EOF
