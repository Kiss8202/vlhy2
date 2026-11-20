bash << 'PATCH_EOF'
set -e
command -v python3 >/dev/null 2>&1 || { echo "需要 python3"; exit 1; }

SCRIPT_PATH="/root/install.sh"
[ -f "$SCRIPT_PATH" ] || { echo "[ERROR] 文件不存在: $SCRIPT_PATH"; exit 1; }

BACKUP="${SCRIPT_PATH}.bak3.$(date +%Y%m%d_%H%M%S)"
cp -a "$SCRIPT_PATH" "$BACKUP"
echo "[INFO] 已备份: $BACKUP"

FUNCS_FILE=$(mktemp)
trap 'rm -f "$FUNCS_FILE"' EXIT
cat > "$FUNCS_FILE" << 'FUNC_EOF'
# ==================== 入站/出站 IP 模式 ====================
_io_mode_label() {
    case "$1" in
        v4) echo "仅 IPv4" ;;
        v6) echo "仅 IPv6" ;;
        *)  echo "双栈 (v4+v6)" ;;
    esac
}

apply_inbound_outbound_mode() {
    [ -f "$SINGBOX_CONFIG_FILE" ] || { warn "配置文件不存在，请先安装节点"; return 1; }
    [ -n "$SINGBOX_CMD" ] || { error "SINGBOX_CMD 未设置"; return 1; }
    local new_listen
    new_listen=$(get_listen_address)
    local new_direct
    case "${OUTBOUND_MODE:-both}" in
        v4) new_direct='{"type":"direct","tag":"direct","domain_strategy":"ipv4_only"}' ;;
        v6) new_direct='{"type":"direct","tag":"direct","domain_strategy":"ipv6_only"}' ;;
        *)  new_direct='{"type":"direct","tag":"direct"}' ;;
    esac
    local tmp
    tmp=$(mktemp)
    if jq --arg listen "$new_listen" --argjson direct "$new_direct" '
        .inbounds = ((.inbounds // []) | map(if .type == "tun" then . else .listen = $listen end))
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
        systemctl restart sing-box
        sleep 1
        if systemctl is-active --quiet sing-box; then
            success "已应用: 入站=$(_io_mode_label "$INBOUND_MODE") 出站=$(_io_mode_label "$OUTBOUND_MODE")"
            info "listen=$new_listen  direct.domain_strategy=$(echo "$new_direct" | jq -r '.domain_strategy // "default"')"
        else
            error "服务重启失败，请查看 journalctl -u sing-box -e"
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
    while true; do
        clear
        echo "================================================"
        echo "          入站/出站 IP 模式"
        echo "================================================"
        echo "  当前入站: $(_io_mode_label "$INBOUND_MODE")"
        echo "  当前出站: $(_io_mode_label "$OUTBOUND_MODE")"
        echo "  服务器 IP: v4=${LAST_SERVER_IP4:-无}  v6=${LAST_SERVER_IP6:-无}"
        echo ""
        local v6only
        v6only=$(cat /proc/sys/net/ipv6/bindv6only 2>/dev/null || echo 0)
        if [ "$v6only" == "1" ]; then
            echo -e "${YELLOW}[提示] 系统 bindv6only=1，双栈入站只会接受 IPv6 连接${NC}"
            echo -e "${YELLOW}       如需真正双栈，请先执行: sysctl -w net.ipv6.bindv6only=0${NC}"
        fi
        echo "------------------------------------------------"
        echo "  入站 = 客户端连你的 VPS 时使用的 IP 版本"
        echo "  出站 = VPS 访问外网时使用的 IP 版本"
        echo "------------------------------------------------"
        echo "  1. 双栈入 + 双栈出（默认 / 还原）"
        echo "  2. v4 入站 + v4 出站"
        echo "  3. v6 入站 + v6 出站"
        echo "  4. v4 入站 + v6 出站"
        echo "  5. v6 入站 + v4 出站"
        echo "  6. 自定义（分别选入站和出站）"
        echo "  0. 返回"
        echo "================================================"
        local c
        read -rp "请选择 [0-6]: " c
        local new_in="" new_out=""
        case "$c" in
            1) new_in="both"; new_out="both" ;;
            2) new_in="v4"; new_out="v4" ;;
            3) new_in="v6"; new_out="v6" ;;
            4) new_in="v4"; new_out="v6" ;;
            5) new_in="v6"; new_out="v4" ;;
            6)
                new_in=$(_io_pick_inbound)
                [ -z "$new_in" ] && { warn "无效选择"; sleep 1; continue; }
                new_out=$(_io_pick_outbound)
                [ -z "$new_out" ] && { warn "无效选择"; sleep 1; continue; }
                ;;
            0) return ;;
            *) warn "无效选项"; sleep 1; continue ;;
        esac
        INBOUND_MODE="$new_in"
        OUTBOUND_MODE="$new_out"
        echo ""
        info "即将应用: 入站=$(_io_mode_label "$INBOUND_MODE")  出站=$(_io_mode_label "$OUTBOUND_MODE")"
        local yn
        read -rp "确认应用并重启 sing-box? (y/N): " yn
        if [[ "$yn" =~ ^[Yy]$ ]]; then
            apply_inbound_outbound_mode || warn "应用失败，请检查日志"
        else
            info "已取消"
        fi
        read -n 1 -s -r -p "按任意键继续..."
    done
}
FUNC_EOF

SCRIPT_PATH="$SCRIPT_PATH" FUNCS_FILE="$FUNCS_FILE" python3 << 'PY_EOF'
import os, sys, re
path = os.environ['SCRIPT_PATH']
funcs_path = os.environ['FUNCS_FILE']
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

if 'io_mode_menu' in content:
    print("[WARN] 已存在 IP 模式补丁，跳过"); sys.exit(0)

for m in ['NODE_HY2_RELAY=()', 'relay_menu()']:
    if m not in content:
        print(f"[ERROR] 未找到第一期补丁标记: {m}"); sys.exit(1)

with open(funcs_path, 'r', encoding='utf-8') as f:
    funcs = f.read()

# 1. 变量声明
anchor_decl = '# 中转管理（按端口绑定）'
if anchor_decl not in content:
    print("[ERROR] 未找到中转变量声明锚点"); sys.exit(1)
content = content.replace(anchor_decl,
    '# 入站/出站 IP 模式：v4 / v6 / both\n'
    'INBOUND_MODE="${INBOUND_MODE:-both}"\n'
    'OUTBOUND_MODE="${OUTBOUND_MODE:-both}"\n\n'
    + anchor_decl, 1)

# 2. 替换 get_listen_address（去掉交互，按模式静默返回）
old_listen = '''get_listen_address() {
    if [ ! -f /proc/net/if_inet6 ]; then
        echo "0.0.0.0"
        return
    fi
    local v6only="0"
    v6only=$(cat /proc/sys/net/ipv6/bindv6only 2>/dev/null || echo 0)
    if [ "$v6only" == "1" ]; then
        warn "检测到 net.ipv6.bindv6only=1：监听 '::' 时将无法接受 IPv4 连接。" >&2
        local adj=""
        if ! read -rp "是否临时设置 net.ipv6.bindv6only=0 以启用 IPv4+IPv6 双栈？(y/N): " adj; then
            warn "读取输入失败，使用默认监听地址。" >&2
            adj="n"
        fi
        if [[ "$adj" =~ ^[Yy]$ ]]; then
            if sysctl -w net.ipv6.bindv6only=0 >/dev/null 2>&1; then
                success "已临时设置 net.ipv6.bindv6only=0（重启后失效）。" >&2
                echo "::"
                return
            else
                warn "sysctl 设置失败。" >&2
            fi
        fi
        if [ -n "$LAST_SERVER_IP4" ]; then
            warn "将改用 0.0.0.0（仅监听 IPv4，IPv6 客户端将无法连接）。" >&2
            echo "0.0.0.0"
            return
        fi
    fi
    echo "::"
}'''
new_listen = '''get_listen_address() {
    local mode="${INBOUND_MODE:-both}"
    if [ ! -f /proc/net/if_inet6 ]; then
        echo "0.0.0.0"
        return
    fi
    case "$mode" in
        v4)
            echo "0.0.0.0"
            ;;
        v6)
            if [ -n "${LAST_SERVER_IP6:-}" ]; then
                echo "$LAST_SERVER_IP6"
            else
                echo "::"
            fi
            ;;
        both|*)
            echo "::"
            ;;
    esac
}'''
if old_listen not in content:
    print("[ERROR] 未找到 get_listen_address 原定义"); sys.exit(1)
content = content.replace(old_listen, new_listen, 1)

# 3. save_persistent_info 加两行
old_save = '        echo "LINK_IP_MODE=\\"${LINK_IP_MODE}\\""'
new_save = ('        echo "LINK_IP_MODE=\\"${LINK_IP_MODE}\\""\n'
            '        echo "INBOUND_MODE=\\"${INBOUND_MODE}\\""\n'
            '        echo "OUTBOUND_MODE=\\"${OUTBOUND_MODE}\\""')
if old_save not in content:
    print("[ERROR] 未找到 save_persistent_info 的 LINK_IP_MODE 行"); sys.exit(1)
content = content.replace(old_save, new_save, 1)

# 4. load_persistent_info 加两个 case
old_case = '            LINK_IP_MODE) LINK_IP_MODE="$value" ;;'
new_case = ('            LINK_IP_MODE) LINK_IP_MODE="$value" ;;\n'
            '            INBOUND_MODE) INBOUND_MODE="$value" ;;\n'
            '            OUTBOUND_MODE) OUTBOUND_MODE="$value" ;;')
if old_case not in content:
    print("[ERROR] 未找到 load_persistent_info 的 LINK_IP_MODE case"); sys.exit(1)
content = content.replace(old_case, new_case, 1)

# 5. create_config_json：existing_inbounds 读入后统一 listen
old_existing = '''    local existing_inbounds="[]"
    if [ -f "$SINGBOX_CONFIG_FILE" ]; then
        existing_inbounds=$(jq '.inbounds // []' "$SINGBOX_CONFIG_FILE" 2>/dev/null || echo "[]")
    fi
'''
new_existing = '''    local existing_inbounds="[]"
    if [ -f "$SINGBOX_CONFIG_FILE" ]; then
        existing_inbounds=$(jq '.inbounds // []' "$SINGBOX_CONFIG_FILE" 2>/dev/null || echo "[]")
    fi
    existing_inbounds=$(jq --arg listen "$listen_addr" 'map(if .type == "tun" then . else .listen = $listen end)' <<< "$existing_inbounds")
'''
if old_existing not in content:
    print("[ERROR] 未找到 create_config_json 的 existing_inbounds 段"); sys.exit(1)
content = content.replace(old_existing, new_existing, 1)

# 6. create_config_json 的 _ob 初始化改为按 OUTBOUND_MODE
old_ob1 = "    local _ob='[{\"type\":\"direct\",\"tag\":\"direct\"},{\"type\":\"block\",\"tag\":\"block\"}]'\n    local _t _p _rt _tag"
new_ob1 = (
    "    local _direct_ob\n"
    "    case \"${OUTBOUND_MODE:-both}\" in\n"
    "        v4) _direct_ob='{\"type\":\"direct\",\"tag\":\"direct\",\"domain_strategy\":\"ipv4_only\"}' ;;\n"
    "        v6) _direct_ob='{\"type\":\"direct\",\"tag\":\"direct\",\"domain_strategy\":\"ipv6_only\"}' ;;\n"
    "        *)  _direct_ob='{\"type\":\"direct\",\"tag\":\"direct\"}' ;;\n"
    "    esac\n"
    "    local _ob=\"[${_direct_ob},{\\\"type\\\":\\\"block\\\",\\\"tag\\\":\\\"block\\\"}]\"\n"
    "    local _t _p _rt _tag"
)
if old_ob1 not in content:
    print("[ERROR] 未找到 create_config_json 的 _ob 初始化"); sys.exit(1)
content = content.replace(old_ob1, new_ob1, 1)

# 7. rebuild_route_and_outbounds 的 ob 初始化改为按 OUTBOUND_MODE
old_ob2 = "    local ob='[{\"type\":\"direct\",\"tag\":\"direct\"},{\"type\":\"block\",\"tag\":\"block\"}]'\n    local t p rt tag"
new_ob2 = (
    "    local _direct_ob\n"
    "    case \"${OUTBOUND_MODE:-both}\" in\n"
    "        v4) _direct_ob='{\"type\":\"direct\",\"tag\":\"direct\",\"domain_strategy\":\"ipv4_only\"}' ;;\n"
    "        v6) _direct_ob='{\"type\":\"direct\",\"tag\":\"direct\",\"domain_strategy\":\"ipv6_only\"}' ;;\n"
    "        *)  _direct_ob='{\"type\":\"direct\",\"tag\":\"direct\"}' ;;\n"
    "    esac\n"
    "    local ob=\"[${_direct_ob},{\\\"type\\\":\\\"block\\\",\\\"tag\\\":\\\"block\\\"}]\"\n"
    "    local t p rt tag"
)
if old_ob2 not in content:
    print("[ERROR] 未找到 rebuild 的 ob 初始化"); sys.exit(1)
content = content.replace(old_ob2, new_ob2, 1)

# 8. 在 relay_menu 之前插入新函数
if 'relay_menu() {' not in content:
    print("[ERROR] 未找到 relay_menu 定义"); sys.exit(1)
content = content.replace('relay_menu() {', funcs + '\nrelay_menu() {', 1)

# 9. 主菜单加 18
old_menu = '    echo "  17. 中转管理（按端口绑定 socks5/hy2/vless/vmess）"'
new_menu = ('    echo "  17. 中转管理（按端口绑定 socks5/hy2/vless/vmess）"\n'
            '    echo "  18. 入站/出站 IP 模式（v4/v6/双栈）"')
if old_menu not in content:
    print("[ERROR] 未找到菜单 17"); sys.exit(1)
content = content.replace(old_menu, new_menu, 1)

# 10. case 加 18
old_case2 = '        17) relay_menu ;;'
new_case2 = '        17) relay_menu ;;\n        18) io_mode_menu ;;'
if old_case2 not in content:
    print("[ERROR] 未找到 case 17"); sys.exit(1)
content = content.replace(old_case2, new_case2, 1)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print("[OK] 第三期补丁插入完成")
PY_EOF

bash -n "$SCRIPT_PATH" && echo "[SUCCESS] 语法检查通过！重跑 bash /root/install.sh → 18 进入 IP 模式。"
PATCH_EOF
