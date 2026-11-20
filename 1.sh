bash << 'PATCH_EOF'
set -e
command -v python3 >/dev/null 2>&1 || { echo "需要 python3，请先 apt/yum install -y python3"; exit 1; }

SCRIPT_PATH="/root/install.sh"
[ -f "$SCRIPT_PATH" ] || { echo "[ERROR] 文件不存在: $SCRIPT_PATH"; exit 1; }

BACKUP="${SCRIPT_PATH}.bak.$(date +%Y%m%d_%H%M%S)"
cp -a "$SCRIPT_PATH" "$BACKUP"
echo "[INFO] 已备份: $BACKUP"

FUNCS_FILE=$(mktemp)
trap 'rm -f "$FUNCS_FILE"' EXIT
cat > "$FUNCS_FILE" << 'FUNC_EOF'
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
    } > "$tmp"
    if [[ -s "$tmp" ]] && mv -f "$tmp" "$RELAY_FILE"; then
        chmod 600 "$RELAY_FILE" 2>/dev/null
        return 0
    fi
    rm -f "$tmp"; return 1
}

load_relays_from_file() {
    RELAY_JSON=(); RELAY_DESC=()
    NODE_HY2_RELAY=(); NODE_REALITY_RELAY=()
    [ -f "$RELAY_FILE" ] || return 0
    local kind a b c
    while IFS='|' read -r kind a b c; do
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
                esac
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
    local ob='[{"type":"direct","tag":"direct"},{"type":"block","tag":"block"}]'
    local t p rt tag
    for t in "${!RELAY_JSON[@]}"; do
        ob=$(jq --argjson o "${RELAY_JSON[$t]}" '. + [$o]' <<< "$ob")
    done
    local rules='[]'
    for p in "${!NODE_HY2_RELAY[@]}"; do
        rt="${NODE_HY2_RELAY[$p]}"
        if [ -z "$rt" ] || [ "$rt" == "direct" ]; then continue; fi
        [ -z "${RELAY_JSON[$rt]:-}" ] && continue
        tag="hy2-in-${p}"
        jq -e --arg tag "$tag" '.inbounds[] | select(.tag == $tag)' "$SINGBOX_CONFIG_FILE" >/dev/null 2>&1 || continue
        rules=$(jq --arg inb "$tag" --arg out "$rt" '. + [{inbound: [$inb], outbound: $out}]' <<< "$rules")
    done
    for p in "${!NODE_REALITY_RELAY[@]}"; do
        rt="${NODE_REALITY_RELAY[$p]}"
        if [ -z "$rt" ] || [ "$rt" == "direct" ]; then continue; fi
        [ -z "${RELAY_JSON[$rt]:-}" ] && continue
        tag="vless-in-${p}"
        jq -e --arg tag "$tag" '.inbounds[] | select(.tag == $tag)' "$SINGBOX_CONFIG_FILE" >/dev/null 2>&1 || continue
        rules=$(jq --arg inb "$tag" --arg out "$rt" '. + [{inbound: [$inb], outbound: $out}]' <<< "$rules")
    done
    jq --argjson ob "$ob" --argjson rules "$rules" \
       '.outbounds = $ob | .route = {rules: $rules, final: "direct"}' \
       "$SINGBOX_CONFIG_FILE" > "${SINGBOX_CONFIG_FILE}.tmp" \
       && mv "${SINGBOX_CONFIG_FILE}.tmp" "$SINGBOX_CONFIG_FILE"
    chmod 600 "$SINGBOX_CONFIG_FILE"
    if $SINGBOX_CMD check -c "$SINGBOX_CONFIG_FILE" >/dev/null 2>&1; then
        systemctl restart sing-box
        sleep 1
        if systemctl is-active --quiet sing-box; then
            success "配置已更新，服务已重启"
        else
            error "服务重启失败，查看: journalctl -u sing-box -e"
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
    else
        NODE_REALITY_RELAY["$sel_port"]="$sel_tag"
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
    success "已删除中转 $dt"
    save_relays_to_file
    rebuild_route_and_outbounds || true
    read -n 1 -s -r -p "按任意键继续..."
}

relay_menu() {
    load_relays_from_file
    while true; do
        clear
        echo "================================================"
        echo "          中转管理（按端口绑定）"
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
        echo "------------------------------------------------"
        echo "  1. 添加中转（粘贴链接）"
        echo "  2. 为节点端口绑定中转"
        echo "  3. 取消端口的中转（改为直连）"
        echo "  4. 删除中转"
        echo "  0. 返回主菜单"
        echo "================================================"
        local c
        read -rp "请选择 [0-4]: " c
        case "$c" in
            1) _relay_add_ui ;;
            2) _relay_bind_ui ;;
            3) _relay_unbind_ui ;;
            4) _relay_delete_ui ;;
            0) return ;;
            *) warn "无效选项"; sleep 1 ;;
        esac
    done
}
FUNC_EOF

SCRIPT_PATH="$SCRIPT_PATH" FUNCS_FILE="$FUNCS_FILE" python3 << 'PY_EOF'
import os, sys
path = os.environ['SCRIPT_PATH']
funcs_path = os.environ['FUNCS_FILE']
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

if 'relay_menu' in content and 'rebuild_route_and_outbounds' in content:
    print("[WARN] 已存在中转补丁，跳过"); sys.exit(0)

with open(funcs_path, 'r', encoding='utf-8') as f:
    funcs = f.read()

# 1. 插入变量声明
old_decl = '''declare -A NODE_REALITY_FP=()
LAST_HY2_OBFS_PASSWORD=""

# --- Colors ---'''
new_decl = '''declare -A NODE_REALITY_FP=()
LAST_HY2_OBFS_PASSWORD=""

# 中转管理（按端口绑定）
declare -A RELAY_JSON=()
declare -A RELAY_DESC=()
declare -A NODE_HY2_RELAY=()
declare -A NODE_REALITY_RELAY=()
RELAY_FILE="${SINGBOX_CONFIG_DIR}/relays.conf"

# --- Colors ---'''
if old_decl not in content:
    print("[ERROR] 未找到变量声明插入点"); sys.exit(1)
content = content.replace(old_decl, new_decl, 1)

# 2. 插入全部中转函数
marker = '# --- Management functions ---'
if marker not in content:
    print("[ERROR] 未找到函数插入点"); sys.exit(1)
content = content.replace(marker, funcs + '\n' + marker, 1)

# 3. 替换 create_config_json 里的 jq -n 段，加入 outbounds/rules
old_jq = '''    jq -n --argjson inbounds "$existing_inbounds" '{
        log: {level: "info", timestamp: true},
        inbounds: $inbounds,
        outbounds: [
            {type: "direct", tag: "direct"},
            {type: "block", tag: "block"}
        ]
    }' > "$SINGBOX_CONFIG_FILE"'''
new_jq = '''    local _ob='[{"type":"direct","tag":"direct"},{"type":"block","tag":"block"}]'
    local _t _p _rt _tag
    for _t in "${!RELAY_JSON[@]}"; do
        _ob=$(jq --argjson o "${RELAY_JSON[$_t]}" '. + [$o]' <<< "$_ob")
    done
    local _rules='[]'
    for _p in "${!NODE_HY2_RELAY[@]}"; do
        _rt="${NODE_HY2_RELAY[$_p]}"
        if [ -z "$_rt" ] || [ "$_rt" == "direct" ]; then continue; fi
        [ -z "${RELAY_JSON[$_rt]:-}" ] && continue
        _tag="hy2-in-${_p}"
        jq -e --arg tag "$_tag" '.[] | select(.tag == $tag)' <<< "$existing_inbounds" >/dev/null 2>&1 || continue
        _rules=$(jq --arg inb "$_tag" --arg out "$_rt" '. + [{inbound: [$inb], outbound: $out}]' <<< "$_rules")
    done
    for _p in "${!NODE_REALITY_RELAY[@]}"; do
        _rt="${NODE_REALITY_RELAY[$_p]}"
        if [ -z "$_rt" ] || [ "$_rt" == "direct" ]; then continue; fi
        [ -z "${RELAY_JSON[$_rt]:-}" ] && continue
        _tag="vless-in-${_p}"
        jq -e --arg tag "$_tag" '.[] | select(.tag == $tag)' <<< "$existing_inbounds" >/dev/null 2>&1 || continue
        _rules=$(jq --arg inb "$_tag" --arg out "$_rt" '. + [{inbound: [$inb], outbound: $out}]' <<< "$_rules")
    done

    jq -n --argjson inbounds "$existing_inbounds" --argjson outbounds "$_ob" --argjson rules "$_rules" '{
        log: {level: "info", timestamp: true},
        inbounds: $inbounds,
        outbounds: $outbounds,
        route: {rules: $rules, final: "direct"}
    }' > "$SINGBOX_CONFIG_FILE"'''
if old_jq not in content:
    print("[ERROR] 未找到 create_config_json 的 jq 段"); sys.exit(1)
content = content.replace(old_jq, new_jq, 1)

# 4. 菜单添加 17
old_menu = '    echo "  16. 一键全部卸载（含脚本、证书、配置、sb）"'
new_menu = '    echo "  16. 一键全部卸载（含脚本、证书、配置、sb）"\n    echo "  17. 中转管理（按端口绑定 socks5/hy2/vless/vmess）"'
if old_menu not in content:
    print("[ERROR] 未找到菜单 16"); sys.exit(1)
content = content.replace(old_menu, new_menu, 1)

# 5. case 分支添加 17
old_case = '        16) uninstall_all ;;'
new_case = '        16) uninstall_all ;;\n        17) relay_menu ;;'
if old_case not in content:
    print("[ERROR] 未找到 case 16"); sys.exit(1)
content = content.replace(old_case, new_case, 1)

# 6. 入口点加载中转配置
old_entry = '''find_and_set_singbox_cmd
load_persistent_info

while true; do'''
new_entry = '''find_and_set_singbox_cmd
load_persistent_info
load_relays_from_file

while true; do'''
if old_entry not in content:
    print("[ERROR] 未找到入口点"); sys.exit(1)
content = content.replace(old_entry, new_entry, 1)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print("[OK] 补丁插入完成")
PY_EOF

bash -n "$SCRIPT_PATH" && echo "[SUCCESS] 语法检查通过！重新运行 bash /root/install.sh，主菜单新增 17 项。"
PATCH_EOF
