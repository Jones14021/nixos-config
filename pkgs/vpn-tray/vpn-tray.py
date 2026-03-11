#!/usr/bin/env python3
import sys, subprocess
from PyQt6.QtWidgets import QApplication, QSystemTrayIcon, QMenu
from PyQt6.QtGui import QIcon, QAction
from PyQt6.QtCore import QTimer

def run_cmd(cmd):
    """Run a shell command and return its stdout"""
    return subprocess.run(cmd, capture_output=True, text=True).stdout.strip()

class VPNTray(QSystemTrayIcon):
    def __init__(self):
        super().__init__()
        # Default icon
        self.setIcon(QIcon.fromTheme("network-vpn"))
        self.setToolTip("WireGuard Tray Manager")
        
        self.menu = QMenu()
        self.setContextMenu(self.menu)
        self.update_menu()

        # Poll systemd every 3 seconds to update the UI if changed externally
        self.timer = QTimer()
        self.timer.timeout.connect(self.update_menu)
        self.timer.start(3000)

    def update_menu(self):
        self.menu.clear()
        
        # Discover all wg-quick services natively
        units_raw = run_cmd(['systemctl', 'list-unit-files', 'wg-quick-*.service', '--no-legend', '--plain'])
        if not units_raw:
            act = QAction("No VPNs Found", self.menu)
            act.setDisabled(True)
            self.menu.addAction(act)
            self.menu.addSeparator()
            self.add_quit()
            return

        any_active = False
        
        # Build the menu items
        for line in units_raw.split('\n'):
            if not line: continue
            unit = line.split()[0]
            name = unit.replace('wg-quick-', '').replace('.service', '')
            
            status = run_cmd(['systemctl', 'is-active', unit])
            is_active = (status == 'active')
            if is_active: any_active = True

            icon = "security-high" if is_active else "security-low"
            state_text = "ON" if is_active else "OFF"
            
            action = QAction(QIcon.fromTheme(icon), f"{name} ({state_text})", self.menu)
            # Python closure trap fix: bind variables using default args (u=unit, a=is_active)
            action.triggered.connect(lambda checked, u=unit, a=is_active: self.toggle(u, a))
            self.menu.addAction(action)

        # Update the main tray icon to show global status
        self.setIcon(QIcon.fromTheme("network-vpn" if any_active else "network-disconnect"))
        
        self.menu.addSeparator()
        self.add_quit()

    def add_quit(self):
        quit_act = QAction(QIcon.fromTheme("application-exit"), "Quit", self.menu)
        quit_act.triggered.connect(QApplication.quit)
        self.menu.addAction(quit_act)

    def toggle(self, unit, is_active):
        cmd = 'stop' if is_active else 'start'
        subprocess.run(['systemctl', cmd, unit])
        self.update_menu()

if __name__ == '__main__':
    app = QApplication(sys.argv)
    # Prevent the tray app from exiting when the menu closes
    app.setQuitOnLastWindowClosed(False)
    tray = VPNTray()
    tray.show()
    sys.exit(app.exec())
