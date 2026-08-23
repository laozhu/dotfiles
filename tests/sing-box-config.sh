#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
config="$repo_dir/home/.config/sing-box/config.json"
secret_map="$repo_dir/home/.config/sing-box/secrets-map.json"
jq -e '
  .["$schema"] == "https://sing-box.sagernet.org/schema.json" and
  ([.inbounds[].tag] | sort == ["mixed-in", "tun-in"]) and
  ([.outbounds[].tag] | index("proxy") != null) and
  ([.outbounds[].tag] | index("auto") != null) and
  ([.outbounds[].tag] | index("singapore") != null) and
  ([.outbounds[].tag] | index("usa") != null) and
  ([.outbounds[].tag] | index("sg-vless") != null) and
  ([.outbounds[].tag] | index("sg-hy2") != null) and
  ([.outbounds[].tag] | index("us-vless") != null) and
  ([.outbounds[].tag] | index("us-hy2") != null) and
  .route.final == "direct" and
  .route.default_domain_resolver == "proxy-dns" and
  .route.auto_detect_interface == true and
  .experimental.cache_file.enabled == true
' "$config" >/dev/null

jq -e '
  .log == {"level": "info", "timestamp": true} and
  .dns.strategy == "prefer_ipv4" and
  ([.dns.servers[].tag] ==
    ["direct-dns", "proxy-dns", "hosts-dns", "fakeip-dns"]) and
  .dns.servers[0] == {
    "type": "https",
    "tag": "direct-dns",
    "server": "223.5.5.5",
    "server_port": 443,
    "tls": {
      "enabled": true,
      "server_name": "dns.alidns.com"
    }
  } and
  .dns.servers[1] == {
    "type": "https",
    "tag": "proxy-dns",
    "server": "1.1.1.1",
    "server_port": 443,
    "detour": "proxy",
    "tls": {
      "enabled": true,
      "server_name": "cloudflare-dns.com"
    }
  } and
  .dns.servers[2] == {
    "type": "hosts",
    "tag": "hosts-dns",
    "predefined": {
      "__SOPS_SG_SERVER_HOSTNAME__": "__SOPS_SG_SERVER_IP__",
      "__SOPS_US_SERVER_HOSTNAME__": "__SOPS_US_SERVER_IP__"
    }
  } and
  .dns.servers[3] == {
    "type": "fakeip",
    "tag": "fakeip-dns",
    "inet4_range": "198.18.0.0/15",
    "inet6_range": "fc00::/18"
  } and
  .dns.rules == [
    {
      "rule_set": "proxy-server",
      "server": "hosts-dns"
    },
    {
      "rule_set": ["gfwlist", "openai", "claude", "google-meet"],
      "server": "proxy-dns"
    },
    {
      "ip_is_private": true,
      "server": "direct-dns"
    },
    {
      "query_type": ["A", "AAAA"],
      "server": "fakeip-dns"
    }
  ]
' "$config" >/dev/null

jq -e '
  .inbounds == [
    {
      "type": "tun",
      "tag": "tun-in",
      "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
      "auto_route": true,
      "strict_route": true,
      "stack": "mixed"
    },
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "127.0.0.1",
      "listen_port": 7777
    }
  ] and
  .outbounds[0] == {
    "type": "selector",
    "tag": "proxy",
    "outbounds": [
      "auto",
      "singapore",
      "usa",
      "sg-vless",
      "sg-hy2",
      "us-vless",
      "us-hy2"
    ],
    "default": "auto",
    "interrupt_exist_connections": true
  } and
  .outbounds[1] == {
    "type": "urltest",
    "tag": "auto",
    "outbounds": ["sg-vless", "sg-hy2", "us-vless", "us-hy2"],
    "url": "https://www.gstatic.com/generate_204",
    "interval": "10m",
    "tolerance": 50,
    "interrupt_exist_connections": false
  } and
  .outbounds[2] == {
    "type": "urltest",
    "tag": "singapore",
    "outbounds": ["sg-vless", "sg-hy2"],
    "url": "https://www.gstatic.com/generate_204",
    "interval": "10m",
    "interrupt_exist_connections": false
  } and
  .outbounds[3] == {
    "type": "urltest",
    "tag": "usa",
    "outbounds": ["us-vless", "us-hy2"],
    "url": "https://www.gstatic.com/generate_204",
    "interval": "10m",
    "interrupt_exist_connections": false
  } and
  ([.outbounds[].tag] == [
    "proxy",
    "auto",
    "singapore",
    "usa",
    "sg-vless",
    "sg-hy2",
    "us-vless",
    "us-hy2",
    "direct"
  ])
' "$config" >/dev/null

jq -e '
  def vless_valid($tag; $server; $uuid; $name; $key; $short):
    first(.outbounds[] | select(.tag == $tag)) == {
      "type": "vless",
      "tag": $tag,
      "server": $server,
      "server_port": 443,
      "domain_resolver": "hosts-dns",
      "uuid": $uuid,
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": $name,
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        },
        "reality": {
          "enabled": true,
          "public_key": $key,
          "short_id": $short
        }
      }
    };
  def hy2_valid($tag; $server; $port; $password; $obfs; $name; $up; $down):
    first(.outbounds[] | select(.tag == $tag)) == {
      "type": "hysteria2",
      "tag": $tag,
      "server": $server,
      "server_port": $port,
      "domain_resolver": "hosts-dns",
      "up_mbps": $up,
      "down_mbps": $down,
      "password": $password,
      "obfs": {
        "type": "salamander",
        "password": $obfs
      },
      "tls": {
        "enabled": true,
        "server_name": $name
      }
    };
  vless_valid(
    "sg-vless";
    "__SOPS_SG_SERVER_HOSTNAME__";
    "__SOPS_SG_VLESS_UUID__";
    "__SOPS_SG_VLESS_TLS_SERVER_NAME__";
    "__SOPS_SG_VLESS_REALITY_PUBLIC_KEY__";
    "__SOPS_SG_VLESS_REALITY_SHORT_ID__"
  ) and
  hy2_valid(
    "sg-hy2";
    "__SOPS_SG_SERVER_HOSTNAME__";
    443;
    "__SOPS_SG_HY2_PASSWORD__";
    "__SOPS_SG_HY2_OBFS_PASSWORD__";
    "__SOPS_SG_HY2_TLS_SERVER_NAME__";
    45;
    170
  ) and
  vless_valid(
    "us-vless";
    "__SOPS_US_SERVER_HOSTNAME__";
    "__SOPS_US_VLESS_UUID__";
    "__SOPS_US_VLESS_TLS_SERVER_NAME__";
    "__SOPS_US_VLESS_REALITY_PUBLIC_KEY__";
    "__SOPS_US_VLESS_REALITY_SHORT_ID__"
  ) and
  hy2_valid(
    "us-hy2";
    "__SOPS_US_SERVER_HOSTNAME__";
    8443;
    "__SOPS_US_HY2_PASSWORD__";
    "__SOPS_US_HY2_OBFS_PASSWORD__";
    "__SOPS_US_HY2_TLS_SERVER_NAME__";
    32;
    95
  ) and
  first(.outbounds[] | select(.tag == "direct")) == {
    "type": "direct",
    "tag": "direct",
    "domain_resolver": "direct-dns"
  }
' "$config" >/dev/null

jq -e '
  .route.rules == [
    {"action": "sniff"},
    {"protocol": "dns", "action": "hijack-dns"},
    {"rule_set": "proxy-server", "outbound": "direct"},
    {"ip_is_private": true, "outbound": "direct"},
    {"rule_set": "custom-reject", "action": "reject"},
    {"rule_set": "custom-direct", "outbound": "direct"},
    {"rule_set": "custom-proxy", "outbound": "proxy"},
    {"rule_set": "openai", "outbound": "proxy"},
    {"rule_set": "claude", "outbound": "proxy"},
    {
      "rule_set": "google-meet",
      "network": "udp",
      "port": 3478,
      "port_range": "19302:19309",
      "outbound": "proxy"
    },
    {"rule_set": "google-meet", "outbound": "proxy"},
    {"rule_set": "gfwlist", "outbound": "proxy"}
  ] and
  .route.rule_set[0] == {
    "type": "inline",
    "tag": "proxy-server",
    "rules": [
      {
        "domain": [
          "__SOPS_SG_SERVER_HOSTNAME__",
          "__SOPS_US_SERVER_HOSTNAME__"
        ]
      }
    ]
  } and
  .route.rule_set[1:4] == [
    {
      "type": "inline",
      "tag": "custom-reject",
      "rules": [{"domain": "sing-box-placeholder.invalid"}]
    },
    {
      "type": "inline",
      "tag": "custom-direct",
      "rules": [{"domain": "sing-box-placeholder.invalid"}]
    },
    {
      "type": "inline",
      "tag": "custom-proxy",
      "rules": [{"domain": "sing-box-placeholder.invalid"}]
    }
  ] and
  .route.rule_set[4] == {
    "type": "inline",
    "tag": "google-meet",
    "rules": [
      {
        "domain": [
          "meet.google.com",
          "meetings.googleapis.com",
          "stun.l.google.com",
          "workspace.turns.goog",
          "meet.turns.goog"
        ],
        "ip_cidr": [
          "74.125.250.0/24",
          "142.250.82.0/24",
          "2001:4860:4864:5::/64",
          "2001:4860:4864:6::/64"
        ]
      }
    ]
  } and
  ([.route.rule_set[] | select(.type == "remote")] | length == 3) and
  ([.route.rule_set[] | select(.type == "remote") | .tag] ==
    ["gfwlist", "openai", "claude"]) and
  ([.route.rule_set[] | select(.type == "remote") | .download_detour] |
    all(. == "proxy")) and
  ([.route.rule_set[] | select(.type == "remote") | .update_interval] |
    all(. == "24h")) and
  ([.route.rule_set[] | select(.type == "remote") | .format] |
    all(. == "binary")) and
  first(.route.rule_set[] | select(.tag == "gfwlist")).url ==
    "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/gfw.srs" and
  first(.route.rule_set[] | select(.tag == "openai")).url ==
    "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/openai.srs" and
  first(.route.rule_set[] | select(.tag == "claude")).url ==
    "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/anthropic.srs"
' "$config" >/dev/null

jq -e '
  .experimental == {
    "cache_file": {
      "enabled": true,
      "store_fakeip": true
    }
  } and
  (.experimental | has("clash_api") | not) and
  (has("http_clients") | not) and
  ([.. | objects | keys[]] |
    any(
      . == "external_controller" or
      . == "external_ui" or
      . == "external_ui_download_url" or
      . == "secret"
    ) | not)
' "$config" >/dev/null

jq -e '
  . == {
    "__SOPS_SG_SERVER_HOSTNAME__": "sing-box/singapore/server-hostname",
    "__SOPS_SG_SERVER_IP__": "sing-box/singapore/server-ip",
    "__SOPS_SG_VLESS_UUID__": "sing-box/singapore/vless/uuid",
    "__SOPS_SG_VLESS_TLS_SERVER_NAME__":
      "sing-box/singapore/vless/tls-server-name",
    "__SOPS_SG_VLESS_REALITY_PUBLIC_KEY__":
      "sing-box/singapore/vless/reality-public-key",
    "__SOPS_SG_VLESS_REALITY_SHORT_ID__":
      "sing-box/singapore/vless/reality-short-id",
    "__SOPS_SG_HY2_PASSWORD__": "sing-box/singapore/hysteria2/password",
    "__SOPS_SG_HY2_OBFS_PASSWORD__":
      "sing-box/singapore/hysteria2/obfs-password",
    "__SOPS_SG_HY2_TLS_SERVER_NAME__":
      "sing-box/singapore/hysteria2/tls-server-name",
    "__SOPS_US_SERVER_HOSTNAME__": "sing-box/usa/server-hostname",
    "__SOPS_US_SERVER_IP__": "sing-box/usa/server-ip",
    "__SOPS_US_VLESS_UUID__": "sing-box/usa/vless/uuid",
    "__SOPS_US_VLESS_TLS_SERVER_NAME__":
      "sing-box/usa/vless/tls-server-name",
    "__SOPS_US_VLESS_REALITY_PUBLIC_KEY__":
      "sing-box/usa/vless/reality-public-key",
    "__SOPS_US_VLESS_REALITY_SHORT_ID__":
      "sing-box/usa/vless/reality-short-id",
    "__SOPS_US_HY2_PASSWORD__": "sing-box/usa/hysteria2/password",
    "__SOPS_US_HY2_OBFS_PASSWORD__":
      "sing-box/usa/hysteria2/obfs-password",
    "__SOPS_US_HY2_TLS_SERVER_NAME__":
      "sing-box/usa/hysteria2/tls-server-name"
  }
' "$secret_map" >/dev/null

map_markers="$(jq -c '[keys[]] | sort' "$secret_map")"
config_markers="$(
  {
    jq -r '.. | strings' "$config"
    jq -r '.. | objects | keys[]' "$config"
  } \
    | rg -o '__SOPS_[A-Z0-9_]+__' \
    | jq -Rsc 'split("\n")[:-1]'
)"
jq -en --argjson expected "$map_markers" --argjson actual "$config_markers" '
  ($actual | unique | sort) == $expected and
  ($expected | all(
    . as $marker |
    ([ $actual[] | select(. == $marker) ] | length) ==
      (if ($marker | endswith("_SERVER_HOSTNAME__")) then 4 else 1 end)
  ))
' >/dev/null

bash -n "$repo_dir/scripts/check-sing-box-config.sh"
