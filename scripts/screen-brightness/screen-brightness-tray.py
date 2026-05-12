#!/usr/bin/env python3
# screen-brightness-tray.py
# 屏幕亮度控制托盘图标 + 滑杆 GUI
# 依赖: python3-tk（所有 Linux 发行版内建）
# 可选: python3-pil（托盘图标更好看）

import tkinter as tk
from tkinter import ttk, messagebox
import subprocess
import os
import sys
import json
import threading
import time

# ── 路径设定 ──────────────────────────────────────────────────────────────────
SCRIPT_DIR    = os.path.dirname(os.path.realpath(__file__))
BASH_SCRIPT   = os.path.join(SCRIPT_DIR, "screen-brightness.sh")
CONFIG_DIR    = os.path.expanduser("~/.config/screen-brightness")
CONFIG_FILE   = os.path.join(CONFIG_DIR, "settings.conf")
DETECTED_FILE = os.path.join(CONFIG_DIR, "detected.conf")

os.makedirs(CONFIG_DIR, exist_ok=True)

# ── 颜色主题 ──────────────────────────────────────────────────────────────────
THEME = {
    "bg":           "#1e1e2e",
    "bg_card":      "#2a2a3e",
    "accent":       "#89b4fa",
    "accent2":      "#f5c2e7",
    "text":         "#cdd6f4",
    "text_dim":     "#6c7086",
    "success":      "#a6e3a1",
    "warning":      "#fab387",
    "slider_trough":"#313244",
    "btn_bg":       "#313244",
    "btn_active":   "#45475a",
}
RED_COLOR = "#f38ba8"   # 退出按钮悬停颜色

###############################################################################
# 与 bash 脚本通讯
###############################################################################

def run_bash(args, timeout=5):
    """执行 bash 脚本，返回 (success, output)"""
    try:
        cmd = ["bash", BASH_SCRIPT] + args
        result = subprocess.run(
            cmd, capture_output=True, text=True,
            timeout=timeout, env={**os.environ}
        )
        return result.returncode == 0, result.stdout.strip()
    except subprocess.TimeoutExpired:
        return False, "timeout"
    except Exception as e:
        return False, str(e)

def run_bash_bg(args):
    """背景执行，不等待结果"""
    threading.Thread(
        target=lambda: run_bash(args, timeout=10),
        daemon=True
    ).start()

###############################################################################
# 读取检测结果
###############################################################################

def load_detected():
    """从 detected.conf 读取显示器列表"""
    if not os.path.exists(DETECTED_FILE):
        run_bash(["detect"])

    conf = {}
    try:
        with open(DETECTED_FILE) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    k, v = line.split("=", 1)
                    conf[k.strip()] = v.strip()
    except Exception:
        return []

    monitors = []

    # 内置屏幕
    builtin_count = int(conf.get("BUILTIN_COUNT", 0))
    for i in range(builtin_count):
        name = conf.get(f"BUILTIN_{i}_NAME", "")
        if name:
            monitors.append({
                "id":    name,
                "label": f"内置屏幕 ({name})",
                "type":  "backlight",
                "icon":  "💻",
            })

    # xrandr 输出
    xrandr_count = int(conf.get("XRANDR_COUNT", 0))
    for i in range(xrandr_count):
        name = conf.get(f"XRANDR_{i}_NAME", "")
        if name:
            # 跳过已经在 builtin 里的内置屏幕对应输出
            is_builtin_output = any(
                n in name.upper()
                for n in ["EDP", "LVDS", "DSI"]
            )
            label = f"内置屏幕 - {name}" if is_builtin_output else f"外接显示器 ({name})"
            icon  = "💻" if is_builtin_output else "🖥"
            monitors.append({
                "id":    name,
                "label": label,
                "type":  "xrandr",
                "icon":  icon,
            })

    # DDC 显示器
    ddc_count = int(conf.get("DDC_COUNT", 0))
    for i in range(ddc_count):
        num = conf.get(f"DDC_{i}_NUM", "")
        if num:
            monitors.append({
                "id":    num,
                "label": f"外接显示器 DDC (Display {num})",
                "type":  "ddc",
                "icon":  "🖥",
            })

    # 如果完全没检测到，加一个占位符
    if not monitors:
        monitors.append({
            "id":    "unknown",
            "label": "未检测到显示器",
            "type":  "unknown",
            "icon":  "❓",
        })

    return monitors

###############################################################################
# 设定档读写
###############################################################################

def load_settings():
    """读取储存的亮度/色温设定"""
    settings = {}
    if not os.path.exists(CONFIG_FILE):
        return settings
    try:
        with open(CONFIG_FILE) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split("|")
                if len(parts) >= 3:
                    device, brightness, temperature = parts[0], parts[1], parts[2]
                    settings[device] = {
                        "brightness":   int(brightness),
                        "temperature":  int(temperature),
                    }
    except Exception:
        pass
    return settings

def save_setting(device, brightness, temperature):
    """储存一个显示器的设定"""
    run_bash_bg(["save", device, str(brightness), str(temperature)])

###############################################################################
# 主 GUI 窗口
###############################################################################

class BrightnessWindow(tk.Toplevel):
    """亮度控制弹出窗口"""

    def __init__(self, parent, monitors, settings, auto_close=True):
        super().__init__(parent)
        self.parent   = parent
        self.monitors = monitors
        self.settings = settings
        self._apply_timer = {}

        self.title("屏幕亮度控制")
        self.resizable(False, False)
        self.configure(bg=THEME["bg"])

        self.update_idletasks()
        sw = self.winfo_screenwidth()
        sh = self.winfo_screenheight()
        w, h = 360, 80 + len(monitors) * 140
        x = sw - w - 20
        # 往上移 110px，避开右下角浮动按钮（浮动按钮高 40px，位于 sh-90）
        y = sh - h - 65
        self.geometry(f"{w}x{h}+{x}+{y}")

        # 不绑定 FocusOut：切换窗口不应关闭亮度控制窗口
        self.protocol("WM_DELETE_WINDOW", self.close)
        self._build_ui()
        self.focus_force()

    def _on_focus_out(self, event):
        self.after(100, self._check_focus)

    def _check_focus(self):
        try:
            focused = self.focus_get()
            if focused is None:
                self.close()
        except Exception:
            pass

    def close(self):
        """只关闭亮度窗口，不退出程序（浮动按钮保留）"""
        try:
            self.destroy()
        except Exception:
            pass

    def _build_ui(self):
        # 标题栏
        header = tk.Frame(self, bg=THEME["bg"], pady=8)
        header.pack(fill="x", padx=16)
        tk.Label(
            header, text="☀  屏幕亮度控制",
            bg=THEME["bg"], fg=THEME["accent"],
            font=("Sans", 12, "bold")
        ).pack(side="left")

        # 重新检测按钮
        tk.Button(
            header, text="⟳",
            bg=THEME["btn_bg"], fg=THEME["text_dim"],
            activebackground=THEME["btn_active"],
            relief="flat", bd=0, padx=6, pady=2,
            cursor="hand2",
            command=self._redetect
        ).pack(side="right")

        # 分隔线
        tk.Frame(self, bg=THEME["slider_trough"], height=1).pack(fill="x", padx=12)

        # 每个显示器的控制卡片
        self.monitor_vars = {}
        for mon in self.monitors:
            self._build_monitor_card(mon)

        # 底部按钮
        btn_frame = tk.Frame(self, bg=THEME["bg"], pady=8)
        btn_frame.pack(fill="x", padx=16)

        tk.Button(
            btn_frame, text="💾 储存为默认",
            bg=THEME["btn_bg"], fg=THEME["success"],
            activebackground=THEME["btn_active"],
            relief="flat", bd=0, padx=12, pady=5,
            cursor="hand2", font=("Sans", 9),
            command=self._save_all
        ).pack(side="left")

    def _build_monitor_card(self, mon):
        device  = mon["id"]
        label   = mon["label"]
        icon    = mon["icon"]
        is_unknown = mon["type"] == "unknown"

        saved = self.settings.get(device, {})
        init_bright = saved.get("brightness",  80)
        init_temp   = saved.get("temperature", 6500)

        # 卡片框架
        card = tk.Frame(self, bg=THEME["bg_card"], padx=14, pady=10)
        card.pack(fill="x", padx=12, pady=6)

        # 显示器标签
        tk.Label(
            card, text=f"{icon}  {label}",
            bg=THEME["bg_card"], fg=THEME["text"],
            font=("Sans", 9, "bold"), anchor="w"
        ).pack(fill="x")

        if is_unknown:
            tk.Label(
                card, text="未检测到可控制的显示器\n请点击 ⟳ 重新检测",
                bg=THEME["bg_card"], fg=THEME["warning"],
                font=("Sans", 8), anchor="w", justify="left"
            ).pack(fill="x", pady=4)
            return

        # ── 亮度滑杆 ──────────────────────────────────────────────
        bright_frame = tk.Frame(card, bg=THEME["bg_card"])
        bright_frame.pack(fill="x", pady=(8, 0))

        tk.Label(
            bright_frame, text="亮度",
            bg=THEME["bg_card"], fg=THEME["text_dim"],
            font=("Sans", 8), width=4, anchor="w"
        ).pack(side="left")

        bright_var = tk.IntVar(value=init_bright)
        bright_label = tk.Label(
            bright_frame, text=f"{init_bright}%",
            bg=THEME["bg_card"], fg=THEME["accent"],
            font=("Sans", 8, "bold"), width=5, anchor="e"
        )
        bright_label.pack(side="right")

        bright_slider = ttk.Scale(
            bright_frame, from_=10, to=100,
            orient="horizontal", variable=bright_var,
            length=220
        )
        bright_slider.pack(side="left", fill="x", expand=True, padx=6)

        # ── 色温滑杆 ──────────────────────────────────────────────
        temp_frame = tk.Frame(card, bg=THEME["bg_card"])
        temp_frame.pack(fill="x", pady=(6, 0))

        tk.Label(
            temp_frame, text="色温",
            bg=THEME["bg_card"], fg=THEME["text_dim"],
            font=("Sans", 8), width=4, anchor="w"
        ).pack(side="left")

        temp_var = tk.IntVar(value=init_temp)

        def temp_to_label(k):
            if k <= 3000:   return f"{k}K 🌙"
            elif k <= 4500: return f"{k}K 🌅"
            elif k <= 5500: return f"{k}K ☁"
            else:           return f"{k}K ☀"

        temp_label = tk.Label(
            temp_frame, text=temp_to_label(init_temp),
            bg=THEME["bg_card"], fg=THEME["accent2"],
            font=("Sans", 8, "bold"), width=8, anchor="e"
        )
        temp_label.pack(side="right")

        temp_slider = ttk.Scale(
            temp_frame, from_=2000, to=6500,
            orient="horizontal", variable=temp_var,
            length=220
        )
        temp_slider.pack(side="left", fill="x", expand=True, padx=6)

        # 储存变量供后续使用
        self.monitor_vars[device] = {
            "brightness": bright_var,
            "temperature": temp_var,
        }

        # ── 事件绑定：拖动时防抖套用 ──────────────────────────────
        def on_bright_change(val):
            v = int(float(val))
            bright_var.set(v)
            bright_label.config(text=f"{v}%")
            self._debounce_apply(device, "brightness", v)

        def on_temp_change(val):
            # 色温对齐到 100K 整数
            v = round(float(val) / 100) * 100
            temp_var.set(v)
            temp_label.config(text=temp_to_label(v))
            self._debounce_apply(device, "temperature", v)

        bright_slider.config(command=on_bright_change)
        temp_slider.config(command=on_temp_change)

    def _debounce_apply(self, device, param, value):
        """防抖：拖动停止 300ms 后才真正套用，避免连续 call bash"""
        key = f"{device}_{param}"
        if key in self._apply_timer:
            self.after_cancel(self._apply_timer[key])

        def do_apply():
            if param == "brightness":
                run_bash_bg(["brightness", device, str(value)])
            else:
                run_bash_bg(["temperature", device, str(value)])

        self._apply_timer[key] = self.after(300, do_apply)

    def _save_all(self):
        """储存所有显示器的目前设定"""
        for device, vars_ in self.monitor_vars.items():
            bright = vars_["brightness"].get()
            temp   = vars_["temperature"].get()
            save_setting(device, bright, temp)
        # 短暂显示成功提示
        self._show_toast("✓ 已储存为默认设定")

    def _show_toast(self, msg):
        """在窗口底部短暂显示提示文字"""
        toast = tk.Label(
            self, text=msg,
            bg=THEME["success"], fg=THEME["bg"],
            font=("Sans", 9, "bold"), pady=4
        )
        toast.pack(fill="x", side="bottom")
        self.after(2000, toast.destroy)

    def _redetect(self):
        """重新检测显示器"""
        def do():
            run_bash(["detect"])
            self.after(0, self._reload_monitors)
        threading.Thread(target=do, daemon=True).start()

    def _reload_monitors(self):
        self.monitors = load_detected()
        self.settings = load_settings()
        self.close()
        # 重新开启窗口
        win = BrightnessWindow(self.parent, self.monitors, self.settings)
        win.grab_set()

###############################################################################
# 系统托盘（用纯 tkinter 模拟，不依赖额外库）
###############################################################################

class TrayApp:
    """
    屏幕亮度控制托盘应用。
    架构：tkinter 始终在主线程运行（mainloop）。
    若有 pystray：在子线程注册系统托盘图标，点击事件用 root.after() 传回主线程。
    若无 pystray：用 tkinter 浮动按钮替代。
    """

    def __init__(self):
        self.monitors = []
        self.settings = {}
        self.popup    = None

        # tkinter 主窗口始终在主线程
        self.root = tk.Tk()
        self.root.withdraw()

        # 背景初始化
        threading.Thread(target=self._init_background, daemon=True).start()

        # 强制使用浮动按钮（pystray 在不同启动方式下行为不一致，放弃使用）
        self._build_fallback_button()

        # tkinter 主循环在主线程
        self.root.mainloop()

    def _init_background(self):
        run_bash(["detect"], timeout=15)
        run_bash(["load"],   timeout=10)
        self.monitors = load_detected()
        self.settings = load_settings()

    # ── pystray 子线程托盘 ────────────────────────────────────────────────────

    def _start_pystray_thread(self, pystray, Image, ImageDraw):
        """在子线程启动 pystray，点击事件用 root.after 安全传回主线程"""
        import math

        def make_icon():
            img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
            d   = ImageDraw.Draw(img)
            cx, cy, r = 32, 32, 14
            d.ellipse([cx-r, cy-r, cx+r, cy+r], fill=(255, 220, 100, 255))
            for angle in range(0, 360, 45):
                rad = math.radians(angle)
                x1  = cx + (r + 3)  * math.cos(rad)
                y1  = cy + (r + 3)  * math.sin(rad)
                x2  = cx + (r + 10) * math.cos(rad)
                y2  = cy + (r + 10) * math.sin(rad)
                d.line([x1, y1, x2, y2], fill=(255, 220, 100, 255), width=3)
            return img

        def on_clicked(icon, item):
            # 通过 root.after 把操作调度到主线程执行
            self.root.after(0, self._toggle_popup)

        def on_quit(icon, item):
            icon.stop()
            self.root.after(0, self.root.quit)

        def run_icon():
            try:
                menu = pystray.Menu(
                    pystray.MenuItem("Brightness Control", on_clicked, default=True),
                    pystray.MenuItem("Quit", on_quit),
                )
                icon = pystray.Icon(
                    "screen-brightness",
                    make_icon(),
                    "Screen Brightness",
                    menu
                )
                icon.run()
            except Exception as e:
                print(f"pystray 错误: {e}")
                # pystray 失败时在主线程显示浮动按钮
                self.root.after(0, self._build_fallback_button)

        threading.Thread(target=run_icon, daemon=True).start()

    # ── 弹出/关闭亮度窗口（在主线程调用）────────────────────────────────────

    def _toggle_popup(self):
        if self.popup and self.popup.winfo_exists():
            self.popup.close()
            self.popup = None
        else:
            self.monitors = load_detected()
            self.settings = load_settings()
            self.popup = BrightnessWindow(self.root, self.monitors, self.settings)

    # ── 浮动按钮（回退方案）──────────────────────────────────────────────────

    def _build_fallback_button(self):
        self.btn_win = tk.Toplevel(self.root)
        self.btn_win.overrideredirect(True)
        self.btn_win.attributes("-topmost", True)
        self.btn_win.attributes("-alpha", 0.85)
        self.btn_win.configure(bg=THEME["bg"])

        sw = self.btn_win.winfo_screenwidth()
        sh = self.btn_win.winfo_screenheight()
        # 宽度改为 90，容纳两个按钮
        self.btn_win.geometry(f"90x40+{sw-100}+{sh-90}")

        # ☀ 按钮：开关亮度窗口
        sun_btn = tk.Label(
            self.btn_win, text="☀",
            bg=THEME["bg"], fg=THEME["accent"],
            font=("Sans", 18), cursor="hand2",
            padx=6, pady=4
        )
        sun_btn.pack(side="left", fill="both", expand=True)
        sun_btn.bind("<Button-1>", lambda e: self._toggle_popup())

        # 分隔线
        tk.Frame(self.btn_win, bg=THEME["slider_trough"],
                 width=1).pack(side="left", fill="y", pady=4)

        # ✕ 按钮：真正退出程序
        quit_btn = tk.Label(
            self.btn_win, text="✕",
            bg=THEME["bg"], fg=THEME["text_dim"],
            font=("Sans", 11), cursor="hand2",
            padx=6, pady=4
        )
        quit_btn.pack(side="left", fill="both")
        quit_btn.bind("<Button-1>", lambda e: self.root.quit())

        # 悬停效果
        def on_enter_sun(e):  sun_btn.config(fg=THEME["warning"])
        def on_leave_sun(e):  sun_btn.config(fg=THEME["accent"])
        def on_enter_quit(e): quit_btn.config(fg=RED_COLOR)
        def on_leave_quit(e): quit_btn.config(fg=THEME["text_dim"])

        sun_btn.bind("<Enter>",  on_enter_sun)
        sun_btn.bind("<Leave>",  on_leave_sun)
        quit_btn.bind("<Enter>", on_enter_quit)
        quit_btn.bind("<Leave>", on_leave_quit)

        # 右键拖动整个浮动窗口
        self._drag_x = self._drag_y = 0

        def start_drag(e):
            self._drag_x, self._drag_y = e.x_root, e.y_root

        def do_drag(e):
            dx = e.x_root - self._drag_x
            dy = e.y_root - self._drag_y
            x  = self.btn_win.winfo_x() + dx
            y  = self.btn_win.winfo_y() + dy
            self.btn_win.geometry(f"+{x}+{y}")
            self._drag_x, self._drag_y = e.x_root, e.y_root

        for w in (self.btn_win, sun_btn, quit_btn):
            w.bind("<Button-3>",  start_drag)
            w.bind("<B3-Motion>", do_drag)

    def _redetect(self):
        def do():
            run_bash(["detect"], timeout=15)
            self.monitors = load_detected()
            self.settings = load_settings()
        threading.Thread(target=do, daemon=True).start()

###############################################################################
# 入口
###############################################################################

def main():
    # 检查 bash 脚本是否存在
    if not os.path.exists(BASH_SCRIPT):
        print(f"错误：找不到 {BASH_SCRIPT}")
        print("请确认 screen-brightness.sh 与本脚本在同一目录")
        sys.exit(1)

    # TrayApp.__init__ 内部会阻塞（pystray.run 或 tkinter mainloop）
    TrayApp()

if __name__ == "__main__":
    main()
