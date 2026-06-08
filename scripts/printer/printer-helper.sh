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

# 路由分发
case "$1" in
    scan)         cmd_scan ;;
    clear)        cmd_clear_and_restart ;;
    add)          cmd_add "$@" ;;
    list)         cmd_list_installed ;;
    delete)       cmd_delete_printer "$@" ;;
    setdefault)   cmd_set_default "$@" ;;
    jobs)         cmd_list_jobs ;;
    *)            echo "Usage: $0 {scan|clear|add|list|delete|setdefault|jobs}" ;;
esac
