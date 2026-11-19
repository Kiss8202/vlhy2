// 本配置为 Xray 综合模板 (包含 Vless Encryption / Reality / XHTTP)
//
// 💡 请在编辑器中使用快捷键 (Ctrl+F / Cmd+F) 全局搜索关键字 “【修改项】” 来快速定位：
// 共有 22 处需要修改。
// 01. 【可选】日志等级：默认会产生大量日志，可以修改日志级别或配合 logrotate 使用。
// 02. 【可选】DNS 配置：若无需配置 DNS 解锁流媒体，则保持默认。
// 03. 【必改】VLESS Encryption：修改监听端口 (port)。
// 04. 【必改】VLESS Encryption：修改 UUID。
// 05. 【必改】VLESS Encryption：修改解密密钥 (decryption key)。
// 06. 【必改】VLESS Vision Reality：修改 UUID。
// 07. 【必改】VLESS Vision Reality：修改目标网站 (target)。
// 08. 【必改】VLESS Vision Reality：修改服务器名称 (serverNames)。
// 09. 【必改】VLESS Vision Reality：修改私钥 (privateKey)。
// 10. 【必改】VLESS Vision Reality：修改 shortIds。
// 11. 【必改】VLESS XHTTP：修改 UUID。
// 12. 【必改】VLESS XHTTP：修改路径 (path)。
// 13. 【可选】Cloudflare WARP 出站：用于分流大陆流量防止被墙，或分流 Google 防止定位送中。支持 tun0 接口或 Socks 模式。若直接使用本机直连，可移除此出站，同时删除或修改任何带有FORWARD_TO_WARP的路由规则。
// 14. 【必改】落地节点出站：用于分流 Google、AI 等流量。若保留此出站，需修改 "address"、"port"、"id" 及 "encryption"。若直接使用本机直连，可移除此出站，同时删除或修改任何带有FORWARD_TO_VENC的路由规则。
// 15. 【必改】入站SNI校验，和【修改项】8保持一致。
// 16. 【可选】YouTube 域名分流：默认指向落地节点，若计划分流至 Cloudflare WARP，将出站改为 FORWARD_TO_WARP，若直接使用本机直连，直接移除此路由规则。一般还是和Google的分流规则一致，不一致有炸号风险。
// 17. 【可选】Google 域名分流：默认指向落地节点，若计划分流至 Cloudflare WARP，将出站改为 FORWARD_TO_WARP，若直接使用本机直连，直接移除此路由规则。
// 18. 【可选】AI 站点域名分流：默认指向落地节点，若计划分流至 Cloudflare WARP，将出站改为 FORWARD_TO_WARP，若直接使用本机直连，直接移除此路由规则。
// 19. 【可选】中国网站分流至WARP防止被墙，若直接使用本机直连，可直接移除此路由规则。
// 20. 【可选】Google IP 分流：默认指向落地节点，若计划分流至 Cloudflare WARP，将出站改为 FORWARD_TO_WARP，若直接使用本机直连，直接移除此路由规则。
// 21. 【可选】当域名未匹配但解析出中国 IP 时，分流至WARP防止被墙，若直接使用本机直连，可直接移除此路由规则。
// 22. 【可选】处理所有未命中规则的剩余流量，根据服务器的实际网络环境和IP质量，将 outboundTag 修改为 ALLOW_v4v6、ALLOW_v6v4、ALLOW_v4 或 ALLOW_v6。
{
  //【修改项】1. 日志等级
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "info",
    "dnsLog": true
  },
  //【修改项】2. DNS配置
  "dns": {
    "servers": [
      /*      {
        "address": "流媒体解锁DNS的地址",
        "domains": [
          "geosite:netflix",
          "geosite:disney",
          "geosite:tiktok",
          "geosite:amazon",
          "geosite:niconico"
        ],
        "skipFallback": true
      },
      */
      "https+local://dns.google/dns-query",
      "https+local://dns.quad9.net/dns-query",
      "https+local://cloudflare-dns.com/dns-query",
      "https+local://doh.opendns.com/dns-query",
      "https+local://doh.dns.sb/dns-query",
      "https+local://dns.adguard.com/dns-query",
      "https+local://doh.powerdns.org",
      "https+local://public.dns.iij.jp/dns-query",
      "https+local://doh-jp.blahdns.com/dns-query",
      "https+local://dns.mullvad.net/dns-query"
    ],
    "enableParallelQuery": true
  },
  "inbounds": [
    {
      "tag": "SNI_ROUTER",
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "tunnel",
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ],
        "routeOnly": true
      }
    },
    {
      "tag": "VLESS_ENC_IN",
      "listen": "0.0.0.0",
      //【修改项】3. Vless Encryption的监听端口
      "port": 1234,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "email": "VENC",
            //【修改项】4. Vless Encryption的UUID，运行 xray uuid 生成
            "id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
          }
        ],
        //【修改项】5. Vless Encryption的decryption key，运行 xray vlessenc 生成
        "decryption": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
      }
    },
    {
      "tag": "VLESS_VISION-REALITY_IN",
      "listen": "127.0.0.1",
      "port": 44301,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "email": "TCP_VISION",
            //【修改项】6. Vless Vision Reality的UUID，运行 xray uuid 生成
            "id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
            "flow": "xtls-rprx-vision" 
          }
        ],
        "decryption": "none",
        "fallbacks": [
          {
            "dest": "/dev/shm/xhttp.sock"
          }
        ]
      },
      "streamSettings": {
        "network": "raw",
        "rawSettings": {
          "acceptProxyProtocol": true
        },
        "security": "reality",
        "realitySettings": {
          //【修改项】7. Vless Vision Reality的target，域名必须同时符合H2和TLS1.3 X25519 格式为域名:443
          "target": "xxxxxxx.com:443",
          "serverNames": [
            // 【修改项】8. Vless Vision Reality的serverNames，一般与target保持一致，不带端口
            "xxxxxxx.com"
          ],
          // 【修改项】9. Vless Vision Reality的privateKey，运行 xray x25519 生成
          "privateKey": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", 
          "shortIds": [
            // 【修改项】10. Vless Vision Reality的shortIds，运行 openssl rand -hex 8 生成,可以生成多个
            "xxxxxxxxxxxxxxxx"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ],
        "routeOnly": true
      }
    },
    {
      "tag": "VLESS_XHTTP_IN",
      "listen": "/dev/shm/xhttp.sock,0666",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "email": "XHTTP",
            //【修改项】11. VLESS XHTTP的UUID，运行 xray uuid 生成
            "id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" 
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": {
          "host": "",
          //【修改项】12. VLESS XHTTP的path，运行 openssl rand -base64 96 | tr -d '/+=' | head -c 64 生成
          "path": "/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", 
          "mode": "auto"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ],
        "routeOnly": true
      }
    }
  ],
  "outbounds": [
    //IPv4优先
    {
      "tag": "ALLOW_v4v6",
      "protocol": "freedom",
      "targetStrategy": "ForceIPv4v6"
    },
    //IPv6优先
    {
      "tag": "ALLOW_v6v4",
      "protocol": "freedom",
      "targetStrategy": "ForceIPv6v4"
    },
    //仅IPv4
    {
      "tag": "ALLOW_v4",
      "protocol": "freedom",
      "targetStrategy": "ForceIPv4"
    },
    //仅IPv6
    {
      "tag": "ALLOW_v6",
      "protocol": "freedom",
      "targetStrategy": "ForceIPv6"
    },
    {
      "tag": "BLOCK",
      "protocol": "blackhole"
    },
    {
      "tag": "FORWARD_TO_VLESS",
      "protocol": "freedom",
      "settings": {
        "redirect": "127.0.0.1:44301",
        "proxyProtocol": 2
      }
    },
    //【修改项】13. WARP配置，确保tun0存在
    {
      "tag": "FORWARD_TO_WARP",
      "protocol": "freedom",
      "streamSettings": {
        "sockopt": {
          "interface": "tun0"
        }
      }
    },
    /*
    //【修改项】13. WARP配置，无法创建tun0时可以用socks代替
    {
      "tag": "FORWARD_TO_WARP",
      "protocol": "socks",
      "targetStrategy": "AsIs",
      "settings": {
        "address": "127.0.0.1",
        "port": 44304
      }
    },
    */
    //【修改项】14. 落地机配置转发规则，这里以VENC为例，可以配置多个，需要自行修改
    {
      "tag": "FORWARD_TO_VENC",
      "protocol": "vless",
      "settings": {
        "address": "",
        "port": 1234,
        "id": "",
        "encryption": ""
      }
    }
    /*
    ,{
      "tag": "FORWARD_TO_VENC2",
      "protocol": "vless",
      "settings": {
        "address": "",
        "port": 1234,
        "id": "",
        "encryption": ""
      }
    }
    */
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      //入站校验SNI成功，通过
      {
        "inboundTag": [
          "SNI_ROUTER"
        ],
        "domain": [
          //【修改项】15. 入站校验SNI和【修改项】8保持一致
          "xxxxxxx.com" 
        ],
        "outboundTag": "FORWARD_TO_VLESS"
      },
      //入站校验SNI失败，阻断
      {
        "inboundTag": [
          "SNI_ROUTER"
        ],
        "outboundTag": "BLOCK"
      },
      //VENC入站校验IP，拒绝所有中国IP，防止被墙
      {
        "inboundTag": [
          "VLESS_ENC_IN"
        ],
        "sourceIP": [
          "geoip:cn"
        ],
        "outboundTag": "BLOCK"
      },
      //【修改项】16. YouTube分流
      {
        "inboundTag": [
          "VLESS_VISION-REALITY_IN",
          "VLESS_XHTTP_IN",
          "VLESS_ENC_IN"
        ],
        "domain": [
          "geosite:youtube"
        ],
        "outboundTag": "FORWARD_TO_VENC"
      },
      //【修改项】17. 谷歌域名分流
      {
        "inboundTag": [
          "VLESS_VISION-REALITY_IN",
          "VLESS_XHTTP_IN",
          "VLESS_ENC_IN"
        ],
        "domain": [
          "geosite:google",
          "domain:gstatic.com",
          "domain:googleapis.com",
          "domain:googleusercontent.com",
          "domain:googletagmanager.com",
          "domain:google-analytics.com",
          "regexp:^clients\\d*\\.google\\.com$",
          "keyword:ogads-pa"
        ],
        "outboundTag": "FORWARD_TO_VENC"
      },
      //【修改项】18. AI域名分流
      {
        "inboundTag": [
          "VLESS_VISION-REALITY_IN",
          "VLESS_XHTTP_IN",
          "VLESS_ENC_IN"
        ],
        "domain": [
          "geosite:category-ai-!cn",
          "geosite:category-ai-chat-!cn"
        ],
        "outboundTag": "FORWARD_TO_VENC"
      },
      //屏蔽种子下载
      {
        "inboundTag": [
          "VLESS_VISION-REALITY_IN",
          "VLESS_XHTTP_IN",
          "VLESS_ENC_IN"
        ],
        "protocol": [
          "bittorrent"
        ],
        "outboundTag": "BLOCK"
      },
      //屏蔽游戏下载种子下载和广告
      {
        "inboundTag": [
          "VLESS_VISION-REALITY_IN",
          "VLESS_XHTTP_IN",
          "VLESS_ENC_IN"
        ],
        "domain": [
          "geosite:category-game-platforms-download",
          //"geosite:steam",
          //"geosite:epicgames",
          //"geosite:gog",
          //"geosite:ubisoft",
          "geosite:category-ads-all",
          "geosite:category-public-tracker"
        ],
        "outboundTag": "BLOCK"
      },
      //屏蔽ping0.cc，只要域名带ping0全部屏蔽，宁可错杀一千，不可放过一个
      {
        "inboundTag": [
          "VLESS_VISION-REALITY_IN",
          "VLESS_XHTTP_IN",
          "VLESS_ENC_IN"
        ],
        "domain": [
          "regexp:ping0"
        ],
        "outboundTag": "BLOCK"
      },
      //【修改项】19. 中国网站分流WARP
      {
        "inboundTag": [
          "VLESS_VISION-REALITY_IN",
          "VLESS_XHTTP_IN",
          "VLESS_ENC_IN"
        ],
        "domain": [
          "geosite:cn",
          "geosite:geolocation-cn"
        ],
        "outboundTag": "FORWARD_TO_WARP"
      },
      //【修改项】20. 谷歌IP分流
      {
        "inboundTag": [
          "VLESS_VISION-REALITY_IN",
          "VLESS_XHTTP_IN",
          "VLESS_ENC_IN"
        ],
        "ip": [
          "geoip:google"
        ],
        "outboundTag": "FORWARD_TO_VENC"
      },
      //【修改项】21. 中国IP分流WARP
      {
        "inboundTag": [
          "VLESS_VISION-REALITY_IN",
          "VLESS_XHTTP_IN",
          "VLESS_ENC_IN"
        ],
        "ip": [
          "geoip:cn"
        ],
        "outboundTag": "FORWARD_TO_WARP"
      },
      //【修改项】22. 最终出站
      {
        "inboundTag": [
          "VLESS_VISION-REALITY_IN",
          "VLESS_XHTTP_IN",
          "VLESS_ENC_IN"
        ],
        "outboundTag": "ALLOW_v4v6"
      }
    ]
  }
}
