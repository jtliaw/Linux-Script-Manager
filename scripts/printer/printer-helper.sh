#!/bin/bash
# printer-helper.sh
# 描述: 打印机管理工具底层 - 修复网络打印机被数字切片误伤的问题，实现 USB 与网络完美共存

set +e

# ─── 🛠️ 完美的底层提权状态绝对路径锚定 ───
HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==========================================
# 核心功能 1：全网与本地深度扫描
# ==========================================
cmd_scan() {
    echo "===SCAN_START==="

    # ── 公共工具函数 ─────────────────────────────────────────────────────

    # URL 解码（把 %20 等转回普通字符）
    _urldecode() {
        echo "$1" | python3 -c "
import sys, urllib.parse
print(urllib.parse.unquote(sys.stdin.read().strip()))
" 2>/dev/null || echo "$1" | sed 's/%20/ /g; s/%2F/\//g; s/%28/(/g; s/%29/)/g'
    }

    # 从打印机全名（如 "Canon G2010 series"）提取品牌和型号
    # 输出两行：BRAND:xxx 和 MODEL:xxx
    _extract_brand_model() {
        local full_name="$1"
        local brand="" model=""

        # 已知品牌列表（按长名优先，避免 "hp" 误匹配 "sharp"）
        local -a BRANDS=(
            "canon" "epson" "hewlett.packard" "hp" "brother"
            "samsung" "xerox" "lexmark" "kyocera" "ricoh"
            "fuji" "sharp" "panasonic" "oki" "konica"
        )
        local name_lower
        name_lower=$(echo "$full_name" | tr '[:upper:]' '[:lower:]')

        for b in "${BRANDS[@]}"; do
            if echo "$name_lower" | grep -qi "$b"; then
                # 规范化品牌名
                case "$b" in
                    "hewlett.packard") brand="HP" ;;
                    "hp")              brand="HP" ;;
                    *)  brand=$(echo "$b" | sed 's/\.//' | \
                            awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}') ;;
                esac
                break
            fi
        done

        # 型号：去掉品牌名、去掉 "series/printer/共享" 等通用词后的剩余
        model=$(echo "$full_name" \
            | sed -E 's/[Cc]anon|[Ee]pson|[Hh][Pp]|[Hh]ewlett.?[Pp]ackard|[Bb]rother|[Ss]amsung|[Xx]erox|[Ll]exmark|[Kk]yocera|[Rr]icoh//gI' \
            | sed -E 's/[Ss]eries|[Pp]rinter|[Ss]hared|[Nn]etwork|[Ww]ireless|[Cc]olor|打印机//gI' \
            | sed 's/^ *//; s/ *$//' \
            | tr -s ' ')

        echo "BRAND:${brand}|MODEL:${model}"
    }

    # 1. 扫描本地 USB 打印机
    if command -v lpinfo >/dev/null 2>&1; then
        lpinfo -v | grep -E "usb://" | while read -r line; do
            local uri raw_brand raw_model decoded_brand decoded_model
            uri=$(echo "$line" | awk '{print $2}')
            # USB URI 格式：usb://Canon/G2010%20series?serial=xxx
            # 第一段路径 = 品牌，第二段路径（去掉?后缀）= 型号
            raw_brand=$(echo "$uri" | sed 's|usb://||' | cut -d'/' -f1)
            raw_model=$(echo "$uri" | sed 's|usb://[^/]*/||' | sed 's|?.*||')
            decoded_brand=$(_urldecode "$raw_brand")
            decoded_model=$(_urldecode "$raw_model")
            local full_name="${decoded_brand} ${decoded_model}"
            local bm
            bm=$(_extract_brand_model "$full_name")
            local brand model
            brand=$(echo "$bm" | cut -d'|' -f1 | sed 's/BRAND://')
            model=$(echo "$bm" | cut -d'|' -f2 | sed 's/MODEL://')
            [ -z "$brand" ] && brand="$decoded_brand"
            [ -z "$model" ] && model="$decoded_model"
            local clean_name
            clean_name=$(echo "${decoded_brand}_${decoded_model}" | tr -cd '[:alnum:]_' | tr ' ' '_')
            [ -z "$clean_name" ] && clean_name="USB_Printer"
            echo "KIND:USB|URI:${uri}|NAME:${clean_name}|INFO:本地直连 USB 打印机 (${full_name})|BRAND:${brand}|MODEL:${model}"
        done
    fi

    # 2. 扫描网络 IPP 打印机
    if command -v lpinfo >/dev/null 2>&1; then
        lpinfo -v | grep -E "(ipp://|dnssd://|http://|https://)" | while read -r line; do
            local uri host decoded_host full_name bm brand model clean_name
            uri=$(echo "$line" | awk '{print $2}')
            # dnssd URI 格式：dnssd://Canon%20G2010%20series._ipp._tcp.local/...
            # ipp URI 格式：ipp://192.168.0.9:631/printers/EPSON_L3210_Series
            host=$(echo "$uri" | sed -e 's|[^/]*//||' -e 's|/.*||' -e 's|:.*||')
            decoded_host=$(_urldecode "$host")
            # 对 dnssd，主机名本身就是打印机全名（去掉 ._ipp._tcp.local 后缀）
            if echo "$uri" | grep -q "dnssd://"; then
                full_name=$(echo "$decoded_host" \
                    | sed 's/\._ipp\._tcp\.local$//' \
                    | sed 's/\._ipps\._tcp\.local$//' \
                    | sed 's/\._printer\._tcp\.local$//')
            else
                # ipp://IP/printers/PRINTER_NAME → 取最后一段
                full_name=$(echo "$uri" | sed 's|.*/||' | tr '_' ' ' | _urldecode)
            fi
            bm=$(_extract_brand_model "$full_name")
            brand=$(echo "$bm" | cut -d'|' -f1 | sed 's/BRAND://')
            model=$(echo "$bm" | cut -d'|' -f2 | sed 's/MODEL://')
            clean_name=$(echo "$full_name" | tr -cd '[:alnum:]_' | tr ' ' '_')
            [ -z "$clean_name" ] && clean_name=$(echo "$host" | tr '.:' '__')
            echo "KIND:LINUX|URI:${uri}|NAME:Net_${clean_name}|INFO:Linux共享/独立网络打印机 (${full_name})|BRAND:${brand}|MODEL:${model}"
        done
    fi

    # 3. 扫描 Windows 共享打印机
    if ! command -v smbclient >/dev/null 2>&1; then
        echo "KIND:WINDOWS|URI:smb://SCAN_PLACEHOLDER/ManualEntry|NAME:Win_手动填写|INFO:未检测到 smbclient，请安装 samba-client 后重试|BRAND:|MODEL:"
    else
        local _ip_seen_file _result_file
        _ip_seen_file=$(mktemp /tmp/printer_scan_XXXXXX)
        _result_file=$(mktemp /tmp/printer_result_XXXXXX)

        _probe_host() {
            local host_ip="$1"
            local host_name="${2:-$host_ip}"
            grep -qxF "$host_ip" "$_ip_seen_file" 2>/dev/null && return
            echo "$host_ip" >> "$_ip_seen_file"
            local smb_out
            smb_out=$(smbclient -N -L "$host_ip" --timeout=3 2>/dev/null)
            [ -z "$smb_out" ] && return
            echo "$smb_out" \
                | grep -i "Printer" \
                | grep -iv 'print\$' \
                | while IFS= read -r line; do
                local share_name comment clean_share full_name bm brand model
                share_name=$(echo "$line" | awk '{print $1}')
                # comment 字段通常是 "Canon G2010 series" 这样的完整名称
                comment=$(echo "$line" | awk '{$1=""; $2=""; print $0}' | sed 's/^ *//')
                [ -z "$share_name" ] && continue
                echo "$share_name" | grep -q '\$' && continue
                clean_share=$(echo "$share_name" | tr -cd '[:alnum:]_-')
                [ -z "$clean_share" ] && continue
                # 优先用 comment 提取品牌型号，comment 为空则用共享名
                full_name="${comment:-$share_name}"
                bm=$(_extract_brand_model "$full_name")
                brand=$(echo "$bm" | cut -d'|' -f1 | sed 's/BRAND://')
                model=$(echo "$bm" | cut -d'|' -f2 | sed 's/MODEL://')
                echo "KIND:WINDOWS|URI:smb://${host_ip}/${share_name}|NAME:Win_${clean_share}|INFO:Windows 共享打印机 @ ${host_name} (${host_ip}) - ${full_name}|BRAND:${brand}|MODEL:${model}" \
                    >> "$_result_file"
            done
        }

        echo "SCAN_PHASE:AVAHI"
        if command -v avahi-browse >/dev/null 2>&1; then
            while IFS= read -r avahi_line; do
                local avahi_ip avahi_name
                avahi_ip=$(echo "$avahi_line"   | awk -F';' '$3=="IPv4"{print $8}')
                avahi_name=$(echo "$avahi_line" | awk -F';' '{print $4}')
                [ -n "$avahi_ip" ] && _probe_host "$avahi_ip" "$avahi_name"
            done < <(avahi-browse -rtp _smb._tcp 2>/dev/null \
                     | grep '^=' | grep 'IPv4' | grep -v '127\.0\.0\.1')
        fi

        echo "SCAN_PHASE:NMBLOOKUP"
        if command -v nmblookup >/dev/null 2>&1; then
            while IFS= read -r nb_line; do
                local nb_ip
                nb_ip=$(echo "$nb_line" | awk '{print $1}')
                echo "$nb_ip" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || continue
                echo "$nb_ip" | grep -qE '^(127\.|0\.)' && continue
                _probe_host "$nb_ip" ""
            done < <(nmblookup -S '*' 2>/dev/null \
                     | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
        fi

        local _local_subnet="" _subnet_prefix=""
        _local_subnet=$(ip -4 route show scope link 2>/dev/null \
            | grep -v '^127\.' | grep -v 'linkdown' \
            | awk '{print $1}' \
            | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$' | head -1)
        if [ -n "$_local_subnet" ]; then
            _subnet_prefix=$(echo "$_local_subnet" | awk -F'.' '{print $1"."$2"."$3}')
        fi

        if [ -n "$_subnet_prefix" ]; then
            echo "SCAN_PHASE:SUBNET:${_subnet_prefix}.0/24"
            local _job_count=0
            for _last_octet in $(seq 1 254); do
                local _target_ip="${_subnet_prefix}.${_last_octet}"
                ip addr show 2>/dev/null | grep -qF "$_target_ip" && continue
                _probe_host "$_target_ip" "" &
                _job_count=$((_job_count + 1))
                if [ "$_job_count" -ge 20 ]; then
                    wait; _job_count=0
                fi
            done
            wait
        fi

        if [ -s "$_result_file" ]; then
            cat "$_result_file"
        else
            echo "KIND:WINDOWS|URI:smb://SCAN_PLACEHOLDER/ManualEntry|NAME:Win_手动填写|INFO:局域网内未发现 Windows 共享打印机（请检查防火墙/共享设置，或手动输入 IP）|BRAND:|MODEL:"
        fi
        rm -f "$_ip_seen_file" "$_result_file"
    fi

    echo "===SCAN_END==="
}

# ==========================================
# 核心功能 2：强力清洗任务并重启 CUPS
# ==========================================
cmd_clear_and_restart() {
    echo "===CLEAR_START==="
    local task_count=0
    if command -v lpstat >/dev/null 2>&1; then
        task_count=$(lpstat -o 2>/dev/null | wc -l)
    fi
    echo "TASK_COUNT:${task_count}"

    if command -v cancel >/dev/null 2>&1; then
        cancel -a -x >/dev/null 2>&1
    fi

    systemctl stop cups >/dev/null 2>&1
    if [ -d "/var/spool/cups" ]; then
        rm -rf /var/spool/cups/d* >/dev/null 2>&1
        rm -rf /var/spool/cups/c* >/dev/null 2>&1
        rm -rf /var/spool/cups/tmp/* >/dev/null 2>&1
    fi
    systemctl start cups >/dev/null 2>&1
    
    echo "STATUS:SUCCESS"
    echo "===CLEAR_END==="
}

# ==========================================
# 核心功能 3：一键智能匹配驱动并添加打印机
# ==========================================
cmd_add() {
    local name="$2"
    local kind="$3"   
    local uri="$4"
    local user="$5"   
    local pass="$6"   

    if [ "$kind" == "WINDOWS" ]; then
        # 不用 sed 拼接，直接字符串替换，避免密码含特殊字符（| @ / 等）破坏 sed 表达式
        local smb_path="${uri#smb://}"   # 取 smb:// 之后的部分
        if [ -n "$user" ] && [ -n "$pass" ]; then
            uri="smb://${user}:${pass}@${smb_path}"
        elif [ -n "$user" ]; then
            uri="smb://${user}@${smb_path}"
        fi
    fi

    # 净化 CUPS 队列名称
    name=$(echo "$name" | tr -cd '[:alnum:]_')

    # ── 智能驱动匹配函数 ──────────────────────────────────────────────────
    # 输入：品牌(小写)、完整型号字符串（保留字母+数字，如 "g2010" "l3210"）
    # 输出：最佳 PPD model 字符串，找不到则返回空
    # 
    # ⚠️ 关键规则：绝对不能用纯数字(如"2010")去匹配！
    #    纯数字会误命中无关型号（如搜"2010"会匹配"BJC-2010"而非"G2010"）
    # ─────────────────────────────────────────────────────────────────────
    _find_best_ppd() {
        local brand="$1"
        local model_hint="$2"   # 保留字母数字混合，如 "g2010" "l3210" "pixmag2010"
        local best=""

        if ! command -v lpinfo >/dev/null 2>&1; then echo ""; return; fi

        # ── 型号别名映射表 ────────────────────────────────────────────────
        # 当 gutenprint 没有收录某型号时，映射到最兼容的替代型号
        # 格式：原型号小写=替代型号小写
        # Canon G 系列（墨仓机）：G2010/G3010/G4010 是 G2000/G3000/G4000 的亚洲版
        declare -A _alias_map=(
            ["g2010"]="g2000"
            ["g3010"]="g3000"
            ["g4010"]="g4000"
            ["g2012"]="g2000"
            ["g3012"]="g3000"
            ["g2020"]="g2010 g2000"
            ["g3020"]="g3010 g3000"
            ["g2060"]="g2000"
            ["g3060"]="g3000"
            ["g2160"]="g2000"
            ["g3160"]="g3000"
            # Epson EcoTank 别名（L系列区域版本差异）
            ["l3250"]="l3200 l3150"
            ["l3260"]="l3200 l3150"
            ["l3210"]="l3200 l3150"
            ["l3211"]="l3200 l3150"
            ["l3110"]="l3100"
            ["l5190"]="l5180"
            ["l6170"]="l6160"
        )

        # 缓存 lpinfo -m 输出避免多次调用（lpinfo 较慢）
        local _ppd_list
        _ppd_list=$(lpinfo -m 2>/dev/null)

        # ── 内部搜索函数（复用逻辑）─────────────────────────────────────
        _search_ppd() {
            local b="$1" m="$2"
            local r=""
            r=$(echo "$_ppd_list" | grep -i "$b" | grep -i "$m" | grep -i "gutenprint" | awk 'NR==1 {print $1}')
            [ -z "$r" ] && r=$(echo "$_ppd_list" | grep -i "$b" | grep -i "$m" | awk 'NR==1 {print $1}')
            echo "$r"
        }

        # ── 第1步：直接搜索原始型号 ──────────────────────────────────────
        if [ -n "$model_hint" ]; then
            best=$(_search_ppd "$brand" "$model_hint")
        fi

        # ── 第2步：查别名映射表，用替代型号搜索 ─────────────────────────
        if [ -z "$best" ] && [ -n "$model_hint" ]; then
            local aliases="${_alias_map[$model_hint]}"
            if [ -n "$aliases" ]; then
                for alt in $aliases; do
                    best=$(_search_ppd "$brand" "$alt")
                    [ -n "$best" ] && { echo "DEBUG_ALIAS: $model_hint -> $alt -> $best" >&2; break; }
                done
            fi
        fi

        # ── 第3步：Canon G系列提取 G+数字 再搜（覆盖 pixmag2010 这种拼接）
        if [ -z "$best" ] && [ "$brand" = "canon" ]; then
            local g_model
            g_model=$(echo "$model_hint" | grep -oi 'g[0-9]\{3,4\}' | head -1 | tr '[:upper:]' '[:lower:]')
            if [ -n "$g_model" ]; then
                best=$(_search_ppd "canon" "$g_model")
                # 再查别名
                if [ -z "$best" ]; then
                    local g_aliases="${_alias_map[$g_model]}"
                    for alt in $g_aliases; do
                        best=$(_search_ppd "canon" "$alt")
                        [ -n "$best" ] && break
                    done
                fi
            fi
        fi

        # ── 第4步：Epson L系列提取 L+数字 再搜 ──────────────────────────
        if [ -z "$best" ] && [ "$brand" = "epson" ]; then
            local l_model
            l_model=$(echo "$model_hint" | grep -oi 'l[0-9]\{3,4\}' | head -1 | tr '[:upper:]' '[:lower:]')
            if [ -n "$l_model" ]; then
                best=$(_search_ppd "epson" "$l_model")
                if [ -z "$best" ]; then
                    local l_aliases="${_alias_map[$l_model]}"
                    for alt in $l_aliases; do
                        best=$(_search_ppd "epson" "$alt")
                        [ -n "$best" ] && break
                    done
                fi
            fi
        fi

        # ── 第5步：品牌通用 gutenprint 兜底（仅当有明确品牌时）──────────
        if [ -z "$best" ] && [ "$brand" = "canon" ]; then
            best=$(echo "$_ppd_list" | grep -i "gutenprint" | grep -i "pixma" | awk 'NR==1 {print $1}')
        fi
        if [ -z "$best" ] && [ "$brand" = "epson" ]; then
            best=$(echo "$_ppd_list" | grep -i "gutenprint" | grep -i "epson" | awk 'NR==1 {print $1}')
        fi
        if [ -z "$best" ] && [ "$brand" = "hp" ]; then
            best=$(echo "$_ppd_list" | grep -i "hp\|hewlett" | grep -i "gutenprint" | awk 'NR==1 {print $1}')
        fi

        # ── 注意：不使用纯数字 fallback，防止误匹配（如2010->BJC-2010）──
        echo "$best"
    }

    # ── 驱动参数决策 ─────────────────────────────────────────────────────
    # LINUX/IPP：支持 driverless，用 everywhere
    # USB 和 WINDOWS SMB：必须有真实 PPD 驱动才能正常打印
    local driver_param="-m everywhere"

    # 第7个参数：GUI 可以直接传入用户手选的 PPD model 字符串，跳过自动匹配
    local manual_ppd="$7"
    if [ -n "$manual_ppd" ] && [ "$manual_ppd" != "AUTO" ]; then
        driver_param="-m $manual_ppd"
        echo "DEBUG: 使用用户手动指定驱动 -> $manual_ppd"
    elif [ "$kind" = "USB" ] || [ "$kind" = "WINDOWS" ]; then
        # 从队列名称提取品牌和型号
        # USB 队列名如 "CANON_G2010"，WINDOWS 队列名如 "Win_canon_g2010"
        local raw_name="$name"
        # 去掉 Win_ 前缀（不区分大小写）
        raw_name=$(echo "$raw_name" | sed 's/^[Ww]in_//')
        # 品牌：取开头连续纯字母段（遇到数字或下划线停止）
        local brand
        brand=$(echo "$raw_name" | sed 's/[0-9_].*//' | tr '[:upper:]' '[:lower:]')
        # 型号：去掉品牌前缀后的完整剩余（保留字母+数字，如 g2010、l3210）
        local model_hint
        model_hint=$(echo "$raw_name" | sed "s/^${brand}[_]*//i" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')

        echo "DEBUG: 驱动匹配 -> kind=$kind, brand=$brand, model_hint=$model_hint"

        local best_ppd
        best_ppd=$(_find_best_ppd "$brand" "$model_hint")

        if [ -n "$best_ppd" ]; then
            driver_param="-m $best_ppd"
            echo "DEBUG: 成功匹配驱动 -> $best_ppd"
        else
            # SMB 打印机找不到驱动时用 raw，至少能连通，比 everywhere 更兼容
            if [ "$kind" = "WINDOWS" ]; then
                driver_param="-m raw"
                echo "DEBUG: WINDOWS 未找到专属驱动，降级为 raw 模式"
            else
                driver_param="-m generic.ppd"
                echo "DEBUG: USB 未找到专属驱动，降级为 generic.ppd"
            fi
        fi
    fi

    # 强行移除可能残余的同名队列
    lpadmin -x "$name" >/dev/null 2>&1

    # 向 CUPS 提交配置命令
    echo "DEBUG: 最终提交 CUPS 指令: lpadmin -p $name -v $uri -E $driver_param"
    lpadmin -p "$name" -v "$uri" -E $driver_param >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo "ADD_STATUS:SUCCESS"
    else
        # 终极硬核网络保底 (去掉驱动限制尝试直接握手)
        lpadmin -p "$name" -v "$uri" -E >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "ADD_STATUS:SUCCESS"
        else
            echo "ADD_STATUS:FAILED"
        fi
    fi
}

# ==========================================
# 核心功能 4：列出系统中已安装的打印机
# ==========================================
cmd_list_installed() {
    echo "===LIST_START==="
    if command -v lpstat >/dev/null 2>&1; then
        # ── 获取默认打印机名称（多策略，兼容中/英文 locale）───────────────
        # 注意：中文系统 lpstat -d 使用全角冒号"："，awk -F: 无法分割
        # 策略1：用 sed 删除已知前缀（英文/中文），取剩余部分
        local default_printer
        default_printer=$(lpstat -d 2>/dev/null \
            | sed 's/^system default destination:[[:space:]]*//' \
            | sed 's/^系统默认目标[：:][[:space:]]*//' \
            | sed 's/^系统默认目的[：:][[:space:]]*//' \
            | tr -d ' \t\r\n')

        # 策略2：/etc/cups/lpoptions（最可靠，不受 locale 影响）
        if [ -z "$default_printer" ] && [ -f /etc/cups/lpoptions ]; then
            default_printer=$(grep -i '^Default ' /etc/cups/lpoptions 2>/dev/null \
                              | awk '{print $2}' | tr -d ' \t\r\n')
        fi

        # 策略3：~/.cups/lpoptions（用户级默认）
        if [ -z "$default_printer" ] && [ -f "$HOME/.cups/lpoptions" ]; then
            default_printer=$(grep -i '^Default ' "$HOME/.cups/lpoptions" 2>/dev/null \
                              | awk '{print $2}' | tr -d ' \t\r\n')
        fi

        # 策略4：如果以上都失败，用 python3 解析（处理全角冒号最保险）
        if [ -z "$default_printer" ] && command -v python3 >/dev/null 2>&1; then
            default_printer=$(python3 -c "
import subprocess, sys
try:
    out = subprocess.check_output(['lpstat','-d'], text=True, stderr=subprocess.DEVNULL)
    # 去掉已知前缀（英文或中文，全角/半角冒号均处理）
    line = out.strip()
    for sep in ['system default destination:', '系统默认目标：', '系统默认目标:', '系统默认目的：', '系统默认目的:']:
        if line.startswith(sep):
            print(line[len(sep):].strip())
            sys.exit(0)
    # 找最后一个冒号（全角或半角）后的部分
    for ch in ['：', ':']:
        if ch in line:
            print(line.rsplit(ch, 1)[-1].strip())
            sys.exit(0)
except Exception:
    pass
" 2>/dev/null | tr -d ' \t\r\n')
        fi

        # 调试信息（GUI 解析此行用于状态栏提示）
        echo "DEBUG_DEFAULT:${default_printer}"

        # ── 遍历打印机（用进程替换，避免管道子 shell 丢失变量）────────────
        while read -r line; do
            local pname uri state job_count is_default pname_clean default_clean
            pname=$(echo "$line" | awk '{print $2}')
            [ -z "$pname" ] && continue

            uri=$(lpstat -v "$pname" 2>/dev/null | awk '{print $NF}')

            state="就绪"
            echo "$line" | grep -qi "disabled\|停用\|不可用" && state="已停用"
            echo "$line" | grep -qi "idle\|空闲"             && state="空闲"

            job_count=$(lpstat -o "$pname" 2>/dev/null | wc -l | tr -d ' ')

            # 匹配策略：先精确比较，再做子串包含匹配
            # 原因：CUPS implicitclass 会把多台打印机名拼成超长类名
            # lpstat -d 可能返回 "Net_EPSONA_Net_EPSONB" 这类合并名
            # 只要打印机名出现在默认目标字符串中即视为默认
            pname_clean=$(echo "$pname"             | tr -d ' \t\r\n')
            default_clean=$(echo "$default_printer" | tr -d ' \t\r\n')
            is_default="NO"
            if [ -n "$default_clean" ]; then
                # 精确匹配
                if [ "$pname_clean" = "$default_clean" ]; then
                    is_default="YES"
                # 子串匹配：默认目标名包含此打印机名
                elif echo "$default_clean" | grep -qF "$pname_clean"; then
                    is_default="YES"
                # 反向：打印机名包含默认目标名（短目标名匹配长打印机名）
                elif echo "$pname_clean" | grep -qF "$default_clean"; then
                    is_default="YES"
                fi
            fi

            echo "PRINTER:${pname}|URI:${uri}|STATE:${state}|JOBS:${job_count}|DEFAULT:${is_default}"
        done < <(lpstat -p 2>/dev/null)
    fi
    echo "===LIST_END==="
}

# ==========================================
# 核心功能 7：设置默认打印机
# ==========================================
cmd_set_default() {
    local name="$2"
    echo "===SETDEFAULT_START==="
    if [ -z "$name" ]; then
        echo "SETDEFAULT_STATUS:FAILED|REASON:未提供打印机名称"
        echo "===SETDEFAULT_END==="
        return 1
    fi
    # lpadmin -d 设置系统默认打印机（需要 root）
    lpadmin -d "$name" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "SETDEFAULT_STATUS:SUCCESS"
    else
        echo "SETDEFAULT_STATUS:FAILED|REASON:lpadmin 返回错误，请确认打印机名称是否正确"
    fi
    echo "===SETDEFAULT_END==="
}

# ==========================================
# 核心功能 5：删除指定打印机
# ==========================================
cmd_delete_printer() {
    local name="$2"
    echo "===DELETE_START==="
    if [ -z "$name" ]; then
        echo "DELETE_STATUS:FAILED|REASON:未提供打印机名称"
        echo "===DELETE_END==="
        return 1
    fi
    # 先取消该打印机的所有任务，再删除
    cancel -a "$name" >/dev/null 2>&1
    lpadmin -x "$name" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "DELETE_STATUS:SUCCESS"
    else
        echo "DELETE_STATUS:FAILED|REASON:lpadmin 返回错误，请确认打印机名称"
    fi
    echo "===DELETE_END==="
}

# ==========================================
# 核心功能 6：列出所有打印机的未完成任务
# ==========================================
cmd_list_jobs() {
    echo "===JOBS_START==="
    if ! command -v lpstat >/dev/null 2>&1; then
        echo "JOBS_ERROR:lpstat 未找到，请确认 CUPS 已安装"
        echo "===JOBS_END==="
        return 1
    fi

    # lpstat -o 列出所有队列的挂起任务；-l 输出详情
    local raw
    raw=$(lpstat -o 2>/dev/null)

    if [ -z "$raw" ]; then
        echo "NO_JOBS"
        echo "===JOBS_END==="
        return 0
    fi

    echo "$raw" | while IFS= read -r line; do
        # 行格式：  PrinterName-JobID  owner  size  date  time
        [ -z "$line" ] && continue
        local job_id printer_name owner size_kb date_str time_str stuck_flag

        job_id=$(echo "$line"    | awk '{print $1}')          # e.g. HP_LaserJet-42
        owner=$(echo "$line"     | awk '{print $2}')
        size_kb=$(echo "$line"   | awk '{print $3}')
        date_str=$(echo "$line"  | awk '{print $4}')
        time_str=$(echo "$line"  | awk '{print $5}')

        # 提取打印机名（Job ID 中短横线前的部分，但打印机名本身可能含 -，取最后一段数字前的部分）
        printer_name=$(echo "$job_id" | sed 's/-[0-9]*$//')

        # 判断是否疑似卡住：任务提交时间超过 30 分钟且状态不是正在打印
        stuck_flag="NO"
        local job_state
        job_state=$(lpstat -l 2>/dev/null | grep -A5 "^$job_id" | grep -i "状态\|status\|State" | head -1)
        # 通过 cups job 时间戳判断（用 date 工具）
        if [ -n "$date_str" ] && [ -n "$time_str" ]; then
            local job_epoch now_epoch age_min
            job_epoch=$(date -d "${date_str} ${time_str}" +%s 2>/dev/null || echo 0)
            now_epoch=$(date +%s)
            if [ "$job_epoch" -gt 0 ]; then
                age_min=$(( (now_epoch - job_epoch) / 60 ))
                if [ "$age_min" -gt 30 ]; then
                    stuck_flag="YES"
                fi
            fi
        fi

        echo "JOB:${job_id}|PRINTER:${printer_name}|OWNER:${owner}|SIZE:${size_kb}|WHEN:${date_str} ${time_str}|STUCK:${stuck_flag}"
    done

    echo "===JOBS_END==="
}

# ==========================================
# 核心功能 6：列出可用 PPD 驱动（供 GUI 驱动选择器使用）
# 用法：printer-helper.sh listppd <brand_keyword>
# 输出：每行 "PPD_MODEL|DISPLAY_NAME"
# ==========================================
cmd_list_ppd() {
    local keyword="${2:-}"   # 第2个参数：品牌关键词，如 "canon"
    echo "===PPD_START==="
    if ! command -v lpinfo >/dev/null 2>&1; then
        echo "===PPD_END==="
        return
    fi
    lpinfo -m 2>/dev/null \
        | grep -i "$keyword" \
        | while IFS= read -r ppd_line; do
            local ppd_model ppd_display
            ppd_model=$(echo "$ppd_line" | awk '{print $1}')
            ppd_display=$(echo "$ppd_line" | cut -d' ' -f2- | sed 's/^ *//')
            [ -z "$ppd_model" ] && continue
            echo "PPD:${ppd_model}|LABEL:${ppd_display}"
        done
    echo "===PPD_END==="
}

# 路由分发
case "$1" in
    scan)         cmd_scan ;;
    clear)        cmd_clear_and_restart ;;
    add)          cmd_add "$@" ;;
    list)         cmd_list_installed ;;
    delete)       cmd_delete_printer "$@" ;;
    setdefault)   cmd_set_default "$@" ;;
    jobs)         cmd_list_jobs ;;
    listppd)      cmd_list_ppd "$@" ;;
    *)            echo "Usage: $0 {scan|clear|add|list|delete|setdefault|jobs|listppd}" ;;
esac
