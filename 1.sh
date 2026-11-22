bash << 'SOCKS5_EOF'
set -e

SCRIPT_PATH="/root/install.sh"
[ -f "$SCRIPT_PATH" ] || { echo "[ERROR] 脚本不存在: $SCRIPT_PATH"; exit 1; }
cp -a "$SCRIPT_PATH" "${SCRIPT_PATH}.bak.socks5.$(date +%Y%m%d_%H%M%S)"
echo "[INFO] 已备份"

python3 << 'PY_EOF'
import sys
path = "/root/install.sh"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

if 'NODE_SOCKS5_USER' in content:
    print("[WARN] 已存在 SOCKS5 补丁，跳过"); sys.exit(0)

def rep(old, new, tag):
    global content
    if old not in content:
        print(f"[ERROR] 未找到: {tag}"); sys.exit(1)
    content = content.replace(old, new, 1)

# 1. 变量声明
rep(
'''VLESS_TLS_CERT_DIR="/etc/sing-box/vless-tls"
VLESS_TLS_CERT_PEM="${VLESS_TLS_CERT_DIR}/cert.pem"
VLESS_TLS_CERT_KEY="${VLESS_TLS_CERT_DIR}/private.key"''',
'''VLESS_TLS_CERT_DIR="/etc/sing-box/vless-tls"
VLESS_TLS_CERT_PEM="${VLESS_TLS_CERT_DIR}/cert.pem"
VLESS_TLS_CERT_KEY="${VLESS_TLS_CERT_DIR}/private.key"

# SOCKS5 落地节点
declare -A NODE_SOCKS5_USER=()
declare -A NODE_SOCKS5_PASS=()
declare -A NODE_SOCKS5_RELAY=()''',
'变量声明')

# 2. load_persistent_info
rep(
'''                    CDN) NODE_VLESS_TLS_CDN["$port3"]="$value" ;;
                esac
                ;;
        esac''',
'''                    CDN) NODE_VLESS_TLS_CDN["$port3"]="$value" ;;
                esac
                ;;
            NODE_SOCKS5_*)
                local rest4="${key#NODE_SOCKS5_}"
                local port4="${rest4%%_*}"
                local field4="${rest4#*_}"
                case "$field4" in
                    USER) NODE_SOCKS5_USER["$port4"]="$value" ;;
                    PASS) NODE_SOCKS5_PASS["$port4"]="$value" ;;
                esac
                ;;
        esac''',
'load_persistent_info')

# 3. save_persistent_info
rep(
'''        echo "NODE_VLESS_TLS_${p}_CDN=\\"${NODE_VLESS_TLS_CDN[$p]:-}\\""
    done >> "$PERSISTENT_INFO_FILE"''',
'''        echo "NODE_VLESS_TLS_${p}_CDN=\\"${NODE_VLESS_TLS_CDN[$p]:-}\\""
    done >> "$PERSISTENT_INFO_FILE"
    for p in "${!NODE_SOCKS5_USER[@]}"; do
        echo "NODE_SOCKS5_${p}_USER=\\"${NODE_SOCKS5_USER[$p]}\\""
        echo "NODE_SOCKS5_${p}_PASS=\\"${NODE_SOCKS5_PASS[$p]:-}\\""
    done >> "$PERSISTENT_INFO_FILE"''',
'save_persistent_info')

# 4. create_config_json 签名
rep(
'''    local vtls_path="${13:-}"
    local vtls_svc="${14:-}"

    if [ -z "$SINGBOX_CMD" ]; then''',
'''    local vtls_path="${13:-}"
    local vtls_svc="${14:-}"
    local socks5_port="${15:-}"
    local socks5_user="${16:-}"
    local socks5_pass="${17:-}"

    if [ -z "$SINGBOX_CMD" ]; then''',
'create_config_json 签名')

# 5. create_config_json socks5 分支
rep(
'''    local _direct_ob
    case "${OUTBOUND_MODE:-both}" in
        v4) _direct_ob='{"type":"direct","tag":"direct","domain_resolver":{"server":"local","strategy":"ipv4_only"}}' ;;
        v6) _direct_ob='{"type":"direct","tag":"direct","domain_resolver":{"server":"local","strategy":"ipv6_only"}}' ;;
        *)  _direct_ob='{"type":"direct","tag":"direct"}' ;;
    esac
    local _ob="[${_direct_ob},{\\"type\\":\\"block\\",\\"tag\\":\\"block\\"}]"''',
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

    local _direct_ob
    case "${OUTBOUND_MODE:-both}" in
        v4) _direct_ob='{"type":"direct","tag":"direct","domain_resolver":{"server":"local","strategy":"ipv4_only"}}' ;;
        v6) _direct_ob='{"type":"direct","tag":"direct","domain_resolver":{"server":"local","strategy":"ipv6_only"}}' ;;
        *)  _direct_ob='{"type":"direct","tag":"direct"}' ;;
    esac
    local _ob="[${_direct_ob},{\\"type\\":\\"block\\",\\"tag\\":\\"block\\"}]"''',
'create_config_json socks5 分支')

# 6. display_and_store_config_info 显示块
rep(
'''    save_persistent_info
}

# --- Installation functions ---
install_hysteria2_reality() {''',
'''    if [[ "$mode" == "all" || "$mode" == "socks5" ]]; then
        local p
        for p in "${!NODE_SOCKS5_USER[@]}"; do
            local user="${NODE_SOCKS5_USER[$p]}"
            local pass="${NODE_SOCKS5_PASS[$p]:-}"
            echo -e "----------------------------------------------------"
            echo -e "${GREEN}${BOLD} SOCKS5 落地 (端口 ${p}) 配置信息:${NC}"
            echo -e "用户名: ${GREEN}${user}${NC}"
            echo -e "密码:   ${GREEN}${pass}${NC}"
            if [[ "$LINK_IP_MODE" == "4" || "$LINK_IP_MODE" == "both" ]] && [[ -n "$LAST_SERVER_IP4" ]]; then
                local h4
                h4=$(format_host_for_uri "$LAST_SERVER_IP4")
                echo -e "${CYAN}SOCKS5 链接(IPv4):${NC} ${GREEN}socks5://${user}:${pass}@${h4}:${p}#Socks5-${p}-${LAST_SERVER_IP4}${NC}"
            fi
            if [[ "$LINK_IP_MODE" == "6" || "$LINK_IP_MODE" == "both" ]] && [[ -n "$LAST_SERVER_IP6" ]]; then
                local h6
                h6=$(format_host_for_uri "$LAST_SERVER_IP6")
                echo -e "${CYAN}SOCKS5 链接(IPv6):${NC} ${GREEN}socks5://${user}:${pass}@${h6}:${p}#Socks5-${p}-${LAST_SERVER_IP6}${NC}"
            fi
            echo -e "${YELLOW}说明: 无 TLS 加密，仅适合服务器间中转/落地，不建议公网直连${NC}"
        done
    fi

    save_persistent_info
}

# --- Installation functions ---
install_hysteria2_reality() {''',
'display 显示块')

# 7. install_socks5 函数
rep(
'vless_branch_menu() {',
'''install_socks5() {
    info "开始安装 SOCKS5 落地节点 ..."
    install_singbox_core || return 1
    get_server_ips
    choose_link_ip_mode

    local port
    prompt_port "请输入 SOCKS5 监听端口" "1080" port both

    local user
    read -rp "用户名 [默认 socksuser]: " user
    user="${user:-socksuser}"
    if ! [[ "$user" =~ ^[a-zA-Z0-9_]{1,32}$ ]]; then
        error "用户名仅支持 1-32 位字母/数字/下划线"
        return 1
    fi

    local pass
    read -rp "密码 [留空自动生成]: " pass
    if [ -z "$pass" ]; then
        pass=$(openssl rand -hex 8)
        info "已生成密码: $pass"
    fi

    create_config_json "socks5" "" "" "" "" "" "" "" "" "" "" "" "" "" \\
        "$port" "$user" "$pass" || return 1

    NODE_SOCKS5_USER["$port"]="$user"
    NODE_SOCKS5_PASS["$port"]="$pass"

    create_systemd_service
    start_singbox_service || return 1
    install_script_shortcut || true

    success "SOCKS5 落地节点安装配置完成！"
    echo ""
    echo -e "${YELLOW}${BOLD}===== SOCKS5 使用说明 =====${NC}"
    echo -e "  客户端: address=VPS IP  port=${port}  username=${user}  password=${pass}"
    echo -e "  ${YELLOW}SOCKS5 明文协议，仅建议用于服务器间中转/自用落地，切勿直接暴露公网给不可信客户端${NC}"
    echo ""
    display_and_store_config_info "socks5"
}

vless_branch_menu() {''',
'install_socks5')

# 8. show_all_node_links 加 SOCKS5
rep(
'''        unset -f _build_vtls_link
    done
    echo "================================================"
}''',
'''        unset -f _build_vtls_link
    done
    for p in "${!NODE_SOCKS5_USER[@]}"; do
        local user="${NODE_SOCKS5_USER[$p]}"
        local pass="${NODE_SOCKS5_PASS[$p]:-}"
        echo ""
        echo "[SOCKS5 落地 - 端口 $p]"
        if [ -n "$LAST_SERVER_IP4" ]; then
            h4=$(format_host_for_uri "$LAST_SERVER_IP4")
            echo "IPv4: socks5://${user}:${pass}@${h4}:${p}#Socks5-${p}-${LAST_SERVER_IP4}"
        fi
        if [ -n "$LAST_SERVER_IP6" ]; then
            h6=$(format_host_for_uri "$LAST_SERVER_IP6")
            echo "IPv6: socks5://${user}:${pass}@${h6}:${p}#Socks5-${p}-${LAST_SERVER_IP6}"
        fi
    done
    echo "================================================"
}''',
'show_all_node_links')

# 9. delete_node 列表
rep(
'''    for p in "${!NODE_VLESS_TLS_UUID[@]}"; do
        echo "  vless-tls 端口 $p (${NODE_VLESS_TLS_TYPE[$p]:-})"
        any=true
    done
    $any || { warn "当前没有任何节点。"; return; }''',
'''    for p in "${!NODE_VLESS_TLS_UUID[@]}"; do
        echo "  vless-tls 端口 $p (${NODE_VLESS_TLS_TYPE[$p]:-})"
        any=true
    done
    for p in "${!NODE_SOCKS5_USER[@]}"; do
        echo "  socks5    端口 $p"
        any=true
    done
    $any || { warn "当前没有任何节点。"; return; }''',
'delete_node 列表')

# 10. delete_node unset
rep(
'''    if [ -n "${NODE_VLESS_TLS_UUID[$del_port]:-}" ]; then
        unset 'NODE_VLESS_TLS_UUID[$del_port]' 'NODE_VLESS_TLS_TYPE[$del_port]' \\
              'NODE_VLESS_TLS_SNI[$del_port]' 'NODE_VLESS_TLS_PATH[$del_port]' \\
              'NODE_VLESS_TLS_SVC[$del_port]' 'NODE_VLESS_TLS_RELAY[$del_port]'
        found=true
        info "已移除 vless-tls 端口 $del_port"
    fi
    if ! $found; then''',
'''    if [ -n "${NODE_VLESS_TLS_UUID[$del_port]:-}" ]; then
        unset 'NODE_VLESS_TLS_UUID[$del_port]' 'NODE_VLESS_TLS_TYPE[$del_port]' \\
              'NODE_VLESS_TLS_SNI[$del_port]' 'NODE_VLESS_TLS_PATH[$del_port]' \\
              'NODE_VLESS_TLS_SVC[$del_port]' 'NODE_VLESS_TLS_RELAY[$del_port]'
        found=true
        info "已移除 vless-tls 端口 $del_port"
    fi
    if [ -n "${NODE_SOCKS5_USER[$del_port]:-}" ]; then
        unset 'NODE_SOCKS5_USER[$del_port]' 'NODE_SOCKS5_PASS[$del_port]' 'NODE_SOCKS5_RELAY[$del_port]'
        found=true
        info "已移除 socks5 端口 $del_port"
    fi
    if ! $found; then''',
'delete_node unset')

# 11. delete_node jq
rep(
'''        jq --arg ht "hy2-in-${del_port}" --arg vt "vless-in-${del_port}" --arg vtt "vless-tls-in-${del_port}" \\
           '.inbounds |= map(select(.tag != $ht and .tag != $vt and .tag != $vtt))' \\
           "$SINGBOX_CONFIG_FILE" > "$SINGBOX_CONFIG_FILE.tmp" \\
           && mv "$SINGBOX_CONFIG_FILE.tmp" "$SINGBOX_CONFIG_FILE"''',
'''        jq --arg ht "hy2-in-${del_port}" --arg vt "vless-in-${del_port}" --arg vtt "vless-tls-in-${del_port}" --arg st "socks-in-${del_port}" \\
           '.inbounds |= map(select(.tag != $ht and .tag != $vt and .tag != $vtt and .tag != $st))' \\
           "$SINGBOX_CONFIG_FILE" > "$SINGBOX_CONFIG_FILE.tmp" \\
           && mv "$SINGBOX_CONFIG_FILE.tmp" "$SINGBOX_CONFIG_FILE"''',
'delete_node jq')

# 12. save_relays_to_file
rep(
'''        for p in "${!NODE_VLESS_TLS_RELAY[@]}"; do
            [ -z "${NODE_VLESS_TLS_UUID[$p]:-}" ] && continue
            echo "BIND|vless-tls|${p}|${NODE_VLESS_TLS_RELAY[$p]}"
        done
        local _r''',
'''        for p in "${!NODE_VLESS_TLS_RELAY[@]}"; do
            [ -z "${NODE_VLESS_TLS_UUID[$p]:-}" ] && continue
            echo "BIND|vless-tls|${p}|${NODE_VLESS_TLS_RELAY[$p]}"
        done
        for p in "${!NODE_SOCKS5_RELAY[@]}"; do
            [ -z "${NODE_SOCKS5_USER[$p]:-}" ] && continue
            echo "BIND|socks5|${p}|${NODE_SOCKS5_RELAY[$p]}"
        done
        local _r''',
'save_relays SOCKS5')

# 13. load_relays 清空
rep(
'''    NODE_HY2_RELAY=(); NODE_REALITY_RELAY=(); NODE_VLESS_TLS_RELAY=()
    DOMAIN_ROUTES=()''',
'''    NODE_HY2_RELAY=(); NODE_REALITY_RELAY=(); NODE_VLESS_TLS_RELAY=(); NODE_SOCKS5_RELAY=()
    DOMAIN_ROUTES=()''',
'load_relays 清空')

# 14. load_relays BIND
rep(
'''                    vless-tls) NODE_VLESS_TLS_RELAY["$b"]="$c" ;;
                esac''',
'''                    vless-tls) NODE_VLESS_TLS_RELAY["$b"]="$c" ;;
                    socks5) NODE_SOCKS5_RELAY["$b"]="$c" ;;
                esac''',
'load_relays BIND')

# 15. _relay_build_rules all 展开
rep(
'''            for _p in "${!NODE_VLESS_TLS_UUID[@]}"; do _inbounds+=("vless-tls-in-${_p}"); done
        else''',
'''            for _p in "${!NODE_VLESS_TLS_UUID[@]}"; do _inbounds+=("vless-tls-in-${_p}"); done
            for _p in "${!NODE_SOCKS5_USER[@]}"; do _inbounds+=("socks-in-${_p}"); done
        else''',
'_relay_build_rules all')

# 16. _relay_build_rules 端口级
rep(
'''    for _p in "${!NODE_VLESS_TLS_RELAY[@]}"; do
        _rt="${NODE_VLESS_TLS_RELAY[$_p]}"
        if [ -z "$_rt" ] || [ "$_rt" == "direct" ]; then continue; fi
        if [ -z "${RELAY_JSON[$_rt]:-}" ]; then continue; fi
        _tag="vless-tls-in-${_p}"
        _relay_check_inb "$_tag" || continue
        rules=$(jq --arg inb "$_tag" --arg out "$_rt" '. + [{inbound: [$inb], outbound: $out}]' <<< "$rules")
    done

    unset -f _relay_check_inb''',
'''    for _p in "${!NODE_VLESS_TLS_RELAY[@]}"; do
        _rt="${NODE_VLESS_TLS_RELAY[$_p]}"
        if [ -z "$_rt" ] || [ "$_rt" == "direct" ]; then continue; fi
        if [ -z "${RELAY_JSON[$_rt]:-}" ]; then continue; fi
        _tag="vless-tls-in-${_p}"
        _relay_check_inb "$_tag" || continue
        rules=$(jq --arg inb "$_tag" --arg out "$_rt" '. + [{inbound: [$inb], outbound: $out}]' <<< "$rules")
    done
    for _p in "${!NODE_SOCKS5_RELAY[@]}"; do
        _rt="${NODE_SOCKS5_RELAY[$_p]}"
        if [ -z "$_rt" ] || [ "$_rt" == "direct" ]; then continue; fi
        if [ -z "${RELAY_JSON[$_rt]:-}" ]; then continue; fi
        _tag="socks-in-${_p}"
        _relay_check_inb "$_tag" || continue
        rules=$(jq --arg inb "$_tag" --arg out "$_rt" '. + [{inbound: [$inb], outbound: $out}]' <<< "$rules")
    done

    unset -f _relay_check_inb''',
'_relay_build_rules 端口级')

# 17. relay_list_nodes_status
rep(
'''    for p in "${!NODE_VLESS_TLS_UUID[@]}"; do
        desc="直连"; rt="${NODE_VLESS_TLS_RELAY[$p]:-}"
        [ -n "$rt" ] && [ "$rt" != "direct" ] && desc="中转: ${RELAY_DESC[$rt]:-$rt}"
        echo "  vless-tls 端口 $p → $desc"; any=true
    done
    $any || echo "  （无节点）"''',
'''    for p in "${!NODE_VLESS_TLS_UUID[@]}"; do
        desc="直连"; rt="${NODE_VLESS_TLS_RELAY[$p]:-}"
        [ -n "$rt" ] && [ "$rt" != "direct" ] && desc="中转: ${RELAY_DESC[$rt]:-$rt}"
        echo "  vless-tls 端口 $p → $desc"; any=true
    done
    for p in "${!NODE_SOCKS5_USER[@]}"; do
        desc="直连"; rt="${NODE_SOCKS5_RELAY[$p]:-}"
        [ -n "$rt" ] && [ "$rt" != "direct" ] && desc="中转: ${RELAY_DESC[$rt]:-$rt}"
        echo "  socks5    端口 $p → $desc"; any=true
    done
    $any || echo "  （无节点）"''',
'relay_list_nodes_status')

# 18. _relay_bind_ui 列表
rep(
'''    for p in "${!NODE_VLESS_TLS_UUID[@]}"; do
        echo "  [$i] vless-tls 端口 $p"
        ports+=("$p"); types+=("vless-tls"); i=$((i+1))
    done
    if [ ${#ports[@]} -eq 0 ]; then''',
'''    for p in "${!NODE_VLESS_TLS_UUID[@]}"; do
        echo "  [$i] vless-tls 端口 $p"
        ports+=("$p"); types+=("vless-tls"); i=$((i+1))
    done
    for p in "${!NODE_SOCKS5_USER[@]}"; do
        echo "  [$i] socks5 端口 $p"
        ports+=("$p"); types+=("socks5"); i=$((i+1))
    done
    if [ ${#ports[@]} -eq 0 ]; then''',
'_relay_bind_ui 列表')

# 19. _relay_bind_ui 绑定
rep(
'''    elif [ "$sel_type" == "vless-tls" ]; then
        NODE_VLESS_TLS_RELAY["$sel_port"]="$sel_tag"
    fi
    success "已绑定: $sel_type 端口 $sel_port → ${RELAY_DESC[$sel_tag]}"''',
'''    elif [ "$sel_type" == "vless-tls" ]; then
        NODE_VLESS_TLS_RELAY["$sel_port"]="$sel_tag"
    elif [ "$sel_type" == "socks5" ]; then
        NODE_SOCKS5_RELAY["$sel_port"]="$sel_tag"
    fi
    success "已绑定: $sel_type 端口 $sel_port → ${RELAY_DESC[$sel_tag]}"''',
'_relay_bind_ui 绑定')

# 20. _relay_unbind_ui
rep(
'''    if [ -n "${NODE_VLESS_TLS_RELAY[$up]:-}" ]; then unset "NODE_VLESS_TLS_RELAY[$up]"; found=1; fi
    if [ $found -eq 0 ]; then''',
'''    if [ -n "${NODE_VLESS_TLS_RELAY[$up]:-}" ]; then unset "NODE_VLESS_TLS_RELAY[$up]"; found=1; fi
    if [ -n "${NODE_SOCKS5_RELAY[$up]:-}" ]; then unset "NODE_SOCKS5_RELAY[$up]"; found=1; fi
    if [ $found -eq 0 ]; then''',
'_relay_unbind_ui')

# 21. _relay_delete_ui
rep(
'''    for p in "${!NODE_VLESS_TLS_RELAY[@]}"; do
        [ "${NODE_VLESS_TLS_RELAY[$p]}" == "$dt" ] && unset "NODE_VLESS_TLS_RELAY[$p]"
    done
    # 清除该中转的域名分流规则''',
'''    for p in "${!NODE_VLESS_TLS_RELAY[@]}"; do
        [ "${NODE_VLESS_TLS_RELAY[$p]}" == "$dt" ] && unset "NODE_VLESS_TLS_RELAY[$p]"
    done
    for p in "${!NODE_SOCKS5_RELAY[@]}"; do
        [ "${NODE_SOCKS5_RELAY[$p]}" == "$dt" ] && unset "NODE_SOCKS5_RELAY[$p]"
    done
    # 清除该中转的域名分流规则''',
'_relay_delete_ui')

# 22. _domain_route_add_ui
rep(
'''    for p in "${!NODE_VLESS_TLS_UUID[@]}"; do
        inb_list+=("vless-tls-in-${p}"); inb_show+=("vless-tls 端口 $p"); i=$((i+1))
    done
    echo ""''',
'''    for p in "${!NODE_VLESS_TLS_UUID[@]}"; do
        inb_list+=("vless-tls-in-${p}"); inb_show+=("vless-tls 端口 $p"); i=$((i+1))
    done
    for p in "${!NODE_SOCKS5_USER[@]}"; do
        inb_list+=("socks-in-${p}"); inb_show+=("socks5 端口 $p"); i=$((i+1))
    done
    echo ""''',
'_domain_route_add_ui')

# 23. 主菜单加 19
rep(
'''    echo "  18. 出站 IP 模式（v4/v6/双栈，入站固定双栈）"
    echo "  0.  退出脚本"''',
'''    echo "  18. 出站 IP 模式（v4/v6/双栈，入站固定双栈）"
    echo "  19. 安装 SOCKS5 落地节点（带认证，明文协议，仅中转/落地用）"
    echo "  0.  退出脚本"''',
'菜单 19')

# 24. read 提示
rep(
'    read -rp "请输入选项 [0-16]: " choice',
'    read -rp "请输入选项 [0-19]: " choice',
'read 提示')

# 25. case 19
rep(
'        18) io_mode_menu ;;',
'        18) io_mode_menu ;;\n        19) install_socks5 ;;',
'case 19')

# 26. 错误提示
rep(
'        *) error "无效选项，请输入 0 到 16 之间的数字。" ;;',
'        *) error "无效选项，请输入 0 到 19 之间的数字。" ;;',
'错误提示')

with open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("[OK] SOCKS5 全部 26 处改动完成")
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
for k in "install_socks5()" "NODE_SOCKS5_USER" "NODE_SOCKS5_PASS" "NODE_SOCKS5_RELAY"; do
    if grep -qF "$k" "$SCRIPT_PATH"; then echo "  ✓ $k"; else echo "  ✗ $k"; fi
done

echo ""
echo "[DONE] sb → 菜单 19 测试 SOCKS5 落地节点"
SOCKS5_EOF
