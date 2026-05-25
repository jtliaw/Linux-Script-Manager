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
    
    # 1. 扫描本地 USB 打印机
    if command -v lpinfo >/dev/null 2>&1; then
        lpinfo -v | grep -E "usb://" | while read -r line; do
            local uri=$(echo "$line" | awk '{print $2}')
            local raw_name=$(echo "$uri" | sed -e 's|usb://||' -e 's|/.*||' -e 's|?.*||' | tr '[:lower:]' '[:upper:]')
            if [ -z "$raw_name" ]; then raw_name="USB_Printer"; fi
            local clean_name=$(echo "$raw_name" | tr -cd '[:alnum:]_')
            echo "KIND:USB|URI:${uri}|NAME:${clean_name}|INFO:本地直连 USB 打印机 (${clean_name//_/ })"
        done
    fi

    # 2. 扫描网络 IPP 打印机 (保持原始 IP 命名，不破坏格式)
    if command -v lpinfo >/dev/null 2>&1; then
        lpinfo -v | grep -E "(ipp://|dnssd://|http://|https://)" | while read -r line; do
            local uri=$(echo "$line" | awk '{print $2}')
            local host=$(echo "$uri" | sed -e 's|[^/]*//||' -e 's|/.*||')
            # 净化名称，把点和冒号换成下划线，符合 CUPS 规范
            local clean_host=$(echo "$host" | tr '.:' '__')
            echo "KIND:LINUX|URI:${uri}|NAME:Net_${clean_host}|INFO:Linux共享/独立网络打印机 (IPP)"
        done
    fi

    # 3. 扫描 Windows 共享打印机
    # 优先用 smbclient -L（更通用），smbtree 已在多数现代系统中弃用
    local smb_tool=""
    if command -v smbclient >/dev/null 2>&1; then
        smb_tool="smbclient"
    elif command -v smbtree >/dev/null 2>&1; then
        smb_tool="smbtree"
    fi

    # 辅助函数：根据主机名/共享名自动解析真实 IP
    # 优先 nmblookup（Samba 广播），其次 getent hosts（系统 DNS/hosts），
    # 都查不到则返回空字符串，让调用方决定是否回退到手动输入
    _resolve_win_ip() {
        local hostname="$1"
        local resolved=""
        if command -v nmblookup >/dev/null 2>&1; then
            resolved=$(nmblookup "$hostname" 2>/dev/null \
                | grep -v "querying\|failed\|^$" \
                | awk '{print $1}' \
                | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
                | grep -v "^0\." \
                | head -1)
        fi
        if [ -z "$resolved" ]; then
            resolved=$(getent hosts "$hostname" 2>/dev/null | awk '{print $1}' | head -1)
        fi
        echo "$resolved"
    }

    if [ "$smb_tool" == "smbclient" ]; then
        # smbclient -N -L localhost 通过本机 Samba browse list 汇聚局域网共享，
        # 扫到的 SERVER 字段就是 Windows 主机名，再用 nmblookup 解析成 IP
        # grep -i "Printer" 匹配 Type 列为 Printer 的行，
        # 但必须排除 print$（Windows 驱动管理共享，不是真正打印机队列）
        smbclient -N -L "localhost" 2>/dev/null \
            | grep -i "Printer" \
            | grep -iv 'print\$' \
            | while read -r line; do
            local share_name
            share_name=$(echo "$line" | awk '{print $1}')
            local comment
            comment=$(echo "$line" | awk '{$1=""; $2=""; print $0}' | sed 's/^ *//')
            # 跳过空名、print$、IPC$、ADMIN$ 等系统隐藏共享（名字含 $ 结尾的都过滤）
            [ -z "$share_name" ] && continue
            echo "$share_name" | grep -q '\$' && continue
            local clean_share
            clean_share=$(echo "$share_name" | tr -cd '[:alnum:]_-')

            # 尝试从 smbclient 的 Server 列表中找到该共享所属的主机名
            local win_host
            win_host=$(smbclient -N -L "localhost" 2>/dev/null \
                | awk '/^[ \t]*Server[ \t]/{found=1} found && /'"$share_name"'/{print; exit}' \
                | awk '{print $1}')
            # 退化：直接用共享名当主机名尝试解析（适合主机名与共享名相同的情况）
            [ -z "$win_host" ] && win_host="$share_name"

            local win_ip
            win_ip=$(_resolve_win_ip "$win_host")

            if [ -n "$win_ip" ]; then
                echo "KIND:WINDOWS|URI:smb://${win_ip}/${share_name}|NAME:Win_${clean_share}|INFO:Windows 共享打印机 @ ${win_ip} [${comment}]"
            else
                # 解析不到 IP，带 SCAN_PLACEHOLDER，GUI 侧会提示用户手动确认
                echo "KIND:WINDOWS|URI:smb://SCAN_PLACEHOLDER/${share_name}|NAME:Win_${clean_share}|INFO:Windows 共享打印机（IP待确认）[${comment}]"
            fi
        done
    elif [ "$smb_tool" == "smbtree" ]; then
        # smbtree 输出格式为 \\WORKGROUP\HOSTNAME\SHARENAME，能直接提取主机名
        smbtree -N 2>/dev/null | grep -i "Printer" | grep -iv 'print\$' | while read -r line; do
            local share_name
            share_name=$(echo "$line" | awk '{print $1}')
            local comment
            comment=$(echo "$line" | cut -d'[' -f2 | cut -d']' -f1)
            [ -z "$share_name" ] && continue
            echo "$share_name" | grep -q '\$' && continue
            # 从 \\WORKGROUP\HOSTNAME 路径提取主机名
            local win_host
            win_host=$(echo "$line" | awk '{print $1}' | sed 's|\\\\[^\\]*\\||' | cut -d'\' -f1)
            local clean_share
            clean_share=$(echo "$share_name" | tr -cd '[:alnum:]_-')

            local win_ip
            win_ip=$(_resolve_win_ip "$win_host")

            if [ -n "$win_ip" ]; then
                echo "KIND:WINDOWS|URI:smb://${win_ip}/${share_name}|NAME:Win_${clean_share}|INFO:Windows 共享打印机 @ ${win_ip} [${comment}]"
            else
                echo "KIND:WINDOWS|URI:smb://SCAN_PLACEHOLDER/${share_name}|NAME:Win_${clean_share}|INFO:Windows 共享打印机（IP待确认）[${comment}]"
            fi
        done
    else
        # 工具缺失时输出一条占位提示，让 GUI 侧能给用户说明
        echo "KIND:WINDOWS|URI:smb://SCAN_PLACEHOLDER/ManualEntry|NAME:Win_手动填写|INFO:未检测到 smbclient，请手动输入 IP 与共享名"
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
    
    # 核心隔离逻辑：只有 USB 直连才需要去找本地 PPD 驱动
    # 网络 IPP 打印机默认全部使用 "-m everywhere" (无驱动通用协议)
    local driver_param="-m everywhere" 
    
    if [ "$kind" == "USB" ]; then
        # 提取真正的硬件型号数字（因为是 USB 名字，此时里面不会有 IP 地址干扰）
        local model_num=$(echo "$name" | tr -cd '0-9')
        local brand=$(echo "$name" | cut -d'_' -f1 | tr '[:upper:]' '[:lower:]')
        
        echo "DEBUG: 启动 USB 硬件匹配 -> 品牌: $brand, 型号数字: $model_num"
        
        if command -v lpinfo >/dev/null 2>&1; then
            local best_ppd=""
            
            if [ -n "$model_num" ]; then
                best_ppd=$(lpinfo -m | grep -i "$brand" | grep "$model_num" | grep -i "gutenprint" | awk 'NR==1 {print $1}')
            fi
            if [ -z "$best_ppd" ] && [ -n "$model_num" ]; then
                best_ppd=$(lpinfo -m | grep -i "$brand" | grep "$model_num" | awk 'NR==1 {print $1}')
            fi
            if [ -z "$best_ppd" ] && [ "$brand" == "canon" ]; then
                best_ppd=$(lpinfo -m | grep -i "gutenprint" | grep -i "pixma" | awk 'NR==1 {print $1}')
            fi

            if [ -n "$best_ppd" ]; then
                driver_param="-m $best_ppd"
                echo "DEBUG: USB 成功对齐专属驱动 -> $best_ppd"
            else
                driver_param="-m generic.ppd"
                echo "DEBUG: USB 采用标准通用模式脱困"
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

# 路由分发
case "$1" in
    scan)     cmd_scan ;;
    clear)    cmd_clear_and_restart ;;
    add)      cmd_add "$@" ;;
    *)        echo "Usage: $0 {scan|clear|add}" ;;
esac
