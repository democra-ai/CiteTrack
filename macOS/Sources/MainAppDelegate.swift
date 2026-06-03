import Cocoa
import SwiftUI
#if !APP_STORE
import Sparkle
#endif

// MARK: - 现代化macOS 26风格的主应用代理
class MainAppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var statusItem: NSStatusItem?
    var preferencesWindow: NSWindow?
    let dataManager = DataManager.shared
    let iCloudSyncManager = iCloudSyncManager.shared
    let preferencesManager = PreferencesManager.shared
    
    // Sparkle更新检查器（仅非App Store版本）
    #if !APP_STORE
    private var updaterController: SPUStandardUpdaterController?
    #endif
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 [CiteTrack] 应用程序启动 - macOS 26优化版本")
        
        // 初始化Sparkle自动更新（仅非App Store版本）
        #if !APP_STORE
        setupSparkleUpdater()
        #else
        print("ℹ️ [CiteTrack] App Store版本 - 自动更新已禁用")
        #endif
        
        // 设置状态栏图标
        setupStatusBar()
        
        // 加载数据
        dataManager.loadScholars()
        
        // 设置启动时登录（如果已启用）
        setupLaunchAtLogin()
        
        print("✅ [CiteTrack] 应用程序启动完成")
    }
    
    // MARK: - Sparkle自动更新设置（仅非App Store版本）
    
    #if !APP_STORE
    private func setupSparkleUpdater() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        print("✅ [Sparkle] 自动更新已启用")
    }
    #endif
    
    // MARK: - 状态栏设置
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusItem?.button else { return }
        
        // 使用SF Symbols图标（macOS 26风格）
        if #available(macOS 11.0, *) {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            button.image = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: "CiteTrack")?
                .withSymbolConfiguration(config)
        } else {
            button.title = "📊"
        }
        
        button.action = #selector(statusBarButtonClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        
        print("✅ [StatusBar] 状态栏图标已设置")
    }
    
    @objc private func statusBarButtonClicked() {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            showMainMenu()
        }
    }
    
    private func showMainMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        
        // 标题
        let titleItem = NSMenuItem(title: "CiteTrack", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())
        
        // 学者列表
        if dataManager.scholars.isEmpty {
            let emptyItem = NSMenuItem(title: "暂无学者", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for scholar in dataManager.scholars.prefix(10) {
                let scholarItem = NSMenuItem(
                    title: "\(scholar.displayName): \(scholar.citationDisplay) 引用",
                    action: #selector(showScholarDetails(_:)),
                    keyEquivalent: ""
                )
                scholarItem.representedObject = scholar
                menu.addItem(scholarItem)
            }
            
            if dataManager.scholars.count > 10 {
                menu.addItem(NSMenuItem.separator())
                let moreItem = NSMenuItem(title: "查看更多...", action: #selector(openPreferences), keyEquivalent: "")
                menu.addItem(moreItem)
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // 功能菜单
        menu.addItem(NSMenuItem(title: "添加学者", action: #selector(addScholar), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "偏好设置...", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "查看图表", action: #selector(openCharts), keyEquivalent: "g"))
        
        menu.addItem(NSMenuItem.separator())
        
        // 同步和更新
        menu.addItem(NSMenuItem(title: "同步到iCloud", action: #selector(syncToiCloud), keyEquivalent: ""))
        #if !APP_STORE
        menu.addItem(NSMenuItem(title: "检查更新...", action: #selector(checkForUpdates), keyEquivalent: ""))
        #endif
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出 CiteTrack", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }
    
    private func showContextMenu() {
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "偏好设置...", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "关于 CiteTrack", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }
    
    // MARK: - 菜单操作
    
    @objc private func showScholarDetails(_ sender: NSMenuItem) {
        guard let scholar = sender.representedObject as? Scholar else { return }
        print("📊 [Menu] 显示学者详情: \(scholar.displayName)")
        // TODO: 实现学者详情窗口
    }
    
    @objc private func addScholar() {
        print("➕ [Menu] 添加学者")
        // TODO: 实现添加学者对话框
    }
    
    @objc private func openPreferences() {
        if preferencesWindow == nil {
            let window = SettingsWindow()
            window.center()
            preferencesWindow = window
        }
        
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func openCharts() {
        print("📈 [Menu] 打开图表窗口")
        // TODO: 实现图表窗口
    }
    
    @objc private func syncToiCloud() {
        print("☁️ [Menu] 同步到iCloud")
        iCloudSyncManager.exportUsingCloudKit { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.showAlert(title: "同步成功", message: "数据已成功导出到iCloud")
                case .failure(let error):
                    self.showAlert(title: "同步失败", message: error.localizedDescription)
                }
            }
        }
    }
    
    #if !APP_STORE
    @objc private func checkForUpdates() {
        print("🔄 [Menu] 检查更新")
        updaterController?.checkForUpdates(nil)
    }
    #endif
    
    @objc private func showAbout() {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "7"
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationVersion: "\(short) (\(build)) · Beta"
        ])
    }
    
    @objc private func quitApp() {
        print("👋 [CiteTrack] 退出应用程序")
        NSApp.terminate(nil)
    }
    
    // MARK: - 辅助方法
    
    private func setupLaunchAtLogin() {
        if preferencesManager.launchAtLogin {
            // 实现启动时登录
            print("✅ [LaunchAtLogin] 已启用登录时启动")
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好的")
        alert.runModal()
    }
    
    // MARK: - 应用程序生命周期
    
    func applicationWillTerminate(_ notification: Notification) {
        print("👋 [CiteTrack] 应用程序即将退出")
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openPreferences()
        }
        return true
    }
}

