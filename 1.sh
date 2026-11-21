bash << 'CDN_SIMPLE_EOF'
set -e

SCRIPT_PATH="/root/install.sh"
cp -a "$SCRIPT_PATH" "${SCRIPT_PATH}.bak.cdnsimple.$(date +%s)"

python3 << 'PY_EOF'
import sys
path = "/root/install.sh"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

def rep(old, new, tag):
    global content
    if old not in content:
        print(f"[ERROR] 未找到: {tag}"); sys.exit(1)
    content = content.replace(old, new, 1)

# ========== 1. 替换 install_vless_tls 的交互段（去 CDN） ==========
rep(
'''    local port
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
        read -rp "CDN 入口域名 (如 cdn.example.com): " cdn_domain
        if is_valid_domain "$cdn_domain"; then
            cdn="$cdn_domain"
            echo ""
            echo "机头域名（Host 头）：客户端发给 CDN、CDN 回源给 VPS 时携带的 Host 值"
            echo "  默认 = CDN 域名 ${cdn}（推荐，直接回车）"
            echo "  也可填源站域名或伪装域名（如 www.example.com）"
            local cdn_host
            read -rp "机头域名 [默认 ${cdn}]: " cdn_host
            cdn_host="${cdn_host:-$cdn}"
            if is_valid_domain "$cdn_host"; then
                host="$cdn_host"
            else
                warn "机头域名无效，使用 CDN 域名"
                host="$cdn"
            fi
        else
            warn "CDN 域名无效，忽略"
        fi
    fi
''',
'''    echo ""
    echo "CF 支持端口（客户端可通过这些端口走 CDN，建议从下面选一个）:"
    echo "  443系: 443 2053 2083 2087 2096 8443"
    echo "  80系 : 80 8080 8880 2052 2082 2086 2095"
    echo "  提示: 选上述端口，客户端改 address/port 即可走 CDN；也可选任意端口仅直连"
    echo ""
    local port
    prompt_port "请输入 VLESS+TLS 监听端口" "8444" port tcp

    local sni
    prompt_domain "请输入 SNI / 证书 CN" "$DEFAULT_REALITY_SNI" sni

    local path="" host="" svc=""
    if [[ "$transport" == "ws" || "$transport" == "httpupgrade" ]]; then
        read -rp "路径 [默认 /vless]: " path
        path="${path:-/vless}"
        host="$sni"
    elif [[ "$transport" == "grpc" ]]; then
        read -rp "gRPC serviceName [默认 grpc]: " svc
        svc="${svc:-grpc}"
    fi

    local cdn=""
''',
'install_vless_tls 交互简化')

# ========== 2. 替换成功提示（去掉 CDN 说明） ==========
rep(
'''    success "VLESS + TLS ($transport) 安装配置完成！"
    if [ -n "$cdn" ]; then
        echo ""
        echo -e "${YELLOW}${BOLD}===== 套 CDN 场景说明 =====${NC}"
        echo -e "  ${CYAN}VPS 源站端口${NC}（sing-box 监听）: ${GREEN}${port}${NC}"
        echo -e "  ${CYAN}CDN 入口域名${NC}: ${GREEN}${cdn}${NC}"
        echo -e "  ${CYAN}客户端连接端口${NC}: ${GREEN}443${NC}（CDN 入口，不是源站端口）"
        echo -e "  ${CYAN}机头域名 (Host)${NC}: ${GREEN}${host}${NC}"
        echo ""
        echo -e "${GREEN}请在 CDN 面板（如 Cloudflare）配置：${NC}"
        echo -e "  1. DNS: ${cdn} → ${LAST_SERVER_IP4:-你的VPS IP}（开启代理/橙色云）"
        echo -e "  2. 源站端口: ${port}（CDN 回源使用此端口）"
        echo -e "  3. SSL/TLS 模式: Full 或 Full (strict)"
        echo -e "  4. WebSocket: 默认开启即可"
        echo ""
        echo -e "${GREEN}客户端导入参数：${NC}"
        echo -e "  address=${cdn}  port=443  sni=${cdn}  host=${host}  path=${path:-（gRPC 无需 path）}"
        echo -e "${YELLOW}提示：源站端口 ${port} 只在 CDN 面板填写，客户端不要直接用这个端口${NC}"
    fi
    display_and_store_config_info "vless_tls"
}
''',
'''    success "VLESS + TLS ($transport) 安装配置完成！"
    echo ""
    echo -e "${YELLOW}${BOLD}===== 是否走 CDN（客户端自行切换） =====${NC}"
    echo -e "  ${CYAN}直连（默认链接）${NC}: address=VPS IP, port=${port}"
    echo -e "  ${CYAN}走 CDN${NC}: 客户端把链接里的 address 改成 CF 优选 IP/域名"
    echo -e "         port 改成 443/2053/2083/2087/2096/8443（或 80系）"
    echo -e "         sni/host/path 保持不变即可"
    echo -e "  ${YELLOW}前提: VPS 监听端口为 ${port}，请确保 CF 面板回源端口与之一致（或套 CDN 时把客户端 port 设为 CF 支持的端口）${NC}"
    echo ""
    display_and_store_config_info "vless_tls"
}
''',
'install_vless_tls 成功提示简化')

# ========== 3. 简化 gen_vless_tls_link ==========
rep(
'''    gen_vless_tls_link() {
        local port="$1"
        local ip="$2"
        local uuid="${NODE_VLESS_TLS_UUID[$port]}"
        local tp="${NODE_VLESS_TLS_TYPE[$port]}"
        local sni="${NODE_VLESS_TLS_SNI[$port]}"
        local path="${NODE_VLESS_TLS_PATH[$port]:-}"
        local svc="${NODE_VLESS_TLS_SVC[$port]:-}"
        local cdn="${NODE_VLESS_TLS_CDN[$port]:-}"
        local host_header="${NODE_VLESS_TLS_HOST[$port]:-}"
        local addr="$ip"
        local link_port="$port"
        local link_sni="$sni"
        local allow_insecure="1"
        if [ -n "$cdn" ]; then
            addr="$cdn"
            link_port="443"
            link_sni="$cdn"
            allow_insecure="0"
            [ -z "$host_header" ] && host_header="$cdn"
        else
            [ -z "$host_header" ] && host_header="$sni"
        fi
        local h
        h=$(format_host_for_uri "$addr")
        local link="vless://${uuid}@${h}:${link_port}?security=tls&sni=${link_sni}&fp=chrome&allowInsecure=${allow_insecure}&type=${tp}"
        if [[ "$tp" == "ws" || "$tp" == "httpupgrade" ]]; then
            link="${link}&path=${path}&host=${host_header}"
        elif [[ "$tp" == "grpc" ]]; then
            link="${link}&serviceName=${svc}"
        fi
        echo "${link}#VLESS-TLS-${port}-${addr}"
    }
''',
'''    gen_vless_tls_link() {
        local port="$1"
        local ip="$2"
        local uuid="${NODE_VLESS_TLS_UUID[$port]}"
        local tp="${NODE_VLESS_TLS_TYPE[$port]}"
        local sni="${NODE_VLESS_TLS_SNI[$port]}"
        local path="${NODE_VLESS_TLS_PATH[$port]:-}"
        local svc="${NODE_VLESS_TLS_SVC[$port]:-}"
        local h
        h=$(format_host_for_uri "$ip")
        local link="vless://${uuid}@${h}:${port}?security=tls&sni=${sni}&fp=chrome&allowInsecure=1&type=${tp}"
        if [[ "$tp" == "ws" || "$tp" == "httpupgrade" ]]; then
            link="${link}&path=${path}&host=${sni}"
        elif [[ "$tp" == "grpc" ]]; then
            link="${link}&serviceName=${svc}"
        fi
        echo "${link}#VLESS-TLS-${port}-${ip}"
    }
''',
'gen_vless_tls_link 简化')

# ========== 4. display_and_store_config_info 的 VLESS+TLS 显示块简化 ==========
rep(
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
''',
'''    if [[ "$mode" == "all" || "$mode" == "vless_tls" ]]; then
        local p
        for p in "${!NODE_VLESS_TLS_UUID[@]}"; do
            local tp="${NODE_VLESS_TLS_TYPE[$p]:-ws}"
            echo -e "----------------------------------------------------"
            echo -e "${GREEN}${BOLD} VLESS+TLS (端口 ${p}, ${tp}) 配置信息:${NC}"
            echo -e "UUID: ${GREEN}${NODE_VLESS_TLS_UUID[$p]}${NC}"
            echo -e "SNI: ${GREEN}${NODE_VLESS_TLS_SNI[$p]:-}${NC}   Type: ${GREEN}${tp}${NC}"
            [[ -n "${NODE_VLESS_TLS_PATH[$p]:-}" ]] && echo -e "Path: ${GREEN}${NODE_VLESS_TLS_PATH[$p]}${NC}"
            [[ -n "${NODE_VLESS_TLS_SVC[$p]:-}" ]] && echo -e "ServiceName: ${GREEN}${NODE_VLESS_TLS_SVC[$p]}${NC}"
            if [[ "$LINK_IP_MODE" == "4" || "$LINK_IP_MODE" == "both" ]] && [[ -n "$LAST_SERVER_IP4" ]]; then
                local link
                link=$(gen_vless_tls_link "$p" "$LAST_SERVER_IP4")
                echo -e "${CYAN}VLESS+TLS 导入链接(IPv4直连):${NC} ${GREEN}${link}${NC}"
                $qrencode_is_ready && command -v qrencode &>/dev/null && { echo "二维码:"; qrencode -t ANSIUTF8 "$link"; }
            fi
            if [[ "$LINK_IP_MODE" == "6" || "$LINK_IP_MODE" == "both" ]] && [[ -n "$LAST_SERVER_IP6" ]]; then
                local link6
                link6=$(gen_vless_tls_link "$p" "$LAST_SERVER_IP6")
                echo -e "${CYAN}VLESS+TLS 导入链接(IPv6直连):${NC} ${GREEN}${link6}${NC}"
                $qrencode_is_ready && command -v qrencode &>/dev/null && { echo "二维码:"; qrencode -t ANSIUTF8 "$link6"; }
            fi
            echo -e "${YELLOW}想走 CDN？客户端把上面链接的 address 改成 CF 优选 IP/域名、port 改成 443/2053/2083/2087/2096/8443，sni/host/path 不动即可${NC}"
        done
    fi
''',
'display VLESS+TLS 显示简化')

# ========== 5. show_all_node_links 的 VLESS+TLS 部分简化 ==========
rep(
'''    for p in "${!NODE_VLESS_TLS_UUID[@]}"; do
        local uuid="${NODE_VLESS_TLS_UUID[$p]}"
        local tp="${NODE_VLESS_TLS_TYPE[$p]:-ws}"
        local sni="${NODE_VLESS_TLS_SNI[$p]}"
        local path="${NODE_VLESS_TLS_PATH[$p]:-}"
        local svc="${NODE_VLESS_TLS_SVC[$p]:-}"
        local cdn="${NODE_VLESS_TLS_CDN[$p]:-}"
        echo ""
        echo "[VLESS+TLS (${tp}) - 端口 $p]"
        local host_header="${NODE_VLESS_TLS_HOST[$p]:-}"
        [ -z "$host_header" ] && host_header="$sni"
        _build_link() {
            local addr="$1" link_port="$2" link_sni="$3" ai="$4" hh="$5"
            local l="vless://${uuid}@${addr}:${link_port}?security=tls&sni=${link_sni}&fp=chrome&allowInsecure=${ai}&type=${tp}"
            if [[ "$tp" == "ws" || "$tp" == "httpupgrade" ]]; then
                l="${l}&path=${path}&host=${hh}"
            elif [[ "$tp" == "grpc" ]]; then
                l="${l}&serviceName=${svc}"
            fi
            echo "${l}#VLESS-TLS-${p}-${addr}"
        }
        if [ -n "$cdn" ]; then
            echo "CDN: $(_build_link "$cdn" "443" "$cdn" "0" "$host_header")"
        else
            if [ -n "$LAST_SERVER_IP4" ]; then
                h4=$(format_host_for_uri "$LAST_SERVER_IP4")
                echo "IPv4: $(_build_link "$h4" "$p" "$sni" "1" "$host_header")"
            fi
            if [ -n "$LAST_SERVER_IP6" ]; then
                h6=$(format_host_for_uri "$LAST_SERVER_IP6")
                echo "IPv6: $(_build_link "$h6" "$p" "$sni" "1" "$host_header")"
            fi
        fi
        unset -f _build_link
    done
''',
'''    for p in "${!NODE_VLESS_TLS_UUID[@]}"; do
        local uuid="${NODE_VLESS_TLS_UUID[$p]}"
        local tp="${NODE_VLESS_TLS_TYPE[$p]:-ws}"
        local sni="${NODE_VLESS_TLS_SNI[$p]}"
        local path="${NODE_VLESS_TLS_PATH[$p]:-}"
        local svc="${NODE_VLESS_TLS_SVC[$p]:-}"
        echo ""
        echo "[VLESS+TLS (${tp}) - 端口 $p]"
        _build_link() {
            local addr="$1" lp="$2"
            local l="vless://${uuid}@${addr}:${lp}?security=tls&sni=${sni}&fp=chrome&allowInsecure=1&type=${tp}"
            if [[ "$tp" == "ws" || "$tp" == "httpupgrade" ]]; then
                l="${l}&path=${path}&host=${sni}"
            elif [[ "$tp" == "grpc" ]]; then
                l="${l}&serviceName=${svc}"
            fi
            echo "${l}#VLESS-TLS-${p}-${addr}"
        }
        if [ -n "$LAST_SERVER_IP4" ]; then
            h4=$(format_host_for_uri "$LAST_SERVER_IP4")
            echo "IPv4: $(_build_link "$h4" "$p")"
        fi
        if [ -n "$LAST_SERVER_IP6" ]; then
            h6=$(format_host_for_uri "$LAST_SERVER_IP6")
            echo "IPv6: $(_build_link "$h6" "$p")"
        fi
        unset -f _build_link
    done
''',
'show_all_node_links 简化')

# ========== 6. create_config_json vless_tls 分支：transport 不设 headers ==========
rep(
'''                + (if $ttype == "ws" then
                    {transport: {type: "ws", path: $tpath, headers: {Host: $thost}}}
                   elif $ttype == "httpupgrade" then
                    {transport: {type: "httpupgrade", path: $tpath, headers: {Host: $thost}}}
                   elif $ttype == "grpc" then
                    {transport: {type: "grpc", service_name: $tsvc}}
                   else {} end)
''',
'''                + (if $ttype == "ws" then
                    {transport: {type: "ws", path: $tpath}}
                   elif $ttype == "httpupgrade" then
                    {transport: {type: "httpupgrade", path: $tpath}}
                   elif $ttype == "grpc" then
                    {transport: {type: "grpc", service_name: $tsvc}}
                   else {} end)
''',
'create_config_json transport 去 headers')

with open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("[OK] 套 CDN 逻辑已彻底简化：VPS 不校验 Host，链接只需改 address/port")
PY_EOF

bash -n "$SCRIPT_PATH" && echo "[SUCCESS] 语法检查通过"
if [ -f /usr/local/bin/install.sh ]; then
    cp -f "$SCRIPT_PATH" /usr/local/bin/install.sh
    chmod 755 /usr/local/bin/install.sh
    echo "[INFO] 已同步到 /usr/local/bin/install.sh"
fi
CDN_SIMPLE_EOF
