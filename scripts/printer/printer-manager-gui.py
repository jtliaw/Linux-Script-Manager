#!/usr/bin/env python3
# printer-manager-gui.py
import tkinter as tk
from tkinter import ttk, messagebox, simpledialog
import subprocess
import os
import threading

# ─── 🛠️ 完美的动态项目绝对路径对齐 ───
# 无论从哪个目录拉起，哪怕是从主管理器的根目录下跨目录调用，都能100%精准定位
SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
BASH_SCRIPT = os.path.join(SCRIPT_DIR, "printer-helper.sh")

# 精致深色主题色彩配置
THEME = {
    "bg": "#1e1e2e",
    "bg_card": "#2a2a3e",
    "accent": "#89b4fa",
    "accent_hover": "#b4befe",
    "text": "#cdd6f4",
    "text_dim": "#6c7086",
    "danger": "#f38ba8",
    "success": "#a6e3a1",
    "win_bg": "#313244"
}

class PrinterManagerApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Linux 智能打印机一键神医与管理器")
        # 优化：窗口缩小为紧凑的 720x460，更适合作为子插件嵌入
        self.root.geometry("720x460")
        self.root.configure(bg=THEME["bg"])
        self.root.resizable(False, False) # 固定大小，防止布局变形
        
        # 统一设置 Treeview 样式
        style = ttk.Style()
        style.theme_use("clam")
        style.configure("Treeview", 
                        background=THEME["bg_card"], 
                        fieldbackground=THEME["bg_card"], 
                        foreground=THEME["text"],
                        rowheight=26) # 稍微调紧行高
        style.map("Treeview", background=[("selected", THEME["accent"])], foreground=[("selected", "#11111b")])
        
        self.printer_data = []
        self._data_lock = threading.Lock()   # 保护 printer_data 的读写，防止多次快速点击扫描造成竞争
        self._active_threads = 0             # 追踪活跃背景线程数，关窗时等待完成
        self.create_widgets()
        self.root.protocol("WM_DELETE_WINDOW", self._on_closing)
        
    def create_widgets(self):
        # 标题栏
        title_lbl = tk.Label(self.root, text="🖨️ Linux 智能打印机助手", font=("Helvetica", 14, "bold"), bg=THEME["bg"], fg=THEME["accent"])
        title_lbl.pack(pady=10) # 缩小间距
        
        # 按钮控制区框架
        btn_frame = tk.Frame(self.root, bg=THEME["bg"])
        btn_frame.pack(fill="x", padx=15, pady=2)
        
        # 一键搜索按钮
        self.scan_btn = tk.Button(btn_frame, text="🔍 智能搜索全网/USB打印机", font=("Helvetica", 10), 
                                  bg=THEME["accent"], fg="#11111b", activebackground=THEME["accent_hover"],
                                  bd=0, cursor="hand2", padx=12, pady=5, command=self.start_scan_thread)
        self.scan_btn.pack(side="left", padx=5)
        
        # 强力取消任务与重启按钮
        self.clear_btn = tk.Button(btn_frame, text="💥 强力取消任务并重置CUPS", font=("Helvetica", 10, "bold"), 
                                   bg=THEME["danger"], fg="#11111b", activebackground="#f5e0dc",
                                   bd=0, cursor="hand2", padx=12, pady=5, command=self.start_clear_thread)
        self.clear_btn.pack(side="right", padx=5)
        
        # 状态提示
        self.status_lbl = tk.Label(self.root, text="就绪。点击搜索开始扫描您的硬件与网络...", font=("Helvetica", 9), bg=THEME["bg"], fg=THEME["text_dim"])
        self.status_lbl.pack(fill="x", padx=20, pady=3, anchor="w")
        
        # 列表展示区
        list_frame = tk.Frame(self.root, bg=THEME["bg"])
        list_frame.pack(fill="both", expand=True, padx=15, pady=5)
        
        columns = ("kind", "name", "uri", "info")
        self.tree = ttk.Treeview(list_frame, columns=columns, show="headings", height=8) # 固定高度，确保存留底部空间
        self.tree.heading("kind", text="打印机类型")
        self.tree.heading("name", text="推荐别名")
        self.tree.heading("uri", text="局域网物理路径 (URI)")
        self.tree.heading("info", text="设备描述")
        
        self.tree.column("kind", width=90, anchor="center")
        self.tree.column("name", width=120, anchor="w")
        self.tree.column("uri", width=240, anchor="w")
        self.tree.column("info", width=220, anchor="w")
        
        scrollbar = ttk.Scrollbar(list_frame, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=scrollbar.set)
        self.tree.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        
        self.tree.bind("<Double-1>", self.on_item_double_click)
        
        # 优化：安装框架和按钮，放宽边缘，确保 100% 可见
        install_frame = tk.Frame(self.root, bg=THEME["bg"])
        install_frame.pack(fill="x", padx=15, pady=12) 
        
        self.add_btn = tk.Button(install_frame, text="⚡ 一键自动安装选中的打印机 (支持双击选择)", font=("Helvetica", 11, "bold"),
                                 bg=THEME["success"], fg="#11111b", activebackground="#b4befe",
                                 bd=0, cursor="hand2", pady=8, command=self.install_selected_printer)
        self.add_btn.pack(fill="x")

    def _parse_field(self, field_str, prefix_len):
        """安全解析 'KEY:VALUE' 字段，VALUE 本身可能含冒号（如 ipp://host:port/...）。
        prefix_len 是 'KEY:' 的字符数，直接切片取后段，完整保留 URI。"""
        return field_str[prefix_len:]

    def start_scan_thread(self):
        self.scan_btn.config(state="disabled", text="正在全网深层搜索...")
        self.status_lbl.config(text="正在唤醒 Avahi/Samba 引擎探测内网打印机，请稍候...", fg=THEME["accent"])
        self.tree.delete(*self.tree.get_children())
        with self._data_lock:
            self.printer_data.clear()
        self._active_threads += 1
        threading.Thread(target=self.run_scan, daemon=True).start()

    def run_scan(self):
        try:
            process = subprocess.Popen(
                [BASH_SCRIPT, "scan"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
            )
            local_buf = []
            inside_block = False
            for line in process.stdout:
                line = line.strip()
                if line == "===SCAN_START===":
                    inside_block = True
                    continue
                if line == "===SCAN_END===":
                    inside_block = False
                    continue
                if inside_block and line.startswith("KIND:"):
                    parts = line.split("|")
                    if len(parts) < 4:
                        continue
                    # 用 prefix_len 切片，完整保留 URI 中的多个冒号（ipp://host:port/...）
                    kind = self._parse_field(parts[0], len("KIND:"))
                    uri  = self._parse_field(parts[1], len("URI:"))
                    name = self._parse_field(parts[2], len("NAME:"))
                    info = self._parse_field(parts[3], len("INFO:"))
                    local_buf.append({"kind": kind, "uri": uri, "name": name, "info": info})
            process.wait()
            # 全部解析完再一次性写入，减少锁持有时间
            with self._data_lock:
                self.printer_data.extend(local_buf)
            self.root.after(0, self.update_table_ui, "SUCCESS")
        except Exception as e:
            self.root.after(0, self.update_table_ui, f"ERROR: {str(e)}")
        finally:
            self._active_threads -= 1

    def update_table_ui(self, status):
        self.scan_btn.config(state="normal", text="🔍 智能搜索全网/USB打印机")
        if "ERROR" in status:
            self.status_lbl.config(text=f"扫描失败: {status}", fg=THEME["danger"])
            return
        for p in self.printer_data:
            if p["kind"] == "USB":
                kind_show = "🔌 USB直连"
            elif p["kind"] == "LINUX":
                kind_show = "🐧 Linux/IPP"
            elif "SCAN_PLACEHOLDER" in p["uri"] or "ManualEntry" in p["uri"] or "MANUAL_ENTRY" in p["uri"]:
                kind_show = "🪟 Win(需确认)"
            else:
                kind_show = "🪟 Win(已发现)"
            self.tree.insert("", "end", values=(kind_show, p["name"], p["uri"], p["info"]))
        self.status_lbl.config(text=f"扫描完成！共发现 {len(self.printer_data)} 台设备。双击或点击下方大按钮自动装配驱动。", fg=THEME["success"])

    def start_clear_thread(self):
        if messagebox.askyesno("警告", "您是否确认启动【强力重置】？\n这将会清空全系统所有打印机中的全部任务，并重置CUPS后台服务。"):
            self.status_lbl.config(text="正在强制剿灭打印任务死锁并清洗CUPS缓存...", fg=THEME["danger"])
            self._active_threads += 1
            threading.Thread(target=self.run_clear, daemon=True).start()

    def run_clear(self):
        try:
            process = subprocess.Popen(
                ["pkexec", BASH_SCRIPT, "clear"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
            )
            task_count = 0
            for line in process.stdout:
                line = line.strip()
                if line.startswith("TASK_COUNT:"):
                    task_count = line.split(":")[1]
            process.wait()
            self.root.after(0, self.show_clear_report, task_count)
        except Exception as e:
            self.root.after(0, lambda: messagebox.showerror("错误", f"提权或执行清理失败:\n{str(e)}"))
        finally:
            self._active_threads -= 1

    def show_clear_report(self, count):
        self.status_lbl.config(text="系统 CUPS 后台已成功清洗并满血复活！", fg=THEME["success"])
        messagebox.showinfo("神医体检报告", f"【清道夫任务完成】\n\n检测到当前后台积压死锁任务: {count} 个\n已全部强力抹除完毕！\nCUPS 后台服务已成功优雅重启。")

    def on_item_double_click(self, event):
        self.install_selected_printer()
        
    def install_selected_printer(self):
        selected = self.tree.selection()
        if not selected:
            messagebox.showwarning("提示", "请先在列表中选择一台发现的打印机设备。")
            return
        item = self.tree.item(selected[0])
        vals = item["values"]
        printer = None
        with self._data_lock:
            for p in self.printer_data:
                if p["uri"] in str(vals[2]) or vals[1] == p["name"]:
                    printer = dict(p)   # 复制一份，避免背景线程操作时数据被清空
                    break
        if not printer:
            return
        
        username = ""
        password = ""
        if printer["kind"] == "WINDOWS":
            if messagebox.askyesno("需要凭据", "您选择的是【Windows 共享打印机】。\n是否需要配置账号密码？"):
                username = simpledialog.askstring("凭据配置", "请输入 Windows 电脑的用户名:", parent=self.root)
                if username:
                    password = simpledialog.askstring("凭据配置", "请输入该用户的密码:", show="*", parent=self.root)
        
        uri_to_install = printer["uri"]

        if "MANUAL_ENTRY" in uri_to_install or "ManualEntry" in uri_to_install:
            # 工具完全缺失，引导用户手动填写
            manual_ip = simpledialog.askstring(
                "手动添加 Windows 打印机",
                "未能自动发现局域网内的 Windows 主机。\n\n"
                "请输入 Windows 电脑的 IP 地址（如 192.168.1.100）：",
                parent=self.root
            )
            if not manual_ip:
                return
            manual_share = simpledialog.askstring(
                "手动添加 Windows 打印机",
                f"IP 地址：{manual_ip}\n\n"
                "请输入打印机共享名（在 Windows「打印机属性 → 共享」中查看）：",
                parent=self.root
            )
            if not manual_share:
                return
            uri_to_install = f"smb://{manual_ip}/{manual_share}"
            printer["name"] = f"Win_{manual_share.replace(' ', '_')}"

        elif "SCAN_PLACEHOLDER" in uri_to_install:
            # smbclient 发现了共享但 nmblookup 解析 IP 失败，让用户手动确认 IP
            share_part = uri_to_install.split("SCAN_PLACEHOLDER/")[-1]
            confirmed_ip = simpledialog.askstring(
                "请确认 Windows 主机 IP",
                f"已发现共享打印机：{share_part}\n"
                "但未能自动解析其 IP 地址。\n\n"
                "请输入该 Windows 电脑的 IP 地址（如 192.168.1.100）：",
                parent=self.root
            )
            if not confirmed_ip:
                return
            uri_to_install = uri_to_install.replace("SCAN_PLACEHOLDER", confirmed_ip)
        # 否则 URI 已包含真实 IP（nmblookup 自动解析成功），直接使用，无需弹窗

        self.status_lbl.config(text=f"正在为 {printer['name']} 静默匹配并配置万能驱动...", fg=THEME["accent"])

        def do_add():
            try:
                cmd = ["pkexec", BASH_SCRIPT, "add",
                       printer["name"], printer["kind"], uri_to_install,
                       username or "", password or ""]
                res = subprocess.run(cmd, stdout=subprocess.PIPE, text=True, timeout=30)
                if "ADD_STATUS:SUCCESS" in res.stdout:
                    self.root.after(0, lambda: messagebox.showinfo("成功", f"🎉 打印机 [{printer['name']}] 已成功添加进您的 Linux 系统！"))
                    self.root.after(0, lambda: self.status_lbl.config(text="打印机添加成功！", fg=THEME["success"]))
                else:
                    self.root.after(0, lambda: messagebox.showerror("错误", "驱动安装失败。可能由于此旧款打印机不支持 Driverless 协议。"))
            except Exception as e:
                self.root.after(0, lambda: messagebox.showerror("错误", f"安装终止: {str(e)}"))
            finally:
                self._active_threads -= 1

        self._active_threads += 1
        threading.Thread(target=do_add, daemon=True).start()

    def _on_closing(self):
        """关闭窗口时等待背景线程完成，避免 CUPS 配置写到一半被强制中断。"""
        if self._active_threads > 0:
            # 有背景任务正在进行，提示用户
            if not messagebox.askyesno(
                "有任务进行中",
                f"当前有 {self._active_threads} 个操作正在后台执行中。\n"
                "强行关闭可能导致打印机配置不完整。\n\n确定要退出吗？"
            ):
                return
        try:
            self.root.destroy()
        except Exception:
            pass

if __name__ == "__main__":
    root = tk.Tk()
    app = PrinterManagerApp(root)
    root.mainloop()
