#!/bin/bash
# WiFi Power Manager
# DESCRIPTION: WiFi 电源模式管理工具 - 查看与调整 WiFi 省电/性能设置
# REQUIRES_SUDO: true

set +e   # 不用 set -e：脚本大量依赖非零返回码做判断（grep、((...))、is_usb等），
         # set -e 会把"找不到/为假"误判为致命错误并中途退出

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
PURPLE='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

wait_for_exit() {
    local seconds=${1:-5}
    local code=${2:-0}   # 第二参数为退出码，默认 0；错误情况传 1
    echo ""
    echo -e "${BLUE}[INFO]${NC} 脚本将在 ${seconds} 秒后自动退出..."
    sleep $seconds
    exit $code
}

print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
print_step()    { echo -e "${CYAN}➜${NC} $1"; }
print_header()  { echo -e "${WHITE}$1${NC}"; }

###############################################################################
# 工具检查
###############################################################################

check_dependencies() {
    local missing=()
    command -v iwconfig >/dev/null 2>&1 || missing+=("iwconfig (wireless-tools)")
    command -v iw       >/dev/null 2>&1 || missing+=("iw")

    if [ ${#missing[@]} -gt 0 ]; then
        print_error "缺少必要工具: ${missing[*]}"
        print_info "请先安装: sudo apt install wireless-tools iw"
        wait_for_exit 5 1   # 错误退出，返回码 1
    fi
}

###############################################################################
# 检测 WiFi 网卡
###############################################################################

detect_wifi_interface() {
    WIFI_IF=""

    # 收集所有 WiFi 接口
    local all_ifaces=()
    if command -v iw >/dev/null 2>&1; then
        while IFS= read -r line; do
            all_ifaces+=("$line")
        done < <(iw dev 2>/dev/null | awk '/Interface/{print $2}')
    fi
    if [ ${#all_ifaces[@]} -eq 0 ] && command -v iwconfig >/dev/null 2>&1; then
        while IFS= read -r line; do
            all_ifaces+=("$line")
        done < <(iwconfig 2>/dev/null | awk '/IEEE 802.11/{print $1}')
    fi

    if [ ${#all_ifaces[@]} -eq 0 ]; then
        print_error "未检测到 WiFi 网卡！"
        print_info "请确认 WiFi 已开启，且驱动已正确安装"
        wait_for_exit 5 1   # 错误退出，返回码 1
    fi

    # 只有一张网卡时直接使用
    if [ ${#all_ifaces[@]} -eq 1 ]; then
        WIFI_IF="${all_ifaces[0]}"
        print_info "检测到 WiFi 网卡: ${WIFI_IF}"
        return
    fi

    # 多张网卡时列出让用户选择
    echo ""
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "   检测到多张 WiFi 网卡，请选择要管理的网卡"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    local idx=1
    for iface in "${all_ifaces[@]}"; do
        # 尝试取得驱动名称辅助识别
        local drv=""
        if [ -L "/sys/class/net/${iface}/device/driver" ]; then
            drv=$(readlink -f "/sys/class/net/${iface}/device/driver" 2>/dev/null | xargs basename 2>/dev/null || true)
        fi
        # 判断是否为 USB 网卡
        local bus_hint=""
        if [ -e "/sys/class/net/${iface}/device" ]; then
            local devpath
            devpath=$(readlink -f "/sys/class/net/${iface}/device" 2>/dev/null || true)
            echo "$devpath" | grep -q "usb" && bus_hint="${CYAN}[USB]${NC}" || bus_hint="${GREEN}[PCI]${NC}"
        fi
        if [ -n "$drv" ]; then
            echo -e "  ${WHITE}[${idx}]${NC} ${iface}  ${bus_hint}  驱动: ${CYAN}${drv}${NC}"
        else
            echo -e "  ${WHITE}[${idx}]${NC} ${iface}  ${bus_hint}"
        fi
        idx=$(( idx + 1 ))
    done

    echo ""
    read -p "  请输入数字选择网卡 [1-${#all_ifaces[@]}]: " iface_choice

    # 验证输入
    if [[ "$iface_choice" =~ ^[0-9]+$ ]] &&        [ "$iface_choice" -ge 1 ] &&        [ "$iface_choice" -le "${#all_ifaces[@]}" ]; then
        WIFI_IF="${all_ifaces[$(( iface_choice - 1 ))]}"
    else
        print_warning "输入无效，自动选择第一张网卡"
        WIFI_IF="${all_ifaces[0]}"
    fi

    print_info "已选择网卡: ${WIFI_IF}"
}

###############################################################################
# USB Autosuspend 管理
###############################################################################

# 找出指定网卡对应的 USB 设备路径（在 /sys/bus/usb/devices/ 下）
find_usb_device_path() {
    local iface="$1"
    local devpath
    devpath=$(readlink -f "/sys/class/net/${iface}/device" 2>/dev/null || true)
    [ -z "$devpath" ] && { echo ""; return; }

    # 向上追溯找到 USB 设备节点（格式如 /sys/bus/usb/devices/1-1.2）
    local p="$devpath"
    while [ -n "$p" ] && [ "$p" != "/" ]; do
        # USB 设备目录特征：包含 idVendor 文件
        if [ -f "${p}/idVendor" ]; then
            echo "$p"
            return
        fi
        p=$(dirname "$p")
    done
    echo ""
}

# 判断网卡是否为 USB 设备
is_usb_wifi() {
    local iface="$1"
    local devpath
    devpath=$(readlink -f "/sys/class/net/${iface}/device" 2>/dev/null || true)
    echo "$devpath" | grep -q "usb" && echo "yes" || echo "no"
}

# 读取 USB autosuspend 当前状态
get_usb_autosuspend() {
    local iface="$1"
    local usbpath
    usbpath=$(find_usb_device_path "$iface")
    [ -z "$usbpath" ] && { echo "unknown"; return; }

    local val
    val=$(cat "${usbpath}/power/autosuspend" 2>/dev/null || echo "unknown")
    echo "$val"
}

# 读取 USB autosuspend_delay_ms
get_usb_autosuspend_delay() {
    local iface="$1"
    local usbpath
    usbpath=$(find_usb_device_path "$iface")
    [ -z "$usbpath" ] && { echo "unknown"; return; }

    local val
    val=$(cat "${usbpath}/power/autosuspend_delay_ms" 2>/dev/null || echo "unknown")
    echo "$val"
}

# 读取 USB power/control（auto=允许休眠, on=强制开启）
get_usb_power_control() {
    local iface="$1"
    local usbpath
    usbpath=$(find_usb_device_path "$iface")
    [ -z "$usbpath" ] && { echo "unknown"; return; }

    local val
    val=$(cat "${usbpath}/power/control" 2>/dev/null || echo "unknown")
    echo "$val"
}

# 取得 USB 设备的 idVendor 和 idProduct（用于写 udev rule）
get_usb_ids() {
    local iface="$1"
    local usbpath
    usbpath=$(find_usb_device_path "$iface")
    [ -z "$usbpath" ] && { echo ""; return; }

    local vendor product
    vendor=$(cat "${usbpath}/idVendor" 2>/dev/null || echo "")
    product=$(cat "${usbpath}/idProduct" 2>/dev/null || echo "")
    echo "${vendor}:${product}"
}

# 显示 USB 状态
show_usb_status() {
    local iface="$1"

    if [ "$(is_usb_wifi "$iface")" != "yes" ]; then
        return  # 非 USB 网卡，跳过
    fi

    local autosuspend delay ctrl usb_ids usbpath
    autosuspend=$(get_usb_autosuspend "$iface")
    delay=$(get_usb_autosuspend_delay "$iface")
    ctrl=$(get_usb_power_control "$iface")
    usb_ids=$(get_usb_ids "$iface")
    usbpath=$(find_usb_device_path "$iface")

    echo ""
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "   🔌 USB 电源管理状态（USB Autosuspend）"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "  USB 设备 ID    : ${CYAN}${usb_ids:-未知}${NC}"
    [ -n "$usbpath" ] && echo -e "  USB 设备路径   : ${CYAN}${usbpath##*/sys/bus/usb/devices/}${NC}"
    echo ""

    # autosuspend 值：-1=禁用, 0=立即, >0=秒数
    local as_color as_label
    if [ "$autosuspend" = "-1" ]; then
        as_color=$GREEN; as_label="已禁用 ✓（不会自动休眠）"
    elif [ "$autosuspend" = "0" ]; then
        as_color=$RED;   as_label="立即休眠（0秒）⚠"
    elif [ "$autosuspend" = "unknown" ]; then
        as_color=$MAGENTA; as_label="未知"
    else
        as_color=$YELLOW; as_label="${autosuspend} 秒后休眠 ⚠"
    fi

    local ctrl_color ctrl_label
    if [ "$ctrl" = "on" ]; then
        ctrl_color=$GREEN; ctrl_label="强制开启 on（最稳定）"
    elif [ "$ctrl" = "auto" ]; then
        ctrl_color=$YELLOW; ctrl_label="自动管理 auto（可能休眠）"
    else
        ctrl_color=$MAGENTA; ctrl_label="${ctrl}"
    fi

    echo -e "  autosuspend    : ${as_color}${as_label}${NC}"
    echo -e "  power/control  : ${ctrl_color}${ctrl_label}${NC}"

    # 综合判断
    echo ""
    if [ "$autosuspend" = "-1" ] && [ "$ctrl" = "on" ]; then
        print_success "USB 电源管理已完全禁用，不会造成休眠延迟 ✓"
    elif [ "$autosuspend" = "-1" ] || [ "$ctrl" = "on" ]; then
        print_warning "USB 电源管理部分禁用，建议同时设置两项"
    else
        print_warning "USB 自动休眠处于启用状态！"
        print_warning "这会导致 WiFi 网卡定期断电，造成延迟突然飙升"
        print_info "建议切换到选单 [5] 禁用 USB 自动休眠"
    fi
    echo ""
}

# 禁用 USB autosuspend（即时 + 永久）
disable_usb_autosuspend() {
    local iface="$1"

    if [ "$(is_usb_wifi "$iface")" != "yes" ]; then
        print_warning "此网卡不是 USB 设备，跳过 USB autosuspend 设定"
        return
    fi

    local usbpath usb_ids
    usbpath=$(find_usb_device_path "$iface")
    usb_ids=$(get_usb_ids "$iface")
    local vendor="${usb_ids%%:*}"
    local product="${usb_ids##*:}"

    if [ -z "$usbpath" ]; then
        print_error "无法找到 USB 设备路径，请手动处理"
        return 1
    fi

    echo ""
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "   🔌 禁用 USB Autosuspend"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "  USB 设备 ID : ${CYAN}${usb_ids}${NC}"
    echo -e "  USB 路径    : ${CYAN}${usbpath}${NC}"
    echo ""

    # ── 即时写入（本次开机有效）─────────────────────────────────────
    print_step "【即时】写入 autosuspend=-1 和 power/control=on..."
    run_cmd "echo -1 > '${usbpath}/power/autosuspend'"
    run_cmd "echo on  > '${usbpath}/power/control'"
    print_success "即时设定完成（本次开机有效）"

    echo ""

    # ── 永久写入 udev rule ───────────────────────────────────────────
    if [ -n "$vendor" ] && [ -n "$product" ]; then
        local udev_file="/etc/udev/rules.d/50-wifi-usb-power.rules"
        print_step "【永久】写入 udev rule → ${udev_file}"
        run_cmd "cat > '${udev_file}' << 'EOF'
# 禁用 WiFi USB 网卡自动休眠 - 由 wifi-power.sh 写入
# USB ID: ${usb_ids}
ACTION==\"add\", SUBSYSTEM==\"usb\", ATTR{idVendor}==\"${vendor}\", ATTR{idProduct}==\"${product}\", ATTR{power/autosuspend}=\"-1\", ATTR{power/control}=\"on\"
EOF"
        print_success "udev rule 已写入，重启后永久生效 ✓"
        echo ""
        echo -e "  规则档案 : ${CYAN}${udev_file}${NC}"
        echo -e "  适用设备 : USB ID ${CYAN}${usb_ids}${NC}（仅限此网卡，兼容所有 USB WiFi）"
        echo ""
        run_cmd "udevadm control --reload-rules 2>/dev/null || true"
        print_success "udev 规则已重新加载"
    else
        print_warning "无法取得 USB Vendor/Product ID，跳过永久设定"
        print_info "请手动在 /etc/udev/rules.d/50-wifi-usb-power.rules 写入规则"
    fi
}

# 启用 USB autosuspend（恢复系统预设）
enable_usb_autosuspend() {
    local iface="$1"

    if [ "$(is_usb_wifi "$iface")" != "yes" ]; then
        print_warning "此网卡不是 USB 设备，跳过"
        return
    fi

    local usbpath usb_ids
    usbpath=$(find_usb_device_path "$iface")
    usb_ids=$(get_usb_ids "$iface")
    local vendor="${usb_ids%%:*}"
    local product="${usb_ids##*:}"

    [ -z "$usbpath" ] && { print_error "无法找到 USB 设备路径"; return 1; }

    print_step "恢复 USB autosuspend 系统预设（2秒）..."
    run_cmd "echo 2    > '${usbpath}/power/autosuspend'"
    run_cmd "echo auto > '${usbpath}/power/control'"
    print_success "即时恢复完成"

    # 移除 udev rule
    local udev_file="/etc/udev/rules.d/50-wifi-usb-power.rules"
    if [ -f "$udev_file" ]; then
        run_cmd "rm -f '${udev_file}'"
        run_cmd "udevadm control --reload-rules 2>/dev/null || true"
        print_success "已移除永久 udev rule"
    fi
}

###############################################################################
# Realtek 驱动额外参数（IPS / LPS）管理
###############################################################################

# 判断驱动是否为 Realtek 专属驱动（支援 rtw_ips_mode / rtw_lps_disable）
driver_is_realtek_oot() {
    local driver="$1"
    case "$driver" in
        # 社群 OOT 专属驱动（支援 IPS/LPS 参数）
        8821*|8852*|8832*|8192*|8188*|\
        r8192*|r8188*|\
        rtl8192*|rtl8188*|rtl88*)
            echo "yes" ;;
        # rtw88 内核驱动不支援这些参数
        rtw88*)
            echo "no" ;;
        *)
            echo "no" ;;
    esac
}

# 读取驱动当前的 IPS/LPS 参数值
get_realtek_extra_params() {
    local driver="$1"
    local ips_mode lps_disable

    ips_mode=$(cat "/sys/module/${driver}/parameters/rtw_ips_mode" 2>/dev/null || echo "N/A")
    lps_disable=$(cat "/sys/module/${driver}/parameters/rtw_lps_disable" 2>/dev/null || echo "N/A")

    echo "ips=${ips_mode} lps_disable=${lps_disable}"
}

# 显示 IPS/LPS 状态
show_rtk_extra_status() {
    local driver="$1"

    [ "$(driver_is_realtek_oot "$driver")" != "yes" ] && return

    local ips_mode lps_disable
    ips_mode=$(cat "/sys/module/${driver}/parameters/rtw_ips_mode" 2>/dev/null || echo "N/A")
    lps_disable=$(cat "/sys/module/${driver}/parameters/rtw_lps_disable" 2>/dev/null || echo "N/A")

    echo ""
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "   ⚡ Realtek 驱动内部省电参数"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    local ips_color ips_label
    if [ "$ips_mode" = "0" ]; then
        ips_color=$GREEN; ips_label="0 = 已禁用 IPS ✓"
    elif [ "$ips_mode" = "N/A" ]; then
        ips_color=$MAGENTA; ips_label="无法读取（驱动可能不支援）"
    else
        ips_color=$YELLOW; ips_label="${ips_mode} = 启用中 ⚠"
    fi

    local lps_color lps_label
    if [ "$lps_disable" = "1" ]; then
        lps_color=$GREEN; lps_label="1 = 已禁用 LPS ✓"
    elif [ "$lps_disable" = "N/A" ]; then
        lps_color=$MAGENTA; lps_label="无法读取（驱动可能不支援）"
    else
        lps_color=$YELLOW; lps_label="${lps_disable} = 启用中 ⚠"
    fi

    echo -e "  rtw_ips_mode   : ${ips_color}${ips_label}${NC}"
    echo -e "    └ IPS = 空闲省电系统（网卡闲置时自动降速）"
    echo ""
    echo -e "  rtw_lps_disable: ${lps_color}${lps_label}${NC}"
    echo -e "    └ LPS = 链路省电（AP 通知网卡进入低功耗等待）"
    echo ""

    # 综合判断
    if [ "$ips_mode" = "0" ] && [ "$lps_disable" = "1" ]; then
        print_success "Realtek IPS/LPS 已完全禁用，驱动内部省电关闭 ✓"
    elif [ "$ips_mode" != "N/A" ] || [ "$lps_disable" != "N/A" ]; then
        print_warning "Realtek 驱动内部省电仍有部分启用"
        print_info "建议切换到选单 [6] 禁用 IPS/LPS 以获得最佳稳定性"
    fi
    echo ""
}

# 写入 IPS/LPS 禁用参数到 modprobe conf
disable_rtk_ips_lps() {
    local iface="$1"
    local driver
    driver=$(detect_wifi_driver "$iface")

    if [ "$(driver_is_realtek_oot "$driver")" != "yes" ]; then
        print_warning "驱动 ${driver} 不支援 IPS/LPS 参数控制，跳过"
        return
    fi

    echo ""
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "   ⚡ 禁用 Realtek IPS/LPS 驱动省电"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "  驱动 : ${CYAN}${driver}${NC}"
    echo ""

    # 即时写入（通过 /sys）
    print_step "【即时】尝试写入 rtw_ips_mode=0 和 rtw_lps_disable=1..."
    local ips_ok=false lps_ok=false

    if [ -f "/sys/module/${driver}/parameters/rtw_ips_mode" ]; then
        run_cmd "echo 0 > /sys/module/${driver}/parameters/rtw_ips_mode" 2>/dev/null && ips_ok=true || true
    fi
    if [ -f "/sys/module/${driver}/parameters/rtw_lps_disable" ]; then
        run_cmd "echo 1 > /sys/module/${driver}/parameters/rtw_lps_disable" 2>/dev/null && lps_ok=true || true
    fi

    if $ips_ok || $lps_ok; then
        $ips_ok && print_success "rtw_ips_mode=0 即时写入成功"
        $lps_ok && print_success "rtw_lps_disable=1 即时写入成功"
    else
        print_warning "即时写入失败（驱动参数为只读），但永久设定仍会写入"
        print_info "重启后生效"
    fi

    echo ""

    # 永久写入 modprobe 档
    local drv_file="/etc/modprobe.d/${driver}.conf"
    print_step "【永久】写入驱动参数到 ${drv_file}"

    # 检查现有 options 行并添加/更新参数
    local existing_line
    existing_line=$(grep "^options ${driver}" "$drv_file" 2>/dev/null || echo "")

    if [ -z "$existing_line" ]; then
        # 完全没有这行，直接追加
        run_cmd "echo 'options ${driver} rtw_power_mgnt=0 rtw_ips_mode=0 rtw_lps_disable=1' >> '${drv_file}'"
    else
        # 逐个参数更新或追加
        for param_pair in "rtw_ips_mode=0" "rtw_lps_disable=1"; do
            local pname="${param_pair%%=*}"
            local pval="${param_pair##*=}"
            if echo "$existing_line" | grep -q "${pname}="; then
                run_cmd "sed -i 's/\(options ${driver}.*${pname}=\)[^ ]*/\1${pval}/' '${drv_file}'"
            else
                run_cmd "sed -i '/^options ${driver}/s/$/ ${pname}=${pval}/' '${drv_file}'"
            fi
        done
    fi

    print_step "更新 initramfs..."
    run_cmd "update-initramfs -u 2>/dev/null || true"
    print_success "IPS/LPS 参数已写入，重启后永久生效 ✓"
    echo ""
    echo -e "  已写入到 : ${CYAN}${drv_file}${NC}"
    echo -e "  参数内容 : ${WHITE}rtw_power_mgnt=0 rtw_ips_mode=0 rtw_lps_disable=1${NC}"
}

###############################################################################
# 读取目前电源模式
###############################################################################

# 返回字串: "on" = 省电开启, "off" = 省电关闭（全速）, "unknown"
get_power_save_raw() {
    local iface="$1"
    local raw=""

    # 优先用 iw（更准确）
    if command -v iw >/dev/null 2>&1; then
        raw=$(iw dev "$iface" get power_save 2>/dev/null | grep -oP '(?<=Power save: )\w+' || true)
    fi

    # 回退到 iwconfig
    if [ -z "$raw" ] && command -v iwconfig >/dev/null 2>&1; then
        raw=$(iwconfig "$iface" 2>/dev/null | grep -oP '(?<=Power Management:)\w+' || true)
    fi

    echo "${raw:-unknown}"
}

###############################################################################
# 根据驱动家族取得正确的省电参数名与值
###############################################################################

# 返回该驱动使用的省电「参数名」
driver_param_name() {
    local driver="$1"
    case "$driver" in
        # Realtek USB 专属驱动（完整省电控制，参数名 rtw_power_mgnt）
        # 涵盖所有可能的前缀变体：8xxx / r8xxx / rtl8xxx / rtw88xxx
        8821*|8852*|8832*|8192*|8188*|8172*|\
        r8192*|r8188*|r8172*|\
        rtl8192*|rtl8188*|rtl8172*|rtl88*|\
        rtw88*)
            echo "rtw_power_mgnt" ;;
        # Atheros / QCA
        ath9k|ath9k_htc)
            echo "ps_enable" ;;
        # 其余（Intel iwlwifi、博通 brcmfmac、MediaTek mt76 等）皆用 power_save
        *)
            echo "power_save" ;;
    esac
}

# 返回该驱动的省电参数名是否已在脚本已知列表内
# "yes" = 已知，可以安全写入层3
# "no"  = 未知，只能写层1，层2/3 需用户手动处理
driver_param_is_known() {
    local driver="$1"
    case "$driver" in
        # ── 已知 Realtek USB 专属驱动（所有前缀变体）────────────────
        8821*|8852*|8832*|8192*|8188*|8172*|\
        r8192*|r8188*|r8172*|\
        rtl8192*|rtl8188*|rtl8172*|rtl88*|\
        rtw88*)
            echo "yes" ;;
        # ── 已知 Atheros / QCA ────────────────────────────────────
        ath9k|ath9k_htc)
            echo "yes" ;;
        # ── 已知 Intel / 博通 / MediaTek（统一用 power_save）──────
        iwlwifi|iwlmvm|iwldvm|brcmfmac|brcmsmac|mt76*|mt7921*)
            echo "yes" ;;
        # ── 通用兼容驱动（参数名已知但效果有限）──────────────────
        rtl8xxxu|rtl8x2bs)
            echo "yes" ;;
        # ── 其他所有驱动：参数名不确定，不写层3 ──────────────────
        *)
            echo "no" ;;
    esac
}

# 返回该驱动是否为「通用兼容驱动」（省电控制效果有限）
driver_is_generic() {
    local driver="$1"
    case "$driver" in
        rtl8xxxu|rtl8x2bs|r8188ee)
            echo "yes" ;;
        *)
            echo "no"  ;;
    esac
}

# 返回社群专属驱动的安装建议
driver_community_hint() {
    local driver="$1"
    case "$driver" in
        rtl8xxxu)
            echo "RTL8192EU/RTL8188EU 系列 → 搜寻: rtl8192eu linux driver github" ;;
        8192eu|r8192eu)
            echo "已使用 RTL8192EU 专属驱动（${driver}），省电控制参数为 rtw_power_mgnt" ;;
        *)
            echo "" ;;
    esac
}

# 返回该驱动关闭省电的「参数值」（全速=0，省电=1，中等依驱动定）
driver_param_val() {
    local driver="$1"
    local mode="$2"   # "off" / "on" / "auto"
    local pname
    pname=$(driver_param_name "$driver")

    case "$pname" in
        rtw_power_mgnt)
            # rtw_power_mgnt: 0=全速  1=省电  2=自适应(中等)
            case "$mode" in
                off)  echo 0 ;;
                on)   echo 1 ;;
                auto) echo 2 ;;
                *)    echo 0 ;;
            esac ;;
        ps_enable)
            # ps_enable: 0=关闭省电  1=开启省电
            case "$mode" in
                off|auto) echo 0 ;;
                on)       echo 1 ;;
                *)        echo 0 ;;
            esac ;;
        power_save)
            # power_save: 0=全速  1=省电
            case "$mode" in
                off|auto) echo 0 ;;
                on)       echo 1 ;;
                *)        echo 0 ;;
            esac ;;
    esac
}

###############################################################################
# 读取三层设定状态
###############################################################################

# 读取 NetworkManager 层的 wifi.powersave 值并翻译
read_nm_layer() {
    local nm_file="/etc/NetworkManager/conf.d/wifi-power.conf"
    if [ ! -f "$nm_file" ]; then
        echo "未设定"
        return
    fi
    local val
    val=$(grep -oP '(?<=wifi.powersave\s=\s)\d' "$nm_file" 2>/dev/null ||           grep -oP '(?<=wifi.powersave=)\d'      "$nm_file" 2>/dev/null || echo "")
    case "$val" in
        0) echo "跟随系统 (default)" ;;
        1) echo "不干涉 (ignore)"    ;;
        2) echo "全速模式 (disable)" ;;
        3) echo "省电模式 (enable)"  ;;
        *) echo "未设定"             ;;
    esac
}

# 读取 modprobe 档（通用档或驱动专属档）的省电参数值并翻译
read_modprobe_layer() {
    local driver="$1"
    local pname
    pname=$(driver_param_name "$driver")

    # 搜寻所有可能的档案
    local files=( "/etc/modprobe.d/wifi-power.conf" "/etc/modprobe.d/${driver}.conf" )
    local found_val=""
    local found_file=""

    for f in "${files[@]}"; do
        [ -f "$f" ] || continue
        # 只取 options <driver> 那一行里的参数值
        local v
        v=$(grep -oP "(?<=options\s${driver}\s).*" "$f" 2>/dev/null |             grep -oP "(?<=${pname}=)\d" || true)
        if [ -n "$v" ]; then
            found_val="$v"
            found_file="$f"
            break
        fi
    done

    if [ -z "$found_val" ]; then
        echo "未设定"
        return
    fi

    # 翻译
    case "$pname" in
        rtw_power_mgnt)
            case "$found_val" in
                0) echo "全速模式 (${found_file##*/})" ;;
                1) echo "省电模式 (${found_file##*/})" ;;
                2) echo "中等模式 (${found_file##*/})" ;;
                *) echo "未知值=${found_val} (${found_file##*/})" ;;
            esac ;;
        ps_enable|power_save)
            case "$found_val" in
                0) echo "全速模式 (${found_file##*/})" ;;
                1) echo "省电模式 (${found_file##*/})" ;;
                *) echo "未知值=${found_val} (${found_file##*/})" ;;
            esac ;;
    esac
}

# 将 on/off 转换成 2 档等级
#   省电=on/auto → 1（省电）
#   省电=off     → 2（全速）
#   unknown      → 0（无法判断）
raw_to_level() {
    local raw="$1"
    case "$raw" in
        on|auto) echo 1 ;;
        off)     echo 2 ;;
        *)       echo 0 ;;
    esac
}

###############################################################################
# 显示状态
###############################################################################

# 自动检测网卡驱动名称
detect_wifi_driver() {
    local iface="$1"
    local driver=""

    # 方法1: 从 /sys 读取（最准确）
    if [ -L "/sys/class/net/${iface}/device/driver" ]; then
        driver=$(readlink -f "/sys/class/net/${iface}/device/driver" 2>/dev/null | xargs basename 2>/dev/null || true)
    fi

    # 方法2: ethtool
    if [ -z "$driver" ] && command -v ethtool >/dev/null 2>&1; then
        driver=$(ethtool -i "$iface" 2>/dev/null | awk '/^driver:/{print $2}' || true)
    fi

    # 方法3: lsmod 比对已知驱动
    if [ -z "$driver" ]; then
        local known="iwlwifi iwlmvm iwldvm ath9k ath10k_pci ath10k_core rtw88_core rtw88_pci r8188eu r8192ee brcmfmac brcmsmac mt76 mt7921e 8821cu 8852bu 8852ce rtl8xxxu rtl8x2bs 8192eu 8188eu 8192cu 8192du r8192eu"
        for d in $known; do
            if lsmod 2>/dev/null | grep -q "^${d} "; then
                driver="$d"; break
            fi
        done
    fi

    echo "${driver:-unknown}"
}

show_status() {
    local iface="$1"
    local raw
    raw=$(get_power_save_raw "$iface")
    local level
    level=$(raw_to_level "$raw")
    local driver
    driver=$(detect_wifi_driver "$iface")

    echo ""
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "   WiFi 电源状态报告"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "  网卡接口 : ${CYAN}${iface}${NC}"
    echo -e "  网卡驱动 : ${CYAN}${driver}${NC}"
    echo ""

    # ── 2 格颜色进度条（红=省电  绿=全速）──────────────────────────
    local seg1 seg2
    if   [ "$level" -eq 1 ]; then
        seg1="${RED}████████${NC}";   seg2="${WHITE}░░░░░░░░${NC}"
    elif [ "$level" -eq 2 ]; then
        seg1="${RED}████████${NC}";   seg2="${GREEN}████████${NC}"
    else
        seg1="${WHITE}░░░░░░░░${NC}"; seg2="${WHITE}░░░░░░░░${NC}"
    fi

    echo -e "  性能等级 : ${seg1} ${seg2}"
    echo -e "             ${RED}省电${NC}       ${GREEN}全速${NC}"
    echo ""

    case "$raw" in
        on)
            echo -e "  即时状态 : ${YELLOW}● 省电模式 (Power Save ON)${NC}"
            echo ""
            print_warning "WiFi 处于省电模式！"
            print_warning "此模式会让网卡定期休眠，容易造成："
            echo -e "  ${RED}•${NC} 断线、延迟突然升高"
            echo -e "  ${RED}•${NC} ping 不稳定、掉包"
            echo -e "  ${RED}•${NC} 下载速度忽快忽慢"
            ;;
        auto)
            echo -e "  即时状态 : ${RED}● 省电模式 (Power Save AUTO/ON)${NC}"
            echo ""
            print_warning "WiFi 处于省电模式（驱动自动管理）"
            print_warning "建议切换到全速模式以获得最稳定的连线"
            ;;
        off)
            echo -e "  即时状态 : ${GREEN}● 全速模式 (Power Save OFF)${NC}"
            echo ""
            print_success "WiFi 目前处于全速模式，连接稳定性最佳！"
            ;;
        *)
            echo -e "  即时状态 : ${MAGENTA}● 无法判断 (unknown)${NC}"
            echo ""
            print_warning "无法读取电源模式，可能是驱动不支援 power_save 查询"
            ;;
    esac

    # ── 三层永久设定状态 ──────────────────────────────────────────
    echo ""
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "   📋 永久设定状态（三层检查）"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # 层1: NetworkManager
    local nm_status
    nm_status=$(read_nm_layer)
    local nm_color=$WHITE
    [[ "$nm_status" == *"全速"* ]] && nm_color=$GREEN
    [[ "$nm_status" == *"省电"* ]] && nm_color=$YELLOW
    [[ "$nm_status" == "未设定"  ]] && nm_color=$MAGENTA
    echo -e "  层1 NetworkManager : ${nm_color}${nm_status}${NC}"
    echo -e "       └ /etc/NetworkManager/conf.d/wifi-power.conf"

    echo ""

    # 层2: modprobe 通用档
    local mp_status drv_status
    if [ "$driver" != "unknown" ]; then
        local pname
        pname=$(driver_param_name "$driver")
        local pval_off
        pval_off=$(driver_param_val "$driver" "off")

        # 层2: wifi-power.conf
        local mp2_val=""
        [ -f "/etc/modprobe.d/wifi-power.conf" ] &&             mp2_val=$(grep -oP "(?<=options ${driver} ).*" /etc/modprobe.d/wifi-power.conf 2>/dev/null |                       grep -oP "(?<=${pname}=)[0-9]" || true)
        local mp2_status="未设定"
        if [ -n "$mp2_val" ]; then
            [ "$mp2_val" = "$pval_off" ] && mp2_status="全速模式" || mp2_status="省电/中等模式 (val=${mp2_val})"
        fi
        local mp2_color=$WHITE
        [[ "$mp2_status" == *"全速"* ]] && mp2_color=$GREEN
        [[ "$mp2_status" == *"省电"* ]] && mp2_color=$YELLOW
        [[ "$mp2_status" == "未设定" ]] && mp2_color=$MAGENTA
        echo -e "  层2 modprobe 通用档 : ${mp2_color}${mp2_status}${NC}"
        echo -e "       └ /etc/modprobe.d/wifi-power.conf  (参数: ${pname})"

        echo ""

        # 层3: 驱动专属档
        local mp3_val=""
        [ -f "/etc/modprobe.d/${driver}.conf" ] &&             mp3_val=$(grep -oP "(?<=options ${driver} ).*" /etc/modprobe.d/${driver}.conf 2>/dev/null |                       grep -oP "(?<=${pname}=)[0-9]" || true)
        local mp3_status="未设定"
        if [ -n "$mp3_val" ]; then
            [ "$mp3_val" = "$pval_off" ] && mp3_status="全速模式" || mp3_status="省电/中等模式 (val=${mp3_val})"
        fi
        local mp3_color=$WHITE
        [[ "$mp3_status" == *"全速"* ]] && mp3_color=$GREEN
        [[ "$mp3_status" == *"省电"* ]] && mp3_color=$YELLOW
        [[ "$mp3_status" == "未设定" ]] && mp3_color=$MAGENTA
        echo -e "  层3 驱动专属档     : ${mp3_color}${mp3_status}${NC}"
        echo -e "       └ /etc/modprobe.d/${driver}.conf  (参数: ${pname})"

        # 一致性提示
        echo ""
        if [[ "$nm_status" == *"全速"* ]] && [[ "$mp2_status" == *"全速"* ]] && [[ "$mp3_status" == *"全速"* ]]; then
            print_success "三层设定一致：全速模式，重启后永久生效 ✓"
        elif [[ "$nm_status" == "未设定" ]] && [[ "$mp2_status" == "未设定" ]] && [[ "$mp3_status" == "未设定" ]]; then
            print_warning "三层均未写入永久设定，重启后将恢复系统预设"
        else
            print_warning "注意：三层设定不一致，可能互相覆盖，建议重新写入"
        fi
    else
        print_warning "无法检测驱动，跳过层2与层3检查"
    fi

    # ── 通用驱动警告 ──────────────────────────────────────────────
    if [ "$driver" != "unknown" ] && [ "$(driver_is_generic "$driver")" = "yes" ]; then
        local hint
        hint=$(driver_community_hint "$driver")
        echo ""
        print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        print_header "   ⚠️  通用驱动警告"
        print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo -e "  检测到你使用的是 ${YELLOW}${driver}${NC}（Linux 内核通用兼容驱动）"
        echo ""
        print_warning "通用驱动的问题："
        echo -e "  ${RED}•${NC} 省电控制写入后效果有限，网卡仍可能自行进入省电"
        echo -e "  ${RED}•${NC} 延迟不稳定、ping 抖动大是此驱动的已知问题"
        echo -e "  ${RED}•${NC} 这不是脚本的问题，而是驱动本身的限制"
        echo ""
        print_info "根本解决方法：安装社群开发的专属驱动"
        if [ -n "$hint" ]; then
            echo -e "  ${CYAN}${hint}${NC}"
        fi
        echo -e "  ${CYAN}安装专属驱动后，省电控制会更彻底，连线也会更稳定${NC}"
    fi

    # ── USB Autosuspend 状态（仅 USB 网卡）──────────────────────────
    show_usb_status "$iface"

    # ── Realtek IPS/LPS 状态（仅 Realtek OOT 驱动）──────────────────
    show_rtk_extra_status "$driver"

    echo ""
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    print_header "  📌 模式说明"
    echo -e "  ${GREEN}●${NC} 全速模式  - 网卡全时运作，连线最稳定（推荐）"
    echo -e "  ${RED}●${NC} 省电模式  - 网卡定期休眠，连线容易不稳定"
    echo ""
}

###############################################################################
# 设定电源模式（需要 sudo）
###############################################################################

set_power_save() {
    local iface="$1"
    local mode="$2"   # "on" 或 "off"

    if [ "$EUID" -ne 0 ]; then
        print_step "需要管理员权限，尝试使用 sudo..."
        sudo iw dev "$iface" set power_save "$mode"
    else
        iw dev "$iface" set power_save "$mode"
    fi
}

###############################################################################
# 写入开机永久设定（三层：NetworkManager + modprobe通用 + 驱动专属）
###############################################################################

# 判断是否需要 sudo 执行命令
run_cmd() {
    if [ "$EUID" -ne 0 ]; then
        sudo bash -c "$1"
    else
        bash -c "$1"
    fi
}

make_persistent() {
    local iface="$1"
    local mode="$2"   # "on" / "off" / "auto"
    local driver
    driver=$(detect_wifi_driver "$iface")

    # ── 层1: NetworkManager (/etc/NetworkManager/conf.d/wifi-power.conf) ──
    # wifi.powersave: 0=default 1=ignore 2=disable(全速) 3=enable(省电)
    local nm_val
    case "$mode" in
        off)  nm_val=2 ;;
        on)   nm_val=3 ;;
        auto) nm_val=0 ;;
        *)    nm_val=2 ;;
    esac
    local nm_dir="/etc/NetworkManager/conf.d"
    local nm_file="${nm_dir}/wifi-power.conf"

    print_step "【层1】写入 NetworkManager → ${nm_file}"
    run_cmd "mkdir -p '${nm_dir}' && printf '[connection]\nwifi.powersave = ${nm_val}\n' > '${nm_file}'"
    run_cmd "systemctl restart NetworkManager 2>/dev/null || true"
    print_success "NetworkManager 层写入完成"

    # ── 写入 modprobe 档的通用函数（追加或更新，不整个覆盖）────────
    write_modprobe_file() {
        local filepath="$1" drv="$2" param="$3" val="$4"
        if [ ! -f "$filepath" ]; then
            run_cmd "printf '# WiFi 省电设定 - wifi-power.sh\noptions ${drv} ${param}=${val}\n' > '${filepath}'"
            return
        fi
        local existing_line
        existing_line=$(grep "^options ${drv}" "$filepath" 2>/dev/null || true)
        if [ -z "$existing_line" ]; then
            run_cmd "echo 'options ${drv} ${param}=${val}' >> '${filepath}'"
        elif echo "$existing_line" | grep -q "${param}="; then
            run_cmd "sed -i 's/\(options ${drv}.*${param}=\)[0-9]*/\1${val}/' '${filepath}'"
        else
            run_cmd "sed -i '/^options ${drv}/s/$/ ${param}=${val}/' '${filepath}'"
        fi
    }

    # ── 检查驱动是否在已知参数列表内 ────────────────────────────────
    local param_known="no"
    local pname="" pval=""
    if [ "$driver" != "unknown" ]; then
        param_known=$(driver_param_is_known "$driver")
        pname=$(driver_param_name "$driver")
        pval=$(driver_param_val "$driver" "$mode")
    fi

    # ── 层2: modprobe 通用档 ─────────────────────────────────────────
    local mp_file="/etc/modprobe.d/wifi-power.conf"
    if [ "$driver" != "unknown" ] && [ "$param_known" = "yes" ]; then
        print_step "【层2】写入 modprobe 通用档 → ${mp_file}"
        print_step "       驱动: ${driver}  参数: ${pname}=${pval}"
        write_modprobe_file "$mp_file" "$driver" "$pname" "$pval"
        print_success "层2 写入完成"
    elif [ "$driver" != "unknown" ]; then
        print_warning "【层2】驱动 ${driver} 不在已知列表，跳过"
    else
        print_warning "【层2】无法检测驱动，跳过"
    fi

    # ── 层3: 驱动专属档 ──────────────────────────────────────────────
    local drv_file=""
    [ "$driver" != "unknown" ] && drv_file="/etc/modprobe.d/${driver}.conf"

    if [ "$driver" != "unknown" ] && [ "$param_known" = "yes" ]; then
        print_step "【层3】写入驱动专属档 → ${drv_file}"
        print_step "       驱动: ${driver}  参数: ${pname}=${pval}"
        write_modprobe_file "$drv_file" "$driver" "$pname" "$pval"
        print_step "更新 initramfs（可能需要数秒）..."
        run_cmd "update-initramfs -u 2>/dev/null || true"
        print_success "层3 写入完成"
    elif [ "$driver" != "unknown" ] && [ "$param_known" = "no" ]; then
        echo ""
        print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        print_header "   ⚠️  层3 需要手动处理"
        print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo -e "  驱动 ${YELLOW}${driver}${NC} 不在脚本的已知列表内"
        echo -e "  无法确定此驱动的省电参数名，已跳过层3写入"
        echo -e "  （避免写入错误参数导致驱动加载失败）"
        echo ""
        print_info "请手动处理层3（驱动专属档）："
        echo ""
        echo -e "  ${WHITE}步骤1${NC} 查询此驱动支援哪些参数："
        echo -e "         ${CYAN}modinfo ${driver} | grep parm${NC}"
        echo ""
        echo -e "  ${WHITE}步骤2${NC} 找到省电相关参数后写入驱动专属档："
        echo -e "         ${CYAN}sudo nano /etc/modprobe.d/${driver}.conf${NC}"
        echo ""
        echo -e "  ${WHITE}步骤3${NC} 档案内写入（将 <参数名> 替换为实际参数）："
        echo -e "         ${CYAN}options ${driver} <参数名>=0${NC}"
        echo ""
        echo -e "  ${WHITE}步骤4${NC} 更新 initramfs："
        echo -e "         ${CYAN}sudo update-initramfs -u${NC}"
    else
        print_warning "【层3】无法检测驱动，跳过"
    fi

    # ── 写入结果汇总 ──────────────────────────────────────────────────
    echo ""
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "   📋 写入结果汇总"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "  ${GREEN}✓${NC} 层1 ${CYAN}${nm_file}${NC}"
    echo -e "         └ NetworkManager 已写入"
    if [ "$param_known" = "yes" ]; then
        echo -e "  ${GREEN}✓${NC} 层2 ${CYAN}/etc/modprobe.d/wifi-power.conf${NC}"
        echo -e "         └ modprobe 通用档 已写入"
        echo -e "  ${GREEN}✓${NC} 层3 ${CYAN}/etc/modprobe.d/${driver}.conf${NC}"
        echo -e "         └ 驱动专属档 已写入"
        echo ""
        print_success "三层全部写入完成，重启后永久生效 ✓"
    else
        echo -e "  ${YELLOW}⚠${NC} 层2 已跳过（驱动 ${driver} 不在已知列表）"
        echo -e "  ${YELLOW}⚠${NC} 层3 已跳过（请参考上方步骤手动处理）"
        echo ""
        print_warning "层1 已写入，可防止 NetworkManager 强制省电"
        print_warning "层2/3 请按上方步骤手动处理以完全关闭省电"
    fi

    # NetworkManager wifi.powersave 值说明：
    #   0 = default (跟随系统)
    #   1 = ignore  (不干涉)
    #   2 = disable (关闭省电 = 全速)
    #   3 = enable  (开启省电)
}

###############################################################################
# WiFi 稳定性测试
###############################################################################

# 自动检测路由器 IP（默认网关）
detect_gateway() {
    local iface="${1:-}"   # 接受可选的接口参数，优先找该接口的默认路由
    local gw=""

    if command -v ip >/dev/null 2>&1; then
        # 优先：找经过指定接口的默认路由（避免双网卡时取到有线/VPN 的网关）
        if [ -n "$iface" ]; then
            gw=$(ip route show default dev "$iface" 2>/dev/null | awk '/default via/{print $3}' | head -1)
        fi
        # 退化：取任意默认路由
        if [ -z "$gw" ]; then
            gw=$(ip route show default 2>/dev/null | awk '/default via/{print $3}' | head -1)
        fi
    fi

    if [ -z "$gw" ] && command -v route >/dev/null 2>&1; then
        gw=$(route -n 2>/dev/null | awk '/^0\.0\.0\.0/{print $2}' | head -1)
    fi

    if [ -z "$gw" ] && command -v netstat >/dev/null 2>&1; then
        gw=$(netstat -rn 2>/dev/null | awk '/^0\.0\.0\.0/{print $2}' | head -1)
    fi

    echo "${gw:-}"
}

# 将平均延迟和掉包率转换成稳定性评语
latency_verdict() {
    local avg="$1"
    local loss="$2"
    local max="${3:-0}"   # 第三参数：最高延迟（ms），预设 0

    # bc_gt A B：若 A > B 返回字串 "1"，否则 "0"
    bc_gt() { echo "${1} > ${2}" | bc -l 2>/dev/null || echo 0; }

    if   [ "$loss" -ge 20 ]; then echo "非常不稳定"
    elif [ "$loss" -ge 5  ]; then echo "不稳定"
    elif [ "$(bc_gt "$avg" 100)" = "1" ]; then echo "延迟偏高"
    elif [ "$(bc_gt "$avg" 30)"  = "1" ]; then echo "尚可"
    elif [ "$(bc_gt "$max" 200)" = "1" ]; then echo "有严重抖动"
    elif [ "$(bc_gt "$max" 50)"  = "1" ]; then echo "有轻微抖动"
    else echo "稳定"
    fi
}

colorize_verdict() {
    local v="$1"
    case "$v" in
        "稳定")                    echo -e "${GREEN}${v}${NC}"  ;;
        "有轻微抖动")              echo -e "${YELLOW}${v}${NC}" ;;
        "尚可")                    echo -e "${CYAN}${v}${NC}"   ;;
        "延迟偏高"|"有严重抖动")   echo -e "${YELLOW}${v}${NC}" ;;
        "不稳定"|"非常不稳定")     echo -e "${RED}${v}${NC}"    ;;
        *)                         echo -e "${WHITE}${v}${NC}"  ;;
    esac
}

run_stability_test() {
    local iface="$1"
    local target="$2"
    local duration="$3"
    local count=$(( duration * 2 ))   # 0.5 秒一次，总次数 = 时长 × 2
    local driver
    driver=$(detect_wifi_driver "$iface")

    local tmpfile
    tmpfile=$(mktemp /tmp/wifi_ping_XXXXXX)

    local interrupted=false
    trap 'interrupted=true' INT

    echo ""
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "   WiFi 稳定性测试进行中"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "  网卡接口   : ${CYAN}${iface}${NC}"
    echo -e "  网卡驱动   : ${CYAN}${driver}${NC}"
    echo -e "  目标路由器 : ${CYAN}${target}${NC}"
    echo -e "  测试时长   : ${WHITE}${duration} 秒${NC}（每 0.5 秒 ping 一次，共 ${count} 次）"
    echo ""
    echo -e "  ${YELLOW}提示：若 WiFi 不稳定需要求助，上方的网卡接口与驱动名称可直接复制提供给 AI${NC}"
    echo -e "  ${YELLOW}      按 Ctrl+C 可提早停止并查看结果${NC}"
    echo ""

    for i in 3 2 1; do
        echo -ne "\r  ${CYAN}测试将在 ${i} 秒后开始...${NC}  "
        sleep 1
    done
    echo -e "\r  ${GREEN}开始测试！                    ${NC}"
    echo ""

    local sent=0 recv=0 lost=0
    local sum_ms=0 min_ms=99999 max_ms=0

    for (( i=1; i<=count; i++ )); do
        if [ "$interrupted" = "true" ]; then break; fi

        local result
        result=$(ping -c 1 -W 1 -i 0.1 "$target" 2>/dev/null | grep -oP '(?<=time=|时间=)[0-9.]+' || echo "")

        sent=$(( sent + 1 ))

        if [ -n "$result" ]; then
            recv=$(( recv + 1 ))
            sum_ms=$(awk "BEGIN{printf \"%.3f\", $sum_ms + $result}")
            min_ms=$(awk "BEGIN{if ($result < $min_ms) print $result; else print $min_ms}")
            max_ms=$(awk "BEGIN{if ($result > $max_ms) print $result; else print $max_ms}")
            echo "$result" >> "$tmpfile"
        else
            echo "LOSS" >> "$tmpfile"
        fi

        lost=$(( sent - recv ))
        local loss_pct=0
        [ $sent -gt 0 ] && loss_pct=$(( lost * 100 / sent ))

        local avg_ms="0.0"
        [ $recv -gt 0 ] && avg_ms=$(awk "BEGIN{printf \"%.1f\", $sum_ms / $recv}")

        local filled=$(( i * 20 / count ))
        local bar=""
        for (( b=1; b<=20; b++ )); do
            [ $b -le $filled ] && bar+="█" || bar+="░"
        done

        local ms_color=$GREEN
        [ "$(echo "$avg_ms > 100" | bc -l 2>/dev/null || echo 0)" = "1" ] && ms_color=$RED
        { [ "$(echo "$avg_ms > 30" | bc -l 2>/dev/null || echo 0)" = "1" ] && [ "$ms_color" = "$GREEN" ]; } && ms_color=$YELLOW || true

        local loss_color=$GREEN
        [ $loss_pct -ge 5  ] && loss_color=$YELLOW
        [ $loss_pct -ge 20 ] && loss_color=$RED

        printf "\r  [${CYAN}%s${NC}] %3d/%d  延迟: ${ms_color}%6s ms${NC}  掉包: ${loss_color}%3d%%${NC}  " \
               "$bar" "$i" "$count" "$avg_ms" "$loss_pct"

        sleep 0.5
    done

    trap - INT
    echo ""
    echo ""

    # ── 最终统计 ──────────────────────────────────────────────────
    local final_loss_pct=0
    [ $sent -gt 0 ] && final_loss_pct=$(( lost * 100 / sent ))

    local final_avg="0.0"
    [ $recv -gt 0 ] && final_avg=$(awk "BEGIN{printf \"%.1f\", $sum_ms / $recv}")

    local jitter="0.0"
    if [ $recv -ge 2 ]; then
        jitter=$(awk '
            /^[0-9]/{vals[NR]=$1}
            END{
                n=0; sum=0; prev=""
                for(i=1;i<=NR;i++){
                    if(vals[i]!="" && prev!=""){
                        diff=vals[i]-prev
                        if(diff<0) diff=-diff
                        sum+=diff; n++
                    }
                    if(vals[i]!="") prev=vals[i]
                }
                if(n>0) printf "%.1f", sum/n
                else print "0.0"
            }
        ' "$tmpfile")
    fi

    local min_disp="--"  max_disp="--"
    [ $recv -gt 0 ] && min_disp="${min_ms} ms"
    [ $recv -gt 0 ] && max_disp="${max_ms} ms"

    local verdict;  verdict=$(latency_verdict "$final_avg" "$final_loss_pct" "$max_ms")
    local colored;  colored=$(colorize_verdict "$verdict")

    # ── 显示报告 ──────────────────────────────────────────────────
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "   📊 稳定性测试报告"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    [ "$interrupted" = "true" ] && { print_warning "测试已提早停止（已发送 ${sent}/${count} 次）"; echo ""; }

    echo -e "  网卡接口    : ${CYAN}${iface}${NC}"
    echo -e "  网卡驱动    : ${CYAN}${driver}${NC}"
    echo -e "  目标路由器  : ${CYAN}${target}${NC}"
    echo -e "  发送次数    : ${WHITE}${sent}${NC}"
    echo -e "  成功回应    : ${GREEN}${recv}${NC}"
    echo -e "  掉包次数    : $([ $lost -gt 0 ] && echo -e "${RED}${lost}${NC}" || echo -e "${GREEN}${lost}${NC}")"
    echo -e "  掉包率      : $([ $final_loss_pct -ge 5 ] && echo -e "${RED}${final_loss_pct}%${NC}" || echo -e "${GREEN}${final_loss_pct}%${NC}")"
    echo ""
    echo -e "  平均延迟    : ${WHITE}${final_avg} ms${NC}"
    echo -e "  最低延迟    : ${GREEN}${min_disp}${NC}"

    # 最高延迟颜色：>200ms 红, >50ms 黄, 其他绿
    local max_color=$GREEN
    [ "$(echo "$max_ms > 200" | bc -l 2>/dev/null || echo 0)" = "1" ] && max_color=$RED   || true
    { [ "$(echo "$max_ms > 50"  | bc -l 2>/dev/null || echo 0)" = "1" ] && [ "$max_color" = "$GREEN" ]; } && max_color=$YELLOW || true
    echo -e "  最高延迟    : ${max_color}${max_disp}${NC}"

    echo -e "  抖动 Jitter : ${WHITE}${jitter} ms${NC}"
    echo ""
    echo -e "  综合评价    : ${colored}"
    echo ""

    case "$verdict" in
        "稳定")
            print_success "WiFi 连线非常稳定，延迟低、无掉包！" ;;
        "有轻微抖动")
            print_warning "WiFi 偶有延迟峰值（最高 ${max_ms} ms），平均延迟正常。"
            print_warning "可能原因：USB autosuspend 或驱动内部省电仍未完全关闭。"
            print_info    "建议执行选单 [5] 禁用 USB 自动休眠，或 [6] 禁用 Realtek IPS/LPS。" ;;
        "有严重抖动")
            print_error   "WiFi 存在严重延迟峰值（最高 ${max_ms} ms），虽无掉包但连线不稳定！"
            print_error   "强烈建议执行选单 [5] 禁用 USB 自动休眠，并执行 [6] 禁用 Realtek IPS/LPS。"
            echo ""
            print_header  "  🆘 如需向他人或 AI 求助，请提供以下资讯："
            echo -e "  网卡接口 : ${CYAN}${iface}${NC}"
            echo -e "  网卡驱动 : ${CYAN}${driver}${NC}" ;;
        "尚可")
            print_info    "WiFi 连线尚可，延迟稍高但无掉包。"
            print_info    "若感觉不流畅，可尝试关闭省电模式。" ;;
        "延迟偏高")
            print_warning "延迟偏高，可能影响游戏或视讯通话。"
            print_warning "建议检查是否处于省电模式，或靠近路由器。" ;;
        "不稳定")
            print_error "WiFi 连线不稳定，有明显掉包！"
            print_error "强烈建议切换到全速模式，或检查路由器状态。"
            echo ""
            print_header "  🆘 如需向他人或 AI 求助，请提供以下资讯："
            echo -e "  网卡接口 : ${CYAN}${iface}${NC}"
            echo -e "  网卡驱动 : ${CYAN}${driver}${NC}" ;;
        "非常不稳定")
            print_error "WiFi 连线极度不稳定，掉包严重！"
            print_error "请立即切换全速模式，并检查网络环境。"
            echo ""
            print_header "  🆘 如需向他人或 AI 求助，请提供以下资讯："
            echo -e "  网卡接口 : ${CYAN}${iface}${NC}"
            echo -e "  网卡驱动 : ${CYAN}${driver}${NC}" ;;
    esac

    echo ""
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    rm -f "$tmpfile"
}

stability_test_menu() {
    local iface="$1"

    print_step "正在检测路由器 IP..."
    local gateway
    gateway=$(detect_gateway "$iface")

    if [ -z "$gateway" ]; then
        print_warning "无法自动检测路由器 IP"
        read -p "  请手动输入要 ping 的 IP（例如 192.168.1.1）: " gateway
        [ -z "$gateway" ] && { print_error "未输入 IP，取消测试"; return; }
    else
        print_success "检测到路由器 IP: ${gateway}"
        echo ""
        read -p "  使用此 IP？或输入其他 IP（直接回车确认）: " custom_ip
        [ -n "$custom_ip" ] && gateway="$custom_ip"
    fi

    echo ""
    print_header "  选择测试时长："
    echo -e "  ${GREEN}[1]${NC} 快速测试  ( 15 秒)"
    echo -e "  ${CYAN}[2]${NC} 标准测试  ( 30 秒) ← 推荐"
    echo -e "  ${YELLOW}[3]${NC} 深度测试  ( 60 秒)"
    echo -e "  ${WHITE}[4]${NC} 自定时长"
    echo ""
    read -p "  请选择 [1-4]（预设 2）: " dur_choice

    local duration=30
    case "${dur_choice:-2}" in
        1) duration=15 ;;
        2) duration=30 ;;
        3) duration=60 ;;
        4)
            read -p "  请输入测试秒数（10~300）: " custom_dur
            if [[ "$custom_dur" =~ ^[0-9]+$ ]] && [ "$custom_dur" -ge 10 ] && [ "$custom_dur" -le 300 ]; then
                duration=$custom_dur
            else
                print_warning "输入无效，使用预设 30 秒"
                duration=30
            fi
            ;;
        *) duration=30 ;;
    esac

    run_stability_test "$iface" "$gateway" "$duration"
}

###############################################################################
# 互动选单
###############################################################################

# 切换模式的通用流程
switch_mode() {
    local iface="$1"
    local mode="$2"    # "off" / "auto" / "on"
    local label="$3"   # 显示名称

    echo ""
    print_step "正在切换到${label}..."
    if set_power_save "$iface" "$mode"; then
        print_success "已切换到${label}！（本次开机有效）"
    else
        print_error "切换失败，请检查驱动是否支援 power_save 设定"
        return 1
    fi

    echo ""
    read -p "  是否同时写入永久生效设定（三层写入）? [y/N]: " persist
    if [[ "$persist" =~ ^[Yy]$ ]]; then
        echo ""
        make_persistent "$iface" "$mode"
    else
        print_warning "仅本次开机有效，重启后会恢复系统预设"
    fi

    echo ""
    show_status "$iface"
}

show_menu() {
    local iface="$1"
    local driver
    driver=$(detect_wifi_driver "$iface")
    local is_usb rtk_oot
    is_usb=$(is_usb_wifi "$iface")
    rtk_oot=$(driver_is_realtek_oot "$driver")

    echo ""
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "   请选择操作"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "  ${GREEN}[1]${NC} 切换到 ${GREEN}全速模式${NC}（关闭省电，推荐）"
    echo -e "  ${RED}[2]${NC} 切换到 ${RED}省电模式${NC}（延长电池寿命）"
    echo -e "  ${BLUE}[3]${NC} 重新查看当前状态"
    echo -e "  ${MAGENTA}[4]${NC} ${MAGENTA}WiFi 稳定性测试${NC}（ping 路由器，检测连线品质）"

    # 仅 USB 网卡显示选项5
    if [ "$is_usb" = "yes" ]; then
        echo -e "  ${CYAN}[5]${NC} ${CYAN}禁用 USB 自动休眠${NC}（解决 USB WiFi 突发高延迟）"
    fi

    # 仅 Realtek OOT 驱动显示选项6
    if [ "$rtk_oot" = "yes" ]; then
        echo -e "  ${YELLOW}[6]${NC} ${YELLOW}禁用 Realtek IPS/LPS${NC}（关闭驱动内部省电，彻底消除抖动）"
    fi

    echo -e "  ${RED}[0]${NC} 退出"
    echo ""
    read -p "  请输入选项: " choice

    case "$choice" in
        1) switch_mode "$iface" "off" "全速模式" ;;
        2) switch_mode "$iface" "on"  "省电模式" ;;
        3) show_status "$iface" ;;
        4)
            echo ""
            stability_test_menu "$iface"
            ;;
        5)
            if [ "$is_usb" = "yes" ]; then
                disable_usb_autosuspend "$iface"
            else
                print_warning "此网卡不是 USB 设备，无此选项"
            fi
            ;;
        6)
            if [ "$rtk_oot" = "yes" ]; then
                disable_rtk_ips_lps "$iface"
            else
                print_warning "此驱动不支援 IPS/LPS 控制，无此选项"
            fi
            ;;
        0)
            print_info "已退出"
            exit 0
            ;;
        *)
            print_warning "无效选项，请重新选择"
            ;;
    esac
}

###############################################################################
# 主程序
###############################################################################

main() {
    echo ""
    print_header "======================================"
    print_header "   WiFi 电源管理工具"
    print_header "======================================"
    echo ""

    check_dependencies
    detect_wifi_interface

    show_status "$WIFI_IF"

    while true; do
        show_menu "$WIFI_IF"
        echo ""
        read -p "  是否继续操作? [y/N]: " again
        if [[ ! "$again" =~ ^[Yy]$ ]]; then
            break
        fi
    done

    print_success "所有操作完成！"
    wait_for_exit 5
}

main "$@"
