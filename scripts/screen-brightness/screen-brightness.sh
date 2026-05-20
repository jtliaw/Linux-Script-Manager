#!/bin/bash
# Screen Brightness Control
# DESCRIPTION: 屏幕亮度与色温控制核心脚本 - 支援所有 Linux 桌面环境
# REQUIRES_SUDO: false
# 用法:
#   screen-brightness.sh detect              → 检测硬件环境
#   screen-brightness.sh brightness <设备> <0-100>   → 设定亮度百分比
#   screen-brightness.sh temperature <设备> <2000-6500> → 设定色温(K)
#   screen-brightness.sh list               → 列出所有可用显示器
#   screen-brightness.sh save <设备> <亮度> <色温>   → 储存设定
#   screen-brightness.sh load               → 套用已储存的设定
#   screen-brightness.sh autostart install  → 安装开机自动启动
#   screen-brightness.sh autostart remove   → 移除开机自动启动

set +e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
print_step()    { echo -e "${CYAN}➜${NC} $1"; }
print_header()  { echo -e "${WHITE}$1${NC}"; }

# ── 设定档路径 ────────────────────────────────────────────────────────────────
CONFIG_DIR="$HOME/.config/screen-brightness"
CONFIG_FILE="$CONFIG_DIR/settings.conf"
DETECTED_FILE="$CONFIG_DIR/detected.conf"

mkdir -p "$CONFIG_DIR"

###############################################################################
# 工具检测
###############################################################################

has_cmd() { command -v "$1" >/dev/null 2>&1; }

detect_tools() {
    TOOL_BRIGHTNESSCTL=false
    TOOL_LIGHT=false
    TOOL_XRANDR=false
    TOOL_DDCUTIL=false
    TOOL_XGAMMA=false
    TOOL_REDSHIFT=false
    TOOL_GAMMASTEP=false
    TOOL_BUSCTL=false
    TOOL_GSETTINGS=false
    TOOL_WLSUNSET=false

    has_cmd brightnessctl  && TOOL_BRIGHTNESSCTL=true
    has_cmd light          && TOOL_LIGHT=true
    has_cmd xrandr         && TOOL_XRANDR=true
    has_cmd ddcutil        && TOOL_DDCUTIL=true
    has_cmd xgamma         && TOOL_XGAMMA=true
    has_cmd redshift       && TOOL_REDSHIFT=true
    has_cmd gammastep      && TOOL_GAMMASTEP=true
    has_cmd busctl         && TOOL_BUSCTL=true
    has_cmd gsettings      && TOOL_GSETTINGS=true
    has_cmd wlsunset       && TOOL_WLSUNSET=true
}

###############################################################################
# 显示协议检测
###############################################################################

detect_display_protocol() {
    # XDG_SESSION_TYPE 是最可靠的判断方式（GNOME/KDE Wayland 一定会设定）
    if [ "${XDG_SESSION_TYPE:-}" = "wayland" ]; then
        DISPLAY_PROTOCOL="wayland"
    elif [ "${XDG_SESSION_TYPE:-}" = "x11" ]; then
        DISPLAY_PROTOCOL="x11"
    elif [ -n "${WAYLAND_DISPLAY:-}" ]; then
        DISPLAY_PROTOCOL="wayland"
    elif [ -n "${DISPLAY:-}" ]; then
        DISPLAY_PROTOCOL="x11"
    else
        # 尝试从 X11 socket 判断
        if [ -S /tmp/.X11-unix/X0 ] || [ -S /tmp/.X11-unix/X1 ]; then
            export DISPLAY="${DISPLAY:-:0}"
            DISPLAY_PROTOCOL="x11"
        else
            DISPLAY_PROTOCOL="unknown"
        fi
    fi
}

###############################################################################
# 桌面环境检测
###############################################################################

detect_desktop() {
    DE="${XDG_CURRENT_DESKTOP:-}"
    [ -z "$DE" ] && DE="${DESKTOP_SESSION:-}"
    DE=$(echo "$DE" | tr '[:upper:]' '[:lower:]')

    case "$DE" in
        *gnome*)  DESKTOP="gnome"  ;;
        *kde*)    DESKTOP="kde"    ;;
        *xfce*)   DESKTOP="xfce"   ;;
        *lxqt*)   DESKTOP="lxqt"   ;;
        *lxde*)   DESKTOP="lxde"   ;;
        *mate*)   DESKTOP="mate"   ;;
        *cinnamon*) DESKTOP="cinnamon" ;;
        *)        DESKTOP="unknown" ;;
    esac
}

###############################################################################
# 内置屏幕检测（/sys/class/backlight）
###############################################################################

detect_builtin_screens() {
    BUILTIN_SCREENS=()
    local backlight_dir="/sys/class/backlight"

    [ -d "$backlight_dir" ] || return

    for path in "$backlight_dir"/*/; do
        [ -d "$path" ] || continue
        local name
        name=$(basename "$path")
        local max_brightness=0
        [ -f "$path/max_brightness" ] && \
            max_brightness=$(cat "$path/max_brightness" 2>/dev/null || echo 0)
        [ "$max_brightness" -gt 0 ] && \
            BUILTIN_SCREENS+=("$name|$path|$max_brightness")
    done
}

###############################################################################
# 外接显示器检测（X11 xrandr）
###############################################################################

detect_xrandr_outputs() {
    XRANDR_OUTPUTS=()
    $TOOL_XRANDR || return

    # Wayland 下不用 xrandr 输出（色温由 gsettings 处理，亮度由 backlight 处理）
    # 加入 xrandr 输出只会造成重复控制器
    [ "$DISPLAY_PROTOCOL" = "x11" ] || return

    while IFS= read -r line; do
        if echo "$line" | grep -qE "^[A-Za-z0-9-]+ connected"; then
            local name
            name=$(echo "$line" | awk '{print $1}')
            # 跳过内置屏幕对应的 xrandr 输出（如 LVDS-1、eDP-1）
            # 内置屏幕已经由 backlight 控制，不需要 xrandr 重复列出
            echo "$name" | grep -qiE "^(LVDS|eDP|DSI)" && continue || true
            XRANDR_OUTPUTS+=("$name")
        fi
    done < <(xrandr 2>/dev/null || true)
}

###############################################################################
# 外接显示器检测（DDC/CI ddcutil）
###############################################################################

detect_ddc_monitors() {
    DDC_MONITORS=()
    $TOOL_DDCUTIL || return

    local detect_out
    detect_out=$(ddcutil detect --brief 2>/dev/null || true)

    while IFS= read -r line; do
        if echo "$line" | grep -qE "^Display [0-9]+"; then
            local num
            num=$(echo "$line" | grep -oP '(?<=Display )[0-9]+')
            DDC_MONITORS+=("$num")
        fi
    done <<< "$detect_out"
}

###############################################################################
# 综合检测并写入 detected.conf
###############################################################################

run_detect() {
    detect_tools
    detect_display_protocol
    detect_desktop
    detect_builtin_screens
    detect_xrandr_outputs
    detect_ddc_monitors

    # 写入检测结果
    cat > "$DETECTED_FILE" << EOF
# 屏幕亮度控制 - 硬件检测结果
# 生成时间: $(date)

DISPLAY_PROTOCOL=${DISPLAY_PROTOCOL}
XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-unknown}
DESKTOP=${DESKTOP}
TOOL_BRIGHTNESSCTL=${TOOL_BRIGHTNESSCTL}
TOOL_LIGHT=${TOOL_LIGHT}
TOOL_XRANDR=${TOOL_XRANDR}
TOOL_DDCUTIL=${TOOL_DDCUTIL}
TOOL_XGAMMA=${TOOL_XGAMMA}
TOOL_REDSHIFT=${TOOL_REDSHIFT}
TOOL_GAMMASTEP=${TOOL_GAMMASTEP}
BUILTIN_COUNT=${#BUILTIN_SCREENS[@]}
XRANDR_COUNT=${#XRANDR_OUTPUTS[@]}
DDC_COUNT=${#DDC_MONITORS[@]}
EOF

    # 写入内置屏幕详情
    local idx=0
    for screen in "${BUILTIN_SCREENS[@]}"; do
        IFS='|' read -r name path max <<< "$screen"
        echo "BUILTIN_${idx}_NAME=${name}" >> "$DETECTED_FILE"
        echo "BUILTIN_${idx}_PATH=${path}" >> "$DETECTED_FILE"
        echo "BUILTIN_${idx}_MAX=${max}"   >> "$DETECTED_FILE"
        idx=$(( idx + 1 ))
    done

    idx=0
    for output in "${XRANDR_OUTPUTS[@]}"; do
        echo "XRANDR_${idx}_NAME=${output}" >> "$DETECTED_FILE"
        idx=$(( idx + 1 ))
    done

    idx=0
    for mon in "${DDC_MONITORS[@]}"; do
        echo "DDC_${idx}_NUM=${mon}" >> "$DETECTED_FILE"
        idx=$(( idx + 1 ))
    done
}

###############################################################################
# 读取检测结果
###############################################################################

load_detected() {
    if [ ! -f "$DETECTED_FILE" ]; then
        run_detect
    fi
    # shellcheck disable=SC1090
    source "$DETECTED_FILE"
}

###############################################################################
# 亮度控制（核心逻辑）
###############################################################################

# 决定一个显示器应该用哪种方式控制亮度
# 返回: "backlight:<路径>:<最大值>" | "xrandr:<输出名>" | "ddc:<编号>" | "unknown"
get_control_method() {
    local device="$1"
    load_detected

    # 检查是否是内置屏幕 backlight 名称
    local i=0
    while [ $i -lt "${BUILTIN_COUNT:-0}" ]; do
        local varname="BUILTIN_${i}_NAME"
        if [ "${!varname}" = "$device" ]; then
            local path_var="BUILTIN_${i}_PATH"
            local max_var="BUILTIN_${i}_MAX"
            echo "backlight:${!path_var}:${!max_var}"
            return
        fi
        i=$(( i + 1 ))
    done

    # 检查是否是 xrandr 输出名称
    i=0
    while [ $i -lt "${XRANDR_COUNT:-0}" ]; do
        local varname="XRANDR_${i}_NAME"
        if [ "${!varname}" = "$device" ]; then
            echo "xrandr:${device}"
            return
        fi
        i=$(( i + 1 ))
    done

    # 检查是否是 DDC 编号
    i=0
    while [ $i -lt "${DDC_COUNT:-0}" ]; do
        local varname="DDC_${i}_NUM"
        if [ "${!varname}" = "$device" ]; then
            echo "ddc:${device}"
            return
        fi
        i=$(( i + 1 ))
    done

    echo "unknown"
}

# 设定亮度
# 用法: set_brightness <设备ID> <0-100>
set_brightness() {
    local device="$1"
    local pct="$2"

    # 边界检查
    [ "$pct" -lt 0   ] && pct=0
    [ "$pct" -gt 100 ] && pct=100

    local method
    method=$(get_control_method "$device")
    local method_type="${method%%:*}"
    local method_rest="${method#*:}"

    case "$method_type" in
        backlight)
            local path="${method_rest%%:*}"
            local max="${method_rest##*:}"
            local abs
            abs=$(awk "BEGIN{printf \"%d\", $pct * $max / 100}")
            [ "$abs" -lt 1 ] && abs=1

            # 方法1: 直接写入 /sys（udev 规则配置后，video 群组有权限）
            if [ -w "${path}brightness" ]; then
                echo "$abs" > "${path}brightness" && return
            fi

            # 方法2: brightnessctl（自动处理权限）
            if has_cmd brightnessctl; then
                brightnessctl -d "$device" set "${pct}%" > /dev/null 2>&1 && return || true
            fi

            # 方法3: sudo -n（已有 sudo session 时，不弹密码）
            if sudo -n tee "${path}brightness" > /dev/null 2>&1 <<< "$abs"; then
                return
            fi

            # 全部失败：提示配置权限
            print_error "亮度调整权限不足"
            print_info "请在脚本管理器选「重新安装」配置权限，或执行："
            print_info "sudo usermod -aG video \$USER  然后重新登入"
            ;;

        xrandr)
            local output="$method_rest"
            # 软件亮度 + Gamma 补偿（减少灰色感）
            local brightness
            brightness=$(awk "BEGIN{printf \"%.2f\", $pct / 100}")

            # Gamma 补偿：亮度越低，gamma 越高来提升对比度
            # 公式：gamma = 1 + (1 - brightness) * 0.5，最高 1.5
            local gamma
            gamma=$(awk "BEGIN{
                b=$brightness
                g = 1 + (1 - b) * 0.5
                if(g > 1.5) g = 1.5
                if(g < 1.0) g = 1.0
                printf \"%.2f\", g
            }")

            xrandr --output "$output" \
                   --brightness "$brightness" \
                   --gamma "${gamma}:${gamma}:${gamma}" \
                   2>/dev/null || {
                # 不支援 gamma 参数时回退
                xrandr --output "$output" --brightness "$brightness" 2>/dev/null
            }
            ;;

        ddc)
            local mon_num="$method_rest"
            # 先查询显示器实际支援的最大亮度值
            local ddc_max=100
            local raw_info
            raw_info=$(ddcutil --display "$mon_num" getvcp 0x10 2>/dev/null || true)
            if echo "$raw_info" | grep -q "maximum value"; then
                ddc_max=$(echo "$raw_info" | grep -oP 'maximum value\s*=\s*\K[0-9]+' | head -1)
                [ -z "$ddc_max" ] && ddc_max=100
            fi
            # 将百分比换算成显示器实际值
            local ddc_val
            ddc_val=$(awk "BEGIN{printf \"%d\", $pct * $ddc_max / 100}")
            [ "$ddc_val" -lt 1 ] && ddc_val=1
            # 尝试设定，失败时加 sudo 重试
            ddcutil --display "$mon_num" setvcp 0x10 "$ddc_val" 2>/dev/null || \
            sudo ddcutil --display "$mon_num" setvcp 0x10 "$ddc_val" 2>/dev/null || true
            ;;

        *)
            print_error "无法控制设备: $device（未找到支援的控制方式）"
            return 1
            ;;
    esac
}

# 读取目前亮度
get_brightness() {
    local device="$1"
    local method
    method=$(get_control_method "$device")
    local method_type="${method%%:*}"
    local method_rest="${method#*:}"

    case "$method_type" in
        backlight)
            local path="${method_rest%%:*}"
            local max="${method_rest##*:}"
            local cur
            cur=$(cat "${path}brightness" 2>/dev/null || echo 0)
            awk "BEGIN{printf \"%d\", $cur * 100 / $max}"
            ;;
        xrandr)
            # 从 xrandr 读取目前 brightness 值
            local output="$method_rest"
            local val
            val=$(xrandr --verbose 2>/dev/null \
                  | grep -A5 "^${output} connected" \
                  | grep -i "brightness" \
                  | grep -oP '[0-9.]+' | head -1)
            [ -z "$val" ] && val="1.0"
            awk "BEGIN{printf \"%d\", $val * 100}"
            ;;
        ddc)
            local mon_num="$method_rest"
            local val
            val=$(ddcutil --display "$mon_num" getvcp 0x10 2>/dev/null \
                  | grep -oP 'current value\s*=\s*\K[0-9]+' | head -1)
            echo "${val:-50}"
            ;;
        *)
            echo "50"
            ;;
    esac
}

###############################################################################
# 色温控制
###############################################################################

# 将色温 K 值转换为 RGB gamma 系数
# 参考 redshift 的算法简化版
kelvin_to_gamma() {
    local kelvin="$1"
    awk -v k="$kelvin" 'BEGIN {
        # 标准化到 0-1（2000K=0, 6500K=1）
        t = (k - 2000) / 4500

        # 红色：高色温全亮，低色温微降
        r = 1.0

        # 绿色：中间最高，两端略低
        if (t < 0.5)
            g = 0.8 + t * 0.4
        else
            g = 1.0 - (t - 0.5) * 0.1

        # 蓝色：低色温大幅降低（暖色），高色温全亮
        b = 0.4 + t * 0.6

        if (r > 1) r = 1; if (r < 0) r = 0
        if (g > 1) g = 1; if (g < 0) g = 0
        if (b > 1) b = 1; if (b < 0) b = 0

        printf "%.3f:%.3f:%.3f", r, g, b
    }'
}

# 设定色温
# 用法: set_temperature <设备ID> <2000-6500>
set_temperature() {
    local device="$1"
    local kelvin="$2"

    [ "$kelvin" -lt 2000 ] && kelvin=2000
    [ "$kelvin" -gt 6500 ] && kelvin=6500

    # ── Wayland 下的色温控制 ──────────────────────────────────────────────────
    if [ "${DISPLAY_PROTOCOL:-}" = "wayland" ] || [ "${XDG_SESSION_TYPE:-}" = "wayland" ]; then

        # 确保 DBUS 环境变量存在（从子进程调用时可能丢失）
        if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
            local dbus_addr
            dbus_addr=$(grep -z DBUS_SESSION_BUS_ADDRESS \
                /proc/$(pgrep -u "$USER" dbus-daemon 2>/dev/null | head -1)/environ \
                2>/dev/null | tr '\0' '\n' | grep DBUS_SESSION | cut -d= -f2- || true)
            [ -n "$dbus_addr" ] && export DBUS_SESSION_BUS_ADDRESS="$dbus_addr"
        fi

        # 方法1: gsettings（最可靠，T410/Zorin GNOME 已验证有效）
        if has_cmd gsettings && { [ "${DESKTOP:-}" = "gnome" ] || \
           echo "${XDG_CURRENT_DESKTOP:-}" | grep -qi "gnome\|zorin"; }; then
            gsettings set org.gnome.settings-daemon.plugins.color \
                night-light-schedule-automatic false 2>/dev/null || true
            gsettings set org.gnome.settings-daemon.plugins.color \
                night-light-schedule-from 0.0 2>/dev/null || true
            gsettings set org.gnome.settings-daemon.plugins.color \
                night-light-schedule-to 23.99 2>/dev/null || true
            gsettings set org.gnome.settings-daemon.plugins.color \
                night-light-enabled true 2>/dev/null || true
            gsettings set org.gnome.settings-daemon.plugins.color \
                night-light-temperature "$kelvin" 2>/dev/null && return || true
        fi

        # 方法2: busctl dbus（备用）
        if has_cmd busctl; then
            busctl --user set-property \
                org.gnome.SettingsDaemon.Color \
                /org/gnome/SettingsDaemon/Color \
                org.gnome.SettingsDaemon.Color \
                NightLightActive b true 2>/dev/null || true
            busctl --user set-property \
                org.gnome.SettingsDaemon.Color \
                /org/gnome/SettingsDaemon/Color \
                org.gnome.SettingsDaemon.Color \
                Temperature u "$kelvin" 2>/dev/null && return || true
        fi

        # 方法2: gammastep（非 GNOME Wayland，如 KDE、wlroots 等）
        if $TOOL_GAMMASTEP; then
            pkill -f "gammastep" 2>/dev/null || true
            sleep 0.3
            gammastep -O "$kelvin" 2>/dev/null && return || true
        fi

        # 方法3: wlsunset（另一个 Wayland 色温工具）
        if has_cmd wlsunset; then
            pkill -f "wlsunset" 2>/dev/null || true
            # wlsunset 需要经纬度，用固定温度模式
            wlsunset -T "$kelvin" -t "$kelvin" 2>/dev/null & return
        fi

        print_warning "色温调整在此 Wayland 环境下暂不支援"
        print_warning "GNOME 用户可手动在「设定 → 显示器 → 夜灯」调整"
        return
    fi

    # ── X11 下按控制方式处理 ──────────────────────────────────────────────────
    local method
    method=$(get_control_method "$device")
    local method_type="${method%%:*}"
    local method_rest="${method#*:}"

    case "$method_type" in
        xrandr)
            local output="$method_rest"
            local gamma
            gamma=$(kelvin_to_gamma "$kelvin")
            xrandr --output "$output" --gamma "$gamma" 2>/dev/null
            ;;
        backlight)
            # 方法1: gsettings GNOME 夜灯（Zorin/GNOME 最可靠，无论 x11 或 wayland）
            if has_cmd gsettings && { [ "${DESKTOP:-}" = "gnome" ] || \
               echo "${XDG_CURRENT_DESKTOP:-}" | grep -qi "gnome\|zorin"; }; then
                # 确保 DBUS 环境变量存在
                if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
                    local dbus_pid
                    dbus_pid=$(pgrep -u "$USER" dbus-daemon 2>/dev/null | head -1)
                    if [ -n "$dbus_pid" ]; then
                        local dbus_addr
                        dbus_addr=$(grep -z DBUS_SESSION_BUS_ADDRESS \
                            /proc/"$dbus_pid"/environ 2>/dev/null \
                            | tr '\0' '\n' | grep DBUS_SESSION | cut -d= -f2- || true)
                        [ -n "$dbus_addr" ] && export DBUS_SESSION_BUS_ADDRESS="$dbus_addr"
                    fi
                fi
                gsettings set org.gnome.settings-daemon.plugins.color \
                    night-light-schedule-automatic false 2>/dev/null || true
                gsettings set org.gnome.settings-daemon.plugins.color \
                    night-light-schedule-from 0.0 2>/dev/null || true
                gsettings set org.gnome.settings-daemon.plugins.color \
                    night-light-schedule-to 23.99 2>/dev/null || true
                gsettings set org.gnome.settings-daemon.plugins.color \
                    night-light-enabled true 2>/dev/null || true
                gsettings set org.gnome.settings-daemon.plugins.color \
                    night-light-temperature "$kelvin" 2>/dev/null && return || true
            fi

            # 方法2: xrandr gamma（X11 下）
            local xrandr_out=""
            load_detected
            local i=0
            while [ $i -lt "${XRANDR_COUNT:-0}" ]; do
                local vname="XRANDR_${i}_NAME"
                local name="${!vname}"
                if echo "$name" | grep -qiE "eDP|LVDS|DSI|panel"; then
                    xrandr_out="$name"
                    break
                fi
                i=$(( i + 1 ))
            done

            # 如果 xrandr 没找到内置输出，扫描所有已连接输出
            if [ -z "$xrandr_out" ] && has_cmd xrandr; then
                xrandr_out=$(xrandr 2>/dev/null \
                    | grep " connected" \
                    | awk '{print $1}' | head -1 || true)
            fi

            if [ -n "$xrandr_out" ]; then
                local gamma
                gamma=$(kelvin_to_gamma "$kelvin")
                xrandr --output "$xrandr_out" --gamma "$gamma" 2>/dev/null && return || true
            fi

            # 方法3: gammastep/redshift
            if $TOOL_GAMMASTEP; then
                pkill -f "gammastep" 2>/dev/null || true
                gammastep -O "$kelvin" 2>/dev/null & return
            elif $TOOL_REDSHIFT; then
                pkill -f "redshift" 2>/dev/null || true
                redshift -O "$kelvin" -P 2>/dev/null & return
            fi
            ;;
        ddc)
            # DDC 色温支援度差，优先用软件方案
            if $TOOL_REDSHIFT; then
                pkill -f "redshift" 2>/dev/null || true
                redshift -O "$kelvin" -P 2>/dev/null &
            elif $TOOL_GAMMASTEP; then
                pkill -f "gammastep" 2>/dev/null || true
                gammastep -O "$kelvin" -P 2>/dev/null &
            else
                # 最后才尝试 DDC VCP 0x0b（大多数显示器不支援）
                local ddc_val
                ddc_val=$(awk -v k="$kelvin" 'BEGIN{
                    if(k <= 2700) print 1
                    else if(k <= 3000) print 2
                    else if(k <= 4000) print 3
                    else if(k <= 5000) print 4
                    else if(k <= 6000) print 5
                    else print 6
                }')
                ddcutil --display "$method_rest" setvcp 0x0b "$ddc_val" 2>/dev/null || true
            fi
            ;;
    esac
}

###############################################################################
# 列出所有可用显示器
###############################################################################

cmd_list() {
    load_detected

    echo ""
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "   可用显示器列表"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "  协议: ${CYAN}${DISPLAY_PROTOCOL:-unknown}${NC}   桌面: ${CYAN}${DESKTOP:-unknown}${NC}"
    echo ""

    local found=false

    # 内置屏幕
    local i=0
    while [ $i -lt "${BUILTIN_COUNT:-0}" ]; do
        local name_var="BUILTIN_${i}_NAME"
        local path_var="BUILTIN_${i}_PATH"
        local max_var="BUILTIN_${i}_MAX"
        local name="${!name_var}"
        local cur_pct
        cur_pct=$(get_brightness "$name" 2>/dev/null || echo "?")
        echo -e "  ${GREEN}[内置]${NC} ${WHITE}${name}${NC}"
        echo -e "         路径: ${CYAN}${!path_var}${NC}"
        echo -e "         最大值: ${!max_var}   目前亮度: ${cur_pct}%"
        echo -e "         控制方式: backlight（硬件）"
        found=true
        i=$(( i + 1 ))
    done

    # xrandr 输出
    i=0
    while [ $i -lt "${XRANDR_COUNT:-0}" ]; do
        local name_var="XRANDR_${i}_NAME"
        local name="${!name_var}"
        local cur_pct
        cur_pct=$(get_brightness "$name" 2>/dev/null || echo "?")
        echo -e "  ${CYAN}[外接]${NC} ${WHITE}${name}${NC}"
        echo -e "         目前亮度: ${cur_pct}%"
        echo -e "         控制方式: xrandr（软件，含 Gamma 补偿）"
        found=true
        i=$(( i + 1 ))
    done

    # DDC 显示器
    i=0
    while [ $i -lt "${DDC_COUNT:-0}" ]; do
        local num_var="DDC_${i}_NUM"
        local num="${!num_var}"
        local cur_pct
        cur_pct=$(get_brightness "$num" 2>/dev/null || echo "?")
        echo -e "  ${YELLOW}[DDC]${NC}  ${WHITE}Display ${num}${NC}"
        echo -e "         目前亮度: ${cur_pct}%"
        echo -e "         控制方式: DDC/CI（硬件，最准确）"
        found=true
        i=$(( i + 1 ))
    done

    if ! $found; then
        print_warning "未检测到可控制的显示器"
        print_info "尝试重新检测: $0 detect"
    fi

    echo ""
}

###############################################################################
# 储存设定
###############################################################################

cmd_save() {
    local device="$1"
    local brightness="$2"
    local temperature="$3"

    # 读取现有设定
    local conf_content=""
    [ -f "$CONFIG_FILE" ] && conf_content=$(cat "$CONFIG_FILE")

    # 移除旧的该设备设定
    conf_content=$(echo "$conf_content" | grep -v "^${device}|" || true)

    # 追加新设定
    echo "${conf_content}" > "$CONFIG_FILE"
    echo "${device}|${brightness}|${temperature}" >> "$CONFIG_FILE"

    # 清除空行
    grep -v "^$" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && \
        mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE" || true

    print_success "已储存设定：$device → 亮度 ${brightness}%，色温 ${temperature}K"
}

###############################################################################
# 套用储存的设定
###############################################################################

cmd_load() {
    if [ ! -f "$CONFIG_FILE" ]; then
        print_warning "尚无储存的设定"
        return 0
    fi

    local loaded=0
    while IFS='|' read -r device brightness temperature; do
        [ -z "$device" ] && continue
        [[ "$device" == \#* ]] && continue

        set_brightness "$device" "$brightness" 2>/dev/null && \
            set_temperature "$device" "$temperature" 2>/dev/null && \
            loaded=$(( loaded + 1 )) || \
            print_warning "套用设定失败: $device"
    done < "$CONFIG_FILE"

    [ $loaded -gt 0 ] && \
        print_success "已套用 $loaded 个显示器的亮度设定" || \
        print_warning "没有成功套用任何设定"
}

###############################################################################
# 完整检测报告
###############################################################################

cmd_detect() {
    echo ""
    print_header "======================================"
    print_header "   屏幕亮度控制 - 硬件检测"
    print_header "======================================"
    echo ""

    print_step "正在检测环境..."
    run_detect
    load_detected

    echo ""
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "   检测结果"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    echo -e "  显示协议  : ${CYAN}${DISPLAY_PROTOCOL}${NC}"
    echo -e "  桌面环境  : ${CYAN}${DESKTOP}${NC}"
    echo ""

    echo -e "  已安装工具："
    $TOOL_BRIGHTNESSCTL && echo -e "  ${GREEN}✓${NC} brightnessctl" || echo -e "  ${RED}✗${NC} brightnessctl"
    $TOOL_XRANDR        && echo -e "  ${GREEN}✓${NC} xrandr"        || echo -e "  ${RED}✗${NC} xrandr"
    $TOOL_DDCUTIL       && echo -e "  ${GREEN}✓${NC} ddcutil"       || echo -e "  ${RED}✗${NC} ddcutil"
    $TOOL_REDSHIFT      && echo -e "  ${GREEN}✓${NC} redshift"      || echo -e "  ${RED}✗${NC} redshift"
    $TOOL_GAMMASTEP     && echo -e "  ${GREEN}✓${NC} gammastep"     || echo -e "  ${RED}✗${NC} gammastep"
    echo ""

    # 给出安装建议
    if ! $TOOL_DDCUTIL; then
        print_info "建议安装 ddcutil 以支援外接显示器硬件控制："
        echo -e "  ${CYAN}sudo apt install ddcutil${NC}"
    fi
    if ! $TOOL_BRIGHTNESSCTL; then
        print_info "建议安装 brightnessctl 以支援内置屏幕控制："
        echo -e "  ${CYAN}sudo apt install brightnessctl${NC}"
    fi

    echo ""
    cmd_list
}

###############################################################################
# 开机自动启动
###############################################################################

cmd_autostart() {
    local action="${1:-install}"
    local autostart_dir="$HOME/.config/autostart"
    local desktop_file="$autostart_dir/screen-brightness.desktop"
    local script_path
    script_path=$(realpath "$0")
    local tray_script
    tray_script="$(dirname "$script_path")/screen-brightness-tray.py"

    mkdir -p "$autostart_dir"

    case "$action" in
        install)
            cat > "$desktop_file" << EOF
[Desktop Entry]
Type=Application
Name=屏幕亮度控制
Comment=开机自动套用亮度设定并启动托盘图标
Exec=bash -c 'sleep 3 && ${script_path} load && python3 ${tray_script}'
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
StartupNotify=false
EOF
            chmod +x "$desktop_file"
            print_success "已安装开机自动启动"
            print_info "档案位置: $desktop_file"
            ;;
        remove)
            rm -f "$desktop_file"
            print_success "已移除开机自动启动"
            ;;
        *)
            print_error "用法: $0 autostart [install|remove]"
            ;;
    esac
}

###############################################################################
# 主程序入口
###############################################################################

CMD="${1:-detect}"

case "$CMD" in
    detect)
        cmd_detect
        ;;
    list)
        load_detected
        cmd_list
        ;;
    brightness)
        device="${2:-}"
        value="${3:-}"
        if [ -z "$device" ] || [ -z "$value" ]; then
            print_error "用法: $0 brightness <设备> <0-100>"
            exit 1
        fi
        load_detected
        set_brightness "$device" "$value"
        ;;
    temperature)
        device="${2:-}"
        value="${3:-}"
        if [ -z "$device" ] || [ -z "$value" ]; then
            print_error "用法: $0 temperature <设备> <2000-6500>"
            exit 1
        fi
        load_detected
        set_temperature "$device" "$value"
        exit 0
        ;;
    save)
        cmd_save "${2:-}" "${3:-80}" "${4:-6500}"
        ;;
    load)
        load_detected
        cmd_load
        ;;
    brightness-get)
        # 读取设备目前亮度百分比，供 tray.py 初始化时使用
        device="${2:-}"
        if [ -n "$device" ]; then
            load_detected
            get_brightness "$device" 2>/dev/null || echo "50"
        else
            echo "50"
        fi
        ;;
    autostart)
        cmd_autostart "${2:-install}"
        ;;
    *)
        print_error "未知指令: $CMD"
        echo "用法: $0 [detect|list|brightness|temperature|save|load|autostart]"
        exit 1
        ;;
esac
