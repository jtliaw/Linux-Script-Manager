#!/usr/bin/env python3
"""
Linux Script Manager

Copyright (C) 2025 JTLIAW

Licensed under the MIT License. See the LICENSE file for details.
"""

"""
Linux脚本管理器 - 完整版
支持sudo权限切换，支持任意脚本添加
支持中英文切换
修复Lubuntu QTerminal兼容性问题
"""

import os
import sys
import subprocess
import tkinter as tk
from tkinter import ttk, messagebox
from PIL import Image, ImageTk
import glob
import threading
import json

class I18n:
    """国际化翻译类"""
    LANGUAGES = {
        'zh': {
            'title': 'Linux脚本管理器',
            'subtitle': '快速访问和管理您的Linux脚本工具',
            'no_scripts': '暂无可用脚本\n请将.sh脚本文件放入scripts目录',
            'script_dir': '脚本目录',
            'refresh': '刷新',
            'terminal': '终端',
            'quit': '退出',
            'launch': '启动工具',
            'requires_sudo': '需要管理员权限',
            'normal_user': '普通权限',
            'ready': '就绪',
            'success': '成功',
            'error': '错误',
            'script_updated': '已更新',
            'perm_updated': '权限已更新',
            'script_run_error': '执行脚本时出错',
            'terminal_not_found': '未找到可用的终端程序',
            'terminal_open_error': '无法打开终端',
            'scripts_refreshed': '脚本列表已刷新，共找到',
            'scripts': '个脚本',
            'system_tool': '系统工具脚本',
            'menu_language': '语言',
            'menu_english': '英文',
            'menu_chinese': '中文',
            'press_enter': '按Enter关闭',
        },
        'en': {
            'title': 'Linux Script Manager',
            'subtitle': 'Quick access and management of your Linux script tools',
            'no_scripts': 'No scripts available\nPlease put .sh script files in the scripts directory',
            'script_dir': 'Script Directory',
            'refresh': 'Refresh',
            'terminal': 'Terminal',
            'quit': 'Quit',
            'launch': 'Launch Tool',
            'requires_sudo': 'Requires Admin Rights',
            'normal_user': 'Normal Permission',
            'ready': 'Ready',
            'success': 'Success',
            'error': 'Error',
            'script_updated': 'Updated',
            'perm_updated': 'Permission Updated',
            'script_run_error': 'Error running script',
            'terminal_not_found': 'No terminal found',
            'terminal_open_error': 'Cannot open terminal',
            'scripts_refreshed': 'Script list refreshed, found',
            'scripts': 'scripts',
            'system_tool': 'System Tool Script',
            'menu_language': 'Language',
            'menu_english': 'English',
            'menu_chinese': '中文',
            'press_enter': 'Press Enter to close',
        }
    }
    
    def __init__(self, lang='zh'):
        self.lang = lang if lang in self.LANGUAGES else 'zh'
    
    def t(self, key):
        """获取翻译文本"""
        return self.LANGUAGES[self.lang].get(key, key)
    
    def set_language(self, lang):
        """切换语言"""
        if lang in self.LANGUAGES:
            self.lang = lang

class LinuxScriptManager:
    def __init__(self):
        self.root = tk.Tk()
        self.i18n = I18n('zh')  # 默认中文
        self.root.title(self.i18n.t('title'))
        self.root.geometry("700x600")
        self.root.configure(bg='#0f3460')
        self.root.resizable(False, False)
        
        # 脚本目录
        self.script_dir = "./scripts"
        if not os.path.exists(self.script_dir):
            os.makedirs(self.script_dir)
            self.create_default_scripts()
        
        self.scripts = []
        self.load_scripts()
        
        self.photo_image = None
        self.icon_images = []
        
        # 尝试设置窗口图标
        try:
            if os.path.exists('linux-tool.png'):
                icon_img = Image.open('linux-tool.png')
                icon_img = icon_img.resize((256, 256), Image.Resampling.LANCZOS)
                window_icon = ImageTk.PhotoImage(icon_img)
                self.root.iconphoto(True, window_icon)
                self.icon_images.append(window_icon)
        except Exception as e:
            print(f"Icon setup error: {e}")
        
        self.create_ui()
    
    def create_default_scripts(self):
        """创建默认脚本文件（可选）"""
        scripts_info = [
            ('backup-tool.sh', 'Backup Tool', False, 'File backup and recovery / 文件备份和恢复'),
            ('network-diag.sh', 'Network Diagram', False, 'Network connection diagnostics / 网络连接诊断工具'),
            ('fix-usb.sh', 'Fix USB', False, 'Detect and fix USB issues / 检测并修复USB设备问题'),
            ('usb-info.sh', 'USB Info', False, 'View USB device details / 查看USB设备详细信息'),
            ('format-usb.sh', 'Format USB', True, 'Quick format USB device / 快速格式化USB设备'),
            ('disk-clean.sh', 'Disk Clean', True, 'Clean temp files and cache / 清理临时文件和缓存')
        ]
        
        for script_name, display_name, requires_sudo, description in scripts_info:
            script_path = os.path.join(self.script_dir, script_name)
            content = f'''#!/bin/bash
# {display_name}
# DESCRIPTION: {description}
# REQUIRES_SUDO: {'true' if requires_sudo else 'false'}

echo "=== {display_name} ==="
echo "This is a sample script / 这是一个示例脚本"
echo "Running task... / 正在执行任务..."
for i in 1 2 3 4 5; do
    echo "Progress: $i/5 / 进度: $i/5"
    sleep 0.5
done
echo "Execution completed / 执行完成！"
'''
            with open(script_path, 'w') as f:
                f.write(content)
            os.chmod(script_path, 0o755)
    
    def load_scripts(self):
        """加载scripts目录中的所有脚本"""
        self.scripts = []
        script_files = glob.glob(os.path.join(self.script_dir, "*.sh"))
        
        for script_file in script_files:
            if os.path.isfile(script_file):
                if not os.access(script_file, os.X_OK):
                    os.chmod(script_file, 0o755)
                
                script_info = self.parse_script_info(script_file)
                if script_info:
                    self.scripts.append(script_info)
        
        self.scripts.sort(key=lambda x: x['display_name'])
    
    def parse_script_info(self, script_path):
        """解析脚本信息 - 现在支持任意脚本文件"""
        try:
            script_name = os.path.basename(script_path)
            
            # 默认显示名称：去掉扩展名，替换连字符为空格，单词首字母大写
            base_name = script_name.replace('.sh', '')
            display_name = ' '.join(word.capitalize() for word in base_name.replace('-', ' ').replace('_', ' ').split())
            
            requires_sudo = False
            description = self.i18n.t('system_tool')
            
            with open(script_path, 'r', encoding='utf-8', errors='ignore') as f:
                lines = f.readlines()
                
                for line in lines[:20]:
                    line = line.strip()
                    if line.startswith('# DESCRIPTION:'):
                        description = line.split('# DESCRIPTION:')[1].strip()
                    elif line.startswith('# REQUIRES_SUDO:'):
                        requires_sudo = 'true' in line.lower()
                    elif line.startswith('# DISPLAY_NAME:'):
                        display_name = line.split('# DISPLAY_NAME:')[1].strip()
                    elif line.startswith('#'):
                        if description == self.i18n.t('system_tool') and len(line) > 2 and not line.startswith('#!/'):
                            potential_desc = line[1:].strip()
                            if potential_desc and not any(x in potential_desc.upper() for x in ['REQUIRES_SUDO', 'DISPLAY_NAME']):
                                description = potential_desc
            
            return {
                'path': script_path,
                'name': script_name,
                'display_name': display_name,
                'description': description,
                'requires_sudo': requires_sudo
            }
        except Exception as e:
            print(f"Error parsing script {script_path}: {e}")
            return None
    
    def create_ui(self):
        """创建用户界面"""
        main_frame = tk.Frame(self.root, bg='#0f3460')
        main_frame.pack(fill='both', expand=True, padx=15, pady=15)
        
        self.create_header(main_frame)
        self.create_scrollable_cards(main_frame)
        self.create_footer(main_frame)
    
    def change_language(self, lang):
        """切换语言"""
        self.i18n.set_language(lang)
        self.root.title(self.i18n.t('title'))
        # 清空并重新创建UI
        for widget in self.root.winfo_children():
            widget.destroy()
        
        main_frame = tk.Frame(self.root, bg='#0f3460')
        main_frame.pack(fill='both', expand=True, padx=15, pady=15)
        
        self.create_header(main_frame)
        self.create_scrollable_cards(main_frame)
        self.create_footer(main_frame)
    
    def load_icon(self):
        """加载图标"""
        try:
            if os.path.exists('linux-tool.png'):
                img = Image.open('linux-tool.png')
                
                if img.mode != 'RGBA':
                    img = img.convert('RGBA')
                
                img = img.resize((80, 80), Image.Resampling.LANCZOS)
                icon_image = ImageTk.PhotoImage(img)
                return icon_image
            else:
                return None
        except Exception as e:
            print(f"Load icon error: {e}")
            return None
    
    def create_header(self, parent):
        """创建标题区域"""
        header_frame = tk.Frame(parent, bg='#0f3460')
        header_frame.pack(fill='x', pady=(0, 20))
        
        content_frame = tk.Frame(header_frame, bg='#0f3460')
        content_frame.pack(anchor='center')
        
        self.photo_image = self.load_icon()
        if self.photo_image:
            self.icon_images.append(self.photo_image)
            icon_label = tk.Label(content_frame, image=self.photo_image, bg='#0f3460', 
                                 bd=0, highlightthickness=0)
            icon_label.image = self.photo_image
            icon_label.pack(side='left', padx=(0, 20))
        else:
            placeholder = tk.Frame(content_frame, width=80, height=80, bg='#1a5276', relief='solid', bd=2)
            placeholder.pack(side='left', padx=(0, 20))
            placeholder.pack_propagate(False)
            placeholder_label = tk.Label(placeholder, text='🔧', font=('Arial', 40), bg='#1a5276', fg='#00d4ff')
            placeholder_label.pack(expand=True)
        
        text_frame = tk.Frame(content_frame, bg='#0f3460')
        text_frame.pack(side='left')
        
        title_label = tk.Label(text_frame,
                              text=self.i18n.t('title'),
                              font=('Arial', 18, 'bold'),
                              fg='#00d4ff',
                              bg='#0f3460')
        title_label.pack(anchor='w')
        
        subtitle_label = tk.Label(text_frame,
                                 text=self.i18n.t('subtitle'),
                                 font=('Arial', 10),
                                 fg='#a0a0a0',
                                 bg='#0f3460')
        subtitle_label.pack(anchor='w', pady=(5, 0))
    
    def create_scrollable_cards(self, parent):
        """创建带滚动条的卡片区域"""
        cards_main_frame = tk.Frame(parent, bg='#0f3460')
        cards_main_frame.pack(fill='both', expand=True, pady=10)
        
        self.canvas = tk.Canvas(cards_main_frame, bg='#0f3460', highlightthickness=0)
        scrollbar = ttk.Scrollbar(cards_main_frame, orient="vertical", command=self.canvas.yview)
        
        self.scrollable_frame = tk.Frame(self.canvas, bg='#0f3460')
        
        self.canvas_frame = self.canvas.create_window((0, 0), window=self.scrollable_frame, anchor="nw")
        self.canvas.configure(yscrollcommand=scrollbar.set)
        
        self.canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        
        def _on_mousewheel(event):
            self.canvas.yview_scroll(int(-1 * (event.delta / 120)), "units")
        
        self.canvas.bind("<MouseWheel>", _on_mousewheel)
        self.canvas.bind("<Button-4>", lambda e: self.canvas.yview_scroll(-3, "units"))
        self.canvas.bind("<Button-5>", lambda e: self.canvas.yview_scroll(3, "units"))
        
        self.scrollable_frame.bind("<Configure>", lambda e: self.canvas.configure(scrollregion=self.canvas.bbox("all")))
        self.canvas.bind("<Configure>", self._on_canvas_configure)
        
        self.display_cards()
    
    def _on_canvas_configure(self, event):
        """调整内部框架宽度"""
        self.canvas.itemconfig(self.canvas_frame, width=event.width)
        self.scrollable_frame.update_idletasks()
        self.canvas.configure(scrollregion=self.canvas.bbox("all"))
    
    def get_lang_text(self):
        """获取当前语言按钮文本"""
        return "English" if self.i18n.lang == 'zh' else "中文"
    
    def toggle_language(self):
        """切换语言"""
        new_lang = 'en' if self.i18n.lang == 'zh' else 'zh'
        self.change_language(new_lang)
    
    def create_footer(self, parent):
        """创建底部按钮区域"""
        footer_frame = tk.Frame(parent, bg='#000000')
        footer_frame.pack(fill='x', pady=(10, 0))
        
        info_label = tk.Label(footer_frame,
                             text=f"{self.i18n.t('script_dir')}: {os.path.abspath(self.script_dir)}",
                             font=('Arial', 8),
                             fg='#707070',
                             bg='#000000')
        info_label.pack(side='left')
        
        btn_frame = tk.Frame(footer_frame, bg='#000000')
        btn_frame.pack(side='right')
        
        # 语言切换按钮
        lang_btn = self.create_modern_button(btn_frame, self.get_lang_text(), '#c9a805', self.toggle_language)
        lang_btn.pack(side='left', padx=5)
        self.lang_btn = lang_btn
        
        refresh_btn = self.create_modern_button(btn_frame, self.i18n.t('refresh'), '#00d4ff', self.refresh_scripts)
        refresh_btn.pack(side='left', padx=5)
        
        terminal_btn = self.create_modern_button(btn_frame, self.i18n.t('terminal'), '#9b59b6', self.open_terminal)
        terminal_btn.pack(side='left', padx=5)
        
        quit_btn = self.create_modern_button(btn_frame, self.i18n.t('quit'), '#e74c3c', self.root.quit)
        quit_btn.pack(side='left', padx=5)
    
    def create_modern_button(self, parent, text, color, command):
        """创建现代化按钮"""
        btn = tk.Button(parent,
                       text=text,
                       command=command,
                       font=('Arial', 9, 'bold'),
                       bg=color,
                       fg='white',
                       activebackground=self.lighten_color(color),
                       activeforeground='white',
                       relief='flat',
                       bd=0,
                       padx=12,
                       pady=6,
                       cursor='hand2')
        
        def on_enter(e):
            btn['bg'] = self.lighten_color(color)
        def on_leave(e):
            btn['bg'] = color
        
        btn.bind("<Enter>", on_enter)
        btn.bind("<Leave>", on_leave)
        
        return btn
    
    def lighten_color(self, color):
        """亮化颜色"""
        r = int(color[1:3], 16)
        g = int(color[3:5], 16)
        b = int(color[5:7], 16)
        
        r = min(255, r + 40)
        g = min(255, g + 40)
        b = min(255, b + 40)
        
        return f'#{r:02x}{g:02x}{b:02x}'
    
    def display_cards(self):
        """显示所有脚本卡片"""
        for widget in self.scrollable_frame.winfo_children():
            widget.destroy()
        
        if not self.scripts:
            empty_label = tk.Label(self.scrollable_frame,
                                  text=self.i18n.t('no_scripts'),
                                  font=('Arial', 12),
                                  fg='#707070',
                                  bg='#0f3460',
                                  justify='center')
            empty_label.pack(pady=50)
            return
        
        cards_container = tk.Frame(self.scrollable_frame, bg='#0f3460')
        cards_container.pack(fill='both', expand=True)
        
        row, col = 0, 0
        for i, script in enumerate(self.scripts):
            card = self.create_script_card(cards_container, script)
            card.grid(row=row, column=col, padx=8, pady=8, sticky='nsew')
            
            col += 1
            if col >= 2:
                col = 0
                row += 1
        
        for i in range(row + 1):
            cards_container.rowconfigure(i, weight=1)
        cards_container.columnconfigure(0, weight=1)
        cards_container.columnconfigure(1, weight=1)
        
        self.scrollable_frame.update_idletasks()
        self.canvas.configure(scrollregion=self.canvas.bbox("all"))
    
    def create_script_card(self, parent, script):
        """创建单个脚本卡片"""
        card = tk.Frame(parent,
                       bg='#1a5276',
                       relief='solid',
                       bd=0,
                       highlightthickness=2,
                       highlightbackground='#00d4ff',
                       highlightcolor='#00ffff',
                       width=300,
                       height=160)
        card.pack_propagate(False)
        
        def on_enter(e):
            card.configure(highlightbackground='#00ffff', bg='#1a6a96')
        def on_leave(e):
            card.configure(highlightbackground='#00d4ff', bg='#1a5276')
        
        card.bind("<Enter>", on_enter)
        card.bind("<Leave>", on_leave)
        
        content_frame = tk.Frame(card, bg='#1a5276')
        content_frame.pack(fill='both', expand=True, padx=14, pady=12)
        
        title_label = tk.Label(content_frame,
                              text=script['display_name'],
                              font=('Arial', 13, 'bold'),
                              fg='#ffffff',
                              bg='#1a5276')
        title_label.pack(anchor='w', pady=(0, 8))
        
        desc_label = tk.Label(content_frame,
                             text=script['description'],
                             font=('Arial', 9),
                             fg='#b0b0b0',
                             bg='#1a5276',
                             wraplength=270,
                             justify='left')
        desc_label.pack(anchor='w', pady=(0, 10), fill='x')
        
        info_frame = tk.Frame(content_frame, bg='#1a5276')
        info_frame.pack(fill='x', pady=(0, 10))
        
        status_frame = tk.Frame(info_frame, bg='#1a5276')
        status_frame.pack(side='left', fill='x', expand=True)
        
        status_dot = tk.Frame(status_frame, bg='#27ae60', width=8, height=8)
        status_dot.pack(side='left')
        status_dot.pack_propagate(False)
        
        status_label = tk.Label(status_frame,
                               text=self.i18n.t('ready'),
                               font=('Arial', 8),
                               fg='#27ae60',
                               bg='#1a5276')
        status_label.pack(side='left', padx=(4, 0))
        
        perm_text = self.i18n.t('requires_sudo') if script['requires_sudo'] else self.i18n.t('normal_user')
        perm_color = '#e74c3c' if script['requires_sudo'] else '#27ae60'
        
        perm_label = tk.Label(info_frame,
                             text=perm_text,
                             font=('Arial', 8),
                             fg=perm_color,
                             bg='#1a5276',
                             cursor='hand2')
        perm_label.pack(side='right')
        
        def toggle_sudo(e):
            script['requires_sudo'] = not script['requires_sudo']
            self.update_script_sudo(script)
            new_perm_text = self.i18n.t('requires_sudo') if script['requires_sudo'] else self.i18n.t('normal_user')
            new_perm_color = '#e74c3c' if script['requires_sudo'] else '#27ae60'
            perm_label.config(text=new_perm_text, fg=new_perm_color)
            messagebox.showinfo(self.i18n.t('success'), 
                              f"{self.i18n.t('script_updated')}: {script['display_name']}\n{self.i18n.t('perm_updated')}: {new_perm_text}")
        
        perm_label.bind("<Button-1>", toggle_sudo)
        
        launch_btn = tk.Button(content_frame,
                              text=self.i18n.t('launch'),
                              command=lambda s=script: self.run_script(s),
                              font=('Arial', 10, 'bold'),
                              bg='#00d4ff',
                              fg='#1a1a2e',
                              activebackground='#00ffff',
                              activeforeground='#1a1a2e',
                              relief='flat',
                              bd=0,
                              padx=15,
                              pady=5,
                              cursor='hand2')
        launch_btn.pack(fill='x')
        
        return card
    
    def update_script_sudo(self, script):
        """更新脚本的REQUIRES_SUDO字段"""
        try:
            with open(script['path'], 'r', encoding='utf-8') as f:
                lines = f.readlines()
            
            updated = False
            for i, line in enumerate(lines):
                if '# REQUIRES_SUDO:' in line:
                    sudo_value = 'true' if script['requires_sudo'] else 'false'
                    lines[i] = f"# REQUIRES_SUDO: {sudo_value}\n"
                    updated = True
                    break
            
            if not updated:
                for i, line in enumerate(lines):
                    if line.startswith('#!/'):
                        lines.insert(i + 1, f"# REQUIRES_SUDO: {'true' if script['requires_sudo'] else 'false'}\n")
                        break
            
            with open(script['path'], 'w', encoding='utf-8') as f:
                f.writelines(lines)
        except Exception as e:
            messagebox.showerror(self.i18n.t('error'), f"{self.i18n.t('script_run_error')}: {str(e)}")
    
    def run_script(self, script):
        """运行脚本"""
        thread = threading.Thread(target=self._run_script_thread, args=(script,))
        thread.daemon = True
        thread.start()
    
    def _run_script_thread(self, script):
        """运行脚本的线程函数 - 修复Lubuntu QTerminal兼容性"""
        try:
            script_path = os.path.abspath(script['path'])
            terminal = self.get_terminal()
            
            if not terminal:
                # 如果没找到终端，直接执行脚本（但不推荐）
                if script['requires_sudo']:
                    if self.check_command('pkexec'):
                        subprocess.Popen(['pkexec', 'bash', script_path])
                    else:
                        subprocess.Popen(['sudo', 'bash', script_path])
                else:
                    subprocess.Popen(['bash', script_path])
                return
            
            press_enter = self.i18n.t('press_enter')
            
            # 针对不同终端使用不同的命令格式
            if 'qterminal' in terminal:
                # QTerminal (Lubuntu默认) 使用 -e 参数，但需要特殊格式
                if script['requires_sudo']:
                    # QTerminal 需要将整个命令作为一个参数传递
                    subprocess.Popen([terminal, '-e', 'bash', '-c', 
                                    f'sudo bash "{script_path}"; echo ""; echo "{press_enter}"; read'])
                else:
                    subprocess.Popen([terminal, '-e', 'bash', '-c', 
                                    f'bash "{script_path}"; echo ""; echo "{press_enter}"; read'])
            elif 'lxterminal' in terminal:
                # LXTerminal 需要使用 --command 参数
                if script['requires_sudo']:
                    cmd = f'bash -c "sudo bash \\"{script_path}\\"; echo \\"\\n{press_enter}\\"; read"'
                    subprocess.Popen([terminal, '--command', cmd])
                else:
                    cmd = f'bash -c "bash \\"{script_path}\\"; echo \\"\\n{press_enter}\\"; read"'
                    subprocess.Popen([terminal, '--command', cmd])
            elif 'konsole' in terminal:
                # Konsole 使用 --hold -e
                if script['requires_sudo']:
                    subprocess.Popen([terminal, '--hold', '-e', 'sudo', 'bash', script_path])
                else:
                    subprocess.Popen([terminal, '--hold', '-e', 'bash', script_path])
            else:
                # gnome-terminal, xfce4-terminal, xterm 等使用标准格式
                if script['requires_sudo']:
                    cmd = f'bash -c \'sudo bash "{script_path}"; echo "\\n{press_enter}"; read\''
                else:
                    cmd = f'bash -c \'bash "{script_path}"; echo "\\n{press_enter}"; read\''
                subprocess.Popen([terminal, '-e', cmd])
                
        except Exception as e:
            messagebox.showerror(self.i18n.t('error'), f"{self.i18n.t('script_run_error')}: {str(e)}")
    
    def open_terminal(self):
        """打开终端"""
        terminal = self.get_terminal()
        if terminal:
            try:
                subprocess.Popen([terminal])
            except Exception as e:
                messagebox.showerror(self.i18n.t('error'), f"{self.i18n.t('terminal_open_error')}: {e}")
        else:
            messagebox.showerror(self.i18n.t('error'), self.i18n.t('terminal_not_found'))
    
    def check_command(self, command):
        """检查命令是否存在"""
        try:
            subprocess.run(['which', command], check=True, capture_output=True)
            return True
        except subprocess.CalledProcessError:
            return False
    
    def get_terminal(self):
        """获取可用的终端 - 优先使用 QTerminal (Lubuntu默认)"""
        # Lubuntu 22.04+ 优先使用 qterminal
        terminals = ['qterminal', 'lxterminal', 'gnome-terminal', 'konsole', 'xfce4-terminal', 'xterm']
        for terminal in terminals:
            if self.check_command(terminal):
                return terminal
        return None
    
    def refresh_scripts(self):
        """刷新脚本列表"""
        self.load_scripts()
        self.display_cards()
        messagebox.showinfo(self.i18n.t('success'), 
                          f"{self.i18n.t('scripts_refreshed')} {len(self.scripts)} {self.i18n.t('scripts')}")
    
    def run(self):
        """启动应用"""
        self.root.geometry("700x600")
        x = (self.root.winfo_screenwidth() // 2) - (350)
        y = (self.root.winfo_screenheight() // 2) - (300)
        self.root.geometry(f"+{x}+{y}")
        self.root.mainloop()

def main():
    """主函数"""
    try:
        app = LinuxScriptManager()
        app.run()
    except Exception as e:
        print(f"Application startup error: {e}")
        print("Please ensure Python3 and Tkinter are installed")
        print("On Ubuntu/Debian: sudo apt install python3-tk python3-pil python3-pil.imagetk")

if __name__ == "__main__":
    main()
