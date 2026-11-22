#!/bin/bash
set -e
echo "=== 清理脚本备份 ==="
ls -t /root/install.sh.bak.* 2>/dev/null | tail -n +2 | xargs -r rm -f
ls -t /usr/local/etc/sing-box/config.json.edit.bak.* 2>/dev/null | tail -n +2 | xargs -r rm -f
ls -t /usr/local/etc/sing-box/config.json.bak.* 2>/dev/null | tail -n +2 | xargs -r rm -f

echo "=== 清理 journal 到 100M ==="
journalctl --vacuum-size=100M 2>/dev/null || true

echo "=== 永久限制 journal 到 200M ==="
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/size.conf <<'EOF'
[Journal]
SystemMaxUse=200M
SystemMaxFileSize=50M
MaxRetentionSec=7day
EOF
systemctl restart systemd-journald 2>/dev/null || true

echo "=== sing-box 日志级别改 warn ==="
if [ -f /usr/local/etc/sing-box/config.json ]; then
    cp /usr/local/etc/sing-box/config.json /tmp/c.json.bak
    jq '.log.level = "warn"' /usr/local/etc/sing-box/config.json > /tmp/c.json \
      && mv /tmp/c.json /usr/local/etc/sing-box/config.json
    if sing-box check -c /usr/local/etc/sing-box/config.json >/dev/null 2>&1; then
        systemctl restart sing-box 2>/dev/null || rc-service sing-box restart 2>/dev/null || true
        echo "sing-box 已重启，日志级别: warn"
    else
        cp /tmp/c.json.bak /usr/local/etc/sing-box/config.json
        echo "配置有误，已回滚"
    fi
fi

echo "=== 磁盘占用 ==="
du -sh /root/install.sh.bak* /var/log 2>/dev/null
journalctl --disk-usage 2>/dev/null || true