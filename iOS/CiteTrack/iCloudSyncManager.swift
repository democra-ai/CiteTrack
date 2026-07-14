import Foundation
import UIKit
import UniformTypeIdentifiers

// MARK: - iCloud Sync Manager
class iCloudSyncManager: ObservableObject {
	static let shared = iCloudSyncManager()
	
	@Published var isImporting = false
	@Published var isExporting = false
	@Published var lastSyncDate: Date?
	@Published var syncStatus: String = "icloud_available_no_sync".localized
	@Published var showingFilePicker = false
	@Published var importResult: ImportResult?
	@Published var showingImportResult = false
	@Published var errorMessage: String = ""
	@Published var showingErrorAlert = false
	@Published var hasBookmarkedDriveDirectory: Bool = false
	// 首次启动检测到备份时的提示
	@Published var showImportPrompt: Bool = false
	@Published var importPromptMessage: String = ""
	
	private let folderName = "CiteTrack"
	private let dataFileName = "citation_data.json"
	private let configFileName = "ios_data.json"
	private let longTermSyncFileName = "CiteTrack_sync.json"
	private let driveBookmarkKey = "iCloudDrivePreferredDirectoryBookmark"
	
	private init() {}

	// MARK: - First-launch helper
	/// 首次安装/重装后的第一次启动：优先从 iCloud 容器 Documents 读取现有备份（两个文件）
	/// 1) 引导容器与 Documents 出现；2) 尝试拉取 ios_data.json 与 citation_data.json；3) 调用导入
	func importConfigOnFirstLaunch() {
		#if targetEnvironment(simulator)
		print("ℹ️ [FirstLaunch Import] Simulator detected - skip iCloud first-launch import")
		return
		#else
		let flagKey = "FirstLaunchImportDone"
		if UserDefaults.standard.bool(forKey: flagKey) {
			return
		}
		guard isiCloudAvailable else {
			print("ℹ️ [FirstLaunch Import] iCloud not available, skip")
			return
		}
		
		// 🚀 优化：延迟执行，避免阻塞启动
		DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
			// 引导容器（后台执行）
			self.bootstrapContainerIfPossible()
			
			// 如检测到现有备份，先弹窗询问
			if let docs = self.documentsURL {
				let fm = FileManager.default
				let iosURL = docs.appendingPathComponent("ios_data.json")
				let citURL = docs.appendingPathComponent("citation_data.json")
				let hasIOS = fm.fileExists(atPath: iosURL.path)
				let hasCIT = fm.fileExists(atPath: citURL.path)
				if hasIOS || hasCIT {
					DispatchQueue.main.async {
						self.importPromptMessage = hasIOS && hasCIT ? "检测到 iCloud 备份（配置与数据），是否导入？" : "检测到 iCloud 备份，是否导入？"
						self.showImportPrompt = true
						NotificationCenter.default.post(name: Notification.Name("iCloudImportPromptAvailable"), object: nil)
					}
					return
				}
			}
			
			// 🚀 优化：异步下载，使用异步等待替代阻塞sleep
			Task {
				let fm = FileManager.default
				if let docs = self.documentsURL {
					let iosURL = docs.appendingPathComponent("ios_data.json")
					let citURL = docs.appendingPathComponent("citation_data.json")
					if fm.fileExists(atPath: iosURL.path) {
						try? fm.startDownloadingUbiquitousItem(at: iosURL)
						print("🔄 [FirstLaunch Import] startDownloading ios_data.json …")
					}
					if fm.fileExists(atPath: citURL.path) {
						try? fm.startDownloadingUbiquitousItem(at: citURL)
						print("🔄 [FirstLaunch Import] startDownloading citation_data.json …")
					}
					// 🚀 优化：使用 Task.sleep 替代阻塞的 Thread.sleep
					try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
				}
				self.importFromiCloud { result in
					switch result {
					case .success(let info):
						print("✅ [FirstLaunch Import] Imported: scholars=\(info.importedScholars) history=\(info.importedHistory) config=\(info.configImported)")
						UserDefaults.standard.set(true, forKey: flagKey)
					case .failure(let err):
						print("⚠️ [FirstLaunch Import] No data imported: \(err.localizedDescription)")
					}
				}
			}
		}
		#endif
	}

	// 用户点击“导入”
	func confirmImportFromPrompt() {
		let flagKey = "FirstLaunchImportDone"
		showingErrorAlert = false
		showImportPrompt = false
		DispatchQueue.global(qos: .userInitiated).async {
			let fm = FileManager.default
			if let docs = self.documentsURL {
				let iosURL = docs.appendingPathComponent("ios_data.json")
				let citURL = docs.appendingPathComponent("citation_data.json")
				if fm.fileExists(atPath: iosURL.path) { try? fm.startDownloadingUbiquitousItem(at: iosURL) }
				if fm.fileExists(atPath: citURL.path) { try? fm.startDownloadingUbiquitousItem(at: citURL) }
				Thread.sleep(forTimeInterval: 1.0)
			}
			self.importFromiCloud { result in
				if case .success = result { UserDefaults.standard.set(true, forKey: flagKey) }
			}
		}
	}

	// 用户点击“暂不导入”
	func declineImportFromPrompt() {
		let flagKey = "FirstLaunchImportDone"
		showImportPrompt = false
		UserDefaults.standard.set(true, forKey: flagKey)
	}

	// MARK: - CloudKit Long-term Sync

	/// 使用 CloudKit 保存当前导出数据（长期同步）
	func exportUsingCloudKit(completion: @escaping (Result<Void, Error>) -> Void) {
		do {
			let payload = try makeExportJSONData()
			let unified = try makeAppDataJSON(exportPayload: payload)
			CloudKitSyncService.shared.saveJSONData(unified) { result in
				completion(result.map { _ in () })
			}
		} catch {
			completion(.failure(error))
		}
	}

	/// 使用 CloudKit 获取最新数据并导入（长期同步）
	func importUsingCloudKit(completion: @escaping (Result<ImportResult, Error>) -> Void) {
		CloudKitSyncService.shared.fetchJSONData { result in
			switch result {
			case .success(let data):
				do {
					let importResult = try self.importFromUnifiedData(data)
					DispatchQueue.main.async {
						// 导入后刷新 Widget
						DataManager.shared.refreshWidgets()
						completion(.success(importResult))
					}
				} catch {
					completion(.failure(error))
				}
			case .failure(let error):
				completion(.failure(error))
			}
		}
	}

	/// 从 CloudKit 拉取最新快照并合并到本地（“向下同步”）。
	/// This is the missing half of sync: `exportUsingCloudKit` pushed data UP to
	/// CloudKit, but `importUsingCloudKit` was never called anywhere — so a second
	/// device (or this device after relaunch) never pulled changes made elsewhere,
	/// which is exactly the "data not syncing" report. The merge is additive
	/// (`addScholar` upserts, `saveHistoryIfChanged` dedups), so pulling on
	/// launch/foreground can never delete local data. Gated only on iCloud
	/// availability, mirroring `importConfigOnFirstLaunch`.
	func syncDownFromCloudKit(reason: String = "") {
		#if targetEnvironment(simulator)
		return
		#else
		guard isiCloudAvailable else {
			print("ℹ️ [CloudKit SyncDown] iCloud not available, skip")
			return
		}
		importUsingCloudKit { result in
			switch result {
			case .success(let info):
				print("✅ [CloudKit SyncDown\(reason.isEmpty ? "" : ":\(reason)")] merged scholars=\(info.importedScholars) history=\(info.importedHistory)")
			case .failure(let err):
				print("ℹ️ [CloudKit SyncDown\(reason.isEmpty ? "" : ":\(reason)")] no remote data/failed: \(err.localizedDescription)")
			}
		}
		#endif
	}

	/// 立即同步：将本地数据保存到 CloudKit，并刷新状态
	func performImmediateSync() {
		DispatchQueue.main.async {
			self.isExporting = true
			self.syncStatus = LocalizationManager.shared.localized("exporting_to_icloud")
			let df = DateFormatter(); df.locale = .current; df.timeZone = .current; df.dateStyle = .medium; df.timeStyle = .medium
			print("🚀 [CloudKit Sync] performImmediateSync started at: \(df.string(from: Date()))")
		}
		exportUsingCloudKit { result in
			DispatchQueue.main.async {
				switch result {
				case .success:
					self.lastSyncDate = Date()
					let formatter = DateFormatter()
					formatter.locale = Locale(identifier: "en_US_POSIX")
					formatter.dateFormat = "yyyy-MM-dd HH:mm"
					let ts = formatter.string(from: self.lastSyncDate ?? Date())
					self.syncStatus = "\(LocalizationManager.shared.localized("last_sync")): \(ts)"
					self.isExporting = false
					print("✅ [CloudKit Sync] performImmediateSync success, lastSyncDate=\(self.lastSyncDate?.description ?? "nil")")
					// 可见文件镜像：写入容器 Documents 下（Files 中显示为本应用的 iCloud 文件夹）
					let group = DispatchGroup()
					if let docs = self.documentsURL {
						let mirrorURL = docs.appendingPathComponent(self.longTermSyncFileName)
						group.enter()
						DispatchQueue.global(qos: .utility).async {
							do {
								let exportPayload = try self.makeExportJSONData()
								let jsonData = try self.makeAppDataJSON(exportPayload: exportPayload)
								let fm = FileManager.default
								try? fm.createDirectory(at: docs, withIntermediateDirectories: true)
								try jsonData.write(to: mirrorURL, options: [.atomic])
								print("✅ [iCloud Container Mirror] Wrote long-term file: \(mirrorURL.path)")
								if let attrs = try? fm.attributesOfItem(atPath: mirrorURL.path), let m = attrs[.modificationDate] as? Date {
									let df = DateFormatter(); df.locale = .current; df.timeZone = .current; df.dateStyle = .medium; df.timeStyle = .medium
									print("🕒 [Mirror] mtime: \(df.string(from: m))")
								}
							} catch {
								print("⚠️ [iCloud Container Mirror] Failed to write mirror: \(error)")
							}
							group.leave()
						}
					}

					// 同步更新 CloudDocs 下的 ios_data.json（确保 Files 应用可见文件被更新）
					group.enter()
					DispatchQueue.global(qos: .utility).async {
						do {
							try self.createiCloudFolder()
							try self.exportAppConfig()
							print("✅ [iCloud Drive] ios_data.json updated during immediate sync")
						} catch {
							print("⚠️ [iCloud Drive] Failed to update ios_data.json during immediate sync: \(error)")
						}
						group.leave()
					}
					// 在镜像文件写入完成后刷新状态，确保上次同步时间从最新文件时间读取
					group.notify(queue: .main) {
						print("🔁 [CloudKit Sync] checkSyncStatus after mirror writes …")
						self.checkSyncStatus()
					}
				case .failure(let error):
					self.syncStatus = LocalizationManager.shared.localized("export_failed") + ": " + error.localizedDescription
					self.isExporting = false
					print("❌ [CloudKit Sync] performImmediateSync failed: \(error.localizedDescription)")
				}
			}
		}
	}

	// MARK: - CloudDocs Folder Bookmarking

	/// 返回 iCloud Drive 根目录（com~apple~CloudDocs）URL
	func cloudDocsRootURL() -> URL? {
		#if targetEnvironment(simulator)
		return nil
		#else
		guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
		return container.deletingLastPathComponent().appendingPathComponent("com~apple~CloudDocs", isDirectory: true)
		#endif
	}

	/// 判断URL是否位于 iCloud Drive 根（com~apple~CloudDocs）之下
	private func isInCloudDocs(_ url: URL) -> Bool {
		let p = url.path
		return p.contains("/Mobile Documents/com~apple~CloudDocs/") || p.hasSuffix("/Mobile Documents/com~apple~CloudDocs")
	}

	/// 保存用户在 CloudDocs 下选择的目录为安全作用域书签
	func savePreferredDriveDirectoryBookmark(from directoryURL: URL) {
		do {
			// 只接受 CloudDocs 根下的目录，避免误选应用容器的 Documents
			guard isInCloudDocs(directoryURL) else {
				print("⚠️ [CloudDocs Bookmark] Rejected non-CloudDocs URL: \(directoryURL.path)")
				return
			}
			let bookmarkData = try directoryURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
			UserDefaults.standard.set(bookmarkData, forKey: driveBookmarkKey)
			UserDefaults.standard.synchronize()
			DispatchQueue.main.async { self.hasBookmarkedDriveDirectory = true }
			print("✅ [CloudDocs Bookmark] Saved bookmark for: \(directoryURL.path)")
		} catch {
			print("❌ [CloudDocs Bookmark] Save failed: \(error)")
		}
	}
	
	/// 在iCloud Drive中创建并显示应用文件夹
	func createiCloudDriveFolder(completion: @escaping (Result<Void, iCloudError>) -> Void) {
		print("🚀 [iCloud Drive] \("debug_create_icloud_folder".localized)")
		
		guard isiCloudAvailable else {
			print("❌ [iCloud Drive] \("icloud_not_available".localized)")
			DispatchQueue.main.async {
				completion(.failure(.iCloudNotAvailable))
			}
			return
		}
		
		let workItem = DispatchWorkItem {
			do {
				print("🔍 [iCloud Drive] \("debug_setup_icloud_visibility".localized)")
				
				// 确保Documents文件夹存在
				guard let documentsURL = self.documentsURL else {
					print("❌ [iCloud Drive] 无法获取Documents URL")
					DispatchQueue.main.async {
						completion(.failure(.invalidURL))
					}
					return
				}
				
				print("🔍 [iCloud Drive] Documents路径: \(documentsURL.path)")
				
				let fileManager = FileManager.default
				
				// 确保Documents文件夹存在
				if !fileManager.fileExists(atPath: documentsURL.path) {
					print("🔧 [iCloud Drive] 正在创建Documents文件夹...")
					try fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true, attributes: nil)
					print("✅ [iCloud Drive] 创建了Documents文件夹: \(documentsURL.path)")
				} else {
					print("ℹ️ [iCloud Drive] Documents文件夹已存在: \(documentsURL.path)")
				}
				
				// 创建占位 .keep 文件（隐藏），并确保仅生成 ios_config.json 作为配置文件
				let keepURL = documentsURL.appendingPathComponent(".keep")
				if !fileManager.fileExists(atPath: keepURL.path) {
					print("🔧 [iCloud Drive] 正在创建文件: .keep")
					try "keep".write(to: keepURL, atomically: true, encoding: .utf8)
					print("✅ [iCloud Drive] 创建了文件: .keep")
				} else {
					print("ℹ️ [iCloud Drive] 文件已存在: .keep")
				}
				
				// 确保核心数据文件存在
				if let citationURL = self.citationDataURL {
					if !fileManager.fileExists(atPath: citationURL.path) {
						print("🔧 [iCloud Drive] 创建初始citation_data.json...")
						let initialData = [
							"scholars": [],
							"lastUpdated": ISO8601DateFormatter().string(from: Date()),
							"version": "1.0"
						] as [String : Any]
						let jsonData = try JSONSerialization.data(withJSONObject: initialData, options: .prettyPrinted)
						try jsonData.write(to: citationURL)
						print("✅ [iCloud Drive] 创建了初始数据文件")
					}
				}
				
				if let configURL = self.configFileURL {
					if !fileManager.fileExists(atPath: configURL.path) {
						print("🔧 [iCloud Drive] 创建初始app_config.json...")
						let initialConfig = [
							"version": "1.0",
							"settings": [:],
							"lastModified": ISO8601DateFormatter().string(from: Date())
						] as [String : Any]
						let jsonData = try JSONSerialization.data(withJSONObject: initialConfig, options: .prettyPrinted)
						try jsonData.write(to: configURL)
						print("✅ [iCloud Drive] 创建了初始配置文件")
					}
				}
				
				// Documents文件夹已经创建，无需额外设置属性
				print("✅ [iCloud Drive] Documents文件夹已准备就绪")
				
				// 强制同步到iCloud Drive
				print("🔧 [iCloud Drive] 开始强制同步到iCloud...")
				
				if let containerURL = self.iCloudContainerURL {
					// 同步容器
					do {
						try fileManager.startDownloadingUbiquitousItem(at: containerURL)
						print("✅ [iCloud Drive] 启动了iCloud容器同步")
					} catch {
						print("⚠️ [iCloud Drive] 容器同步失败: \(error)")
					}
					
					// 同步Documents文件夹
					do {
						try fileManager.startDownloadingUbiquitousItem(at: documentsURL)
						print("✅ [iCloud Drive] 启动了Documents文件夹同步")
					} catch {
						print("⚠️ [iCloud Drive] Documents同步失败: \(error)")
					}
					
					// 同步 .keep 和 ios_data.json
					let filesToSync = [".keep", "ios_data.json"]
					for fileName in filesToSync {
						let fileURL = documentsURL.appendingPathComponent(fileName)
						if fileManager.fileExists(atPath: fileURL.path) {
							do {
								try fileManager.startDownloadingUbiquitousItem(at: fileURL)
								print("✅ [iCloud Drive] 启动了文件同步: \(fileName)")
							} catch {
								print("⚠️ [iCloud Drive] 文件同步失败 \(fileName): \(error)")
							}
						}
					}
					
					// 同步数据文件
					if let citationURL = self.citationDataURL {
						do {
							try fileManager.startDownloadingUbiquitousItem(at: citationURL)
							print("✅ [iCloud Drive] 启动了引用数据同步")
						} catch {
							print("⚠️ [iCloud Drive] 引用数据同步失败: \(error)")
						}
					}
					
					if let configURL = self.configFileURL {
						do {
							try fileManager.startDownloadingUbiquitousItem(at: configURL)
							print("✅ [iCloud Drive] 启动了配置文件同步")
						} catch {
							print("⚠️ [iCloud Drive] 配置文件同步失败: \(error)")
						}
					}
				}
				
				// 等待同步开始
				Thread.sleep(forTimeInterval: 2.0)
				
				print("🎉 [iCloud Drive] CiteTrack文件夹设置完成！")
				print("📱 [iCloud Drive] 请打开\"文件\"应用 → iCloud Drive，查看带CiteTrack图标的文件夹")
				print("📝 [iCloud Drive] 如果文件夹未立即显示，请等待几分钟让iCloud同步完成")
				
				DispatchQueue.main.async {
					completion(.success(()))
				}
				
			} catch {
				print("❌ [iCloud Drive] 创建文件夹失败: \(error)")
				print("❌ [iCloud Drive] 错误详情: \(error.localizedDescription)")
				DispatchQueue.main.async {
					completion(.failure(.exportFailed(error.localizedDescription)))
				}
			}
		}
		
		DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
	}

	/// 解析已保存的书签，返回可访问的目录 URL
	func resolvePreferredDriveDirectory() -> URL? {
		guard let data = UserDefaults.standard.data(forKey: driveBookmarkKey) else { return nil }
		var stale = false
		do {
			let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
			if stale {
				print("⚠️ [CloudDocs Bookmark] Bookmark is stale, need reselect")
				return nil
			}
			print("✅ [CloudDocs Bookmark] Resolved: \(url.path)")
			return url
		} catch {
			print("❌ [CloudDocs Bookmark] Resolve failed: \(error)")
			return nil
		}
	}

	/// 清除已保存的书签
	func clearPreferredDriveDirectoryBookmark() {
		UserDefaults.standard.removeObject(forKey: driveBookmarkKey)
		UserDefaults.standard.synchronize()
		DispatchQueue.main.async { self.hasBookmarkedDriveDirectory = false }
		print("🧹 [CloudDocs Bookmark] Cleared bookmark")
	}

	// 在应用启动时尝试创建容器和占位文件，帮助系统显示应用图标文件夹
	func bootstrapContainerIfPossible() {
        NSLog("🚀 [iCloud Debug] bootstrapContainerIfPossible() called")
		#if targetEnvironment(simulator)
		print("ℹ️ [iCloud Debug] Simulator environment - skip real iCloud bootstrap")
		return
		#else
		// 检查用户是否启用了iCloud Drive文件夹功能
		let settingsManager = SettingsManager.shared
		guard settingsManager.iCloudDriveFolderEnabled else {
			print("ℹ️ [iCloud Debug] iCloud Drive folder disabled by user setting")
			return
		}
		
		print("🚀 [iCloud Debug] Bootstrap iCloud container if possible ...")
		guard isiCloudAvailable else {
			print("❌ [iCloud Debug] iCloud not available at bootstrap")
			return
		}
		guard let docs = documentsURL else {
			print("❌ [iCloud Debug] documentsURL is nil during bootstrap")
			return
		}
		let fm = FileManager.default
		// 创建 Documents（若不存在）
		if !fm.fileExists(atPath: docs.path) {
			do {
				try fm.createDirectory(at: docs, withIntermediateDirectories: true, attributes: nil)
				print("✅ [iCloud Debug] Created iCloud Documents at: \(docs.path)")
			} catch {
				print("❌ [iCloud Debug] Failed to create Documents: \(error)")
			}
		}
		// 写入占位文件
		let keep = docs.appendingPathComponent(".keep")
		if !fm.fileExists(atPath: keep.path) {
			do {
				try Data("keep".utf8).write(to: keep)
				print("✅ [iCloud Debug] Wrote placeholder at: \(keep.path)")
			} catch {
				print("❌ [iCloud Debug] Failed writing placeholder: \(error)")
			}
		}
		// 写入一个数据文件 ios_data.json，确保 Files 能展示该文件夹
		let bootstrapConfig = docs.appendingPathComponent("ios_data.json")
		if !fm.fileExists(atPath: bootstrapConfig.path) {
			do {
				let initialConfig: [String: Any] = makeCurrentAppData()
				let data = try JSONSerialization.data(withJSONObject: initialConfig, options: .prettyPrinted)
				try data.write(to: bootstrapConfig)
				print("✅ [iCloud Debug] Wrote ios_data.json at: \(bootstrapConfig.path)")
			} catch {
				print("❌ [iCloud Debug] Failed writing ios_data.json: \(error)")
			}
		}
		#endif
	}

	// MARK: - Deep Diagnostics

	/// 打印容器与目录内文件的详细 iCloud 资源状态，帮助定位 Files 不显示的问题
	func runDeepDiagnostics() {
		print("🧪 [iCloud Diag] ===== BEGIN =====")
		// Token 与 Bundle 信息
		if let token = FileManager.default.ubiquityIdentityToken {
			print("🧪 [iCloud Diag] ubiquityIdentityToken: \(token)")
		} else {
			print("🧪 [iCloud Diag] ubiquityIdentityToken: nil")
		}
		print("🧪 [iCloud Diag] bundleIdentifier: \(Bundle.main.bundleIdentifier ?? "nil")")

		// 容器与 Documents URL
		if let container = iCloudContainerURL {
			print("🧪 [iCloud Diag] containerURL: \(container.path)")
		} else {
			print("🧪 [iCloud Diag] containerURL: nil")
		}
		guard let docs = documentsURL else {
			print("🧪 [iCloud Diag] documentsURL: nil")
			print("🧪 [iCloud Diag] ===== END (no docs) =====")
			return
		}
		print("🧪 [iCloud Diag] documentsURL: \(docs.path)")

		// 列出 Documents 下的文件并打印资源状态
		let fm = FileManager.default
		do {
			let items = try fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: [
				.isUbiquitousItemKey,
				.ubiquitousItemIsUploadingKey,
				.ubiquitousItemIsDownloadingKey,
				.ubiquitousItemHasUnresolvedConflictsKey,
				.isHiddenKey,
				.isExcludedFromBackupKey
			], options: [.skipsHiddenFiles])

			print("🧪 [iCloud Diag] documents items count: \(items.count)")
			for url in items {
				do {
					let values = try url.resourceValues(forKeys: [
						.isUbiquitousItemKey,
						.ubiquitousItemIsUploadingKey,
						.ubiquitousItemIsDownloadingKey,
						.ubiquitousItemHasUnresolvedConflictsKey,
						.isHiddenKey,
						.isExcludedFromBackupKey
					])
					let name = url.lastPathComponent
					let ubi = values.isUbiquitousItem ?? false
					let up = values.ubiquitousItemIsUploading ?? false
					let down = values.ubiquitousItemIsDownloading ?? false
					let conf = values.ubiquitousItemHasUnresolvedConflicts ?? false
					let hidden = values.isHidden ?? false
					let excluded = values.isExcludedFromBackup ?? false
					print("🧪 [iCloud Diag] • \(name) | ubi=\(ubi) up=\(up) down=\(down) conflicts=\(conf) hidden=\(hidden) excluded=\(excluded)")
				} catch {
					print("🧪 [iCloud Diag] • \(url.lastPathComponent) | failed to read resource values: \(error)")
				}
			}
		} catch {
			print("🧪 [iCloud Diag] list documents failed: \(error)")
		}

		// 启动一次 Metadata 查询，检查系统视角下的可见文件
		startMetadataSnapshot()
		print("🧪 [iCloud Diag] ===== END (metadata will print async) =====")
	}

	private var metadataQuery: NSMetadataQuery?

	private func startMetadataSnapshot() {
		let query = NSMetadataQuery()
		metadataQuery = query
		NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
			guard let q = self?.metadataQuery else { return }
			q.disableUpdates()
			print("🧪 [iCloud Diag][MD] results: \(q.resultCount)")
			for case let item as NSMetadataItem in q.results {
				let name = item.value(forAttribute: NSMetadataItemFSNameKey) as? String ?? "<nil>"
				let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL
				let size = item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber
				let cdate = item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date
				let mdate = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date
				print("🧪 [iCloud Diag][MD] • name=\(name) url=\(url?.path ?? "nil") size=\(size?.intValue ?? -1) c=\(cdate?.description ?? "nil") m=\(mdate?.description ?? "nil")")
			}
			q.stop()
			NotificationCenter.default.removeObserver(self as Any, name: .NSMetadataQueryDidFinishGathering, object: q)
		}
		query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
		query.predicate = NSPredicate(value: true)
		print("🧪 [iCloud Diag][MD] start query in UbiquitousDocumentsScope …")
		query.start()
	}
	
	// MARK: - iCloud Detection
	
	/// Check if iCloud Drive is available
	var isiCloudAvailable: Bool {
		let ubiquityToken = FileManager.default.ubiquityIdentityToken
		print("🔍 [iCloud Debug] iCloud token: \(ubiquityToken != nil ? "EXISTS" : "NOT FOUND")")
		return ubiquityToken != nil
	}
	
	// MARK: - URL Properties
	
	/// 按照指南标准实现：获取iCloud容器URL
	func getiCloudContainerURL() -> URL? {
		// 使用在Xcode中配置的容器标识符
		// 如果传nil，则会获取第一个在entitlements中声明的容器
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.citetrack.CiteTrack") else {
			print("无法获取iCloud容器URL。请检查：")
			print("- 用户是否已登录iCloud？")
			print("- 应用的iCloud同步是否已在系统设置中启用？")
			print("- 项目的Entitlements配置是否正确？")
			return nil
		}
		print("✅ [iCloud] 成功获取iCloud容器URL: \(containerURL.path)")
		return containerURL
	}
	
	/// 按照指南标准实现：获取公共Documents URL
	func getPublicDocumentsURL() -> URL? {
		// 用户在iCloud Drive中看到的文件夹实际对应容器内的"Documents"子目录
		return getiCloudContainerURL()?.appendingPathComponent("Documents")
	}
	
	/// 按照指南标准实现：关键激活步骤 - 创建初始文件确保文件夹可见
	func createInitialFileForVisibility() {
		guard let documentsURL = getPublicDocumentsURL() else {
			print("❌ [iCloud Activation] 无法获取Documents URL")
			return
		}

		let fileURL = documentsURL.appendingPathComponent("ios_data.json")
		if !FileManager.default.fileExists(atPath: fileURL.path) {
			do {
				let config = makeCurrentAppData()
				let data = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
				try data.write(to: fileURL)
				print("✅ [iCloud Activation] 初始 ios_data.json 创建成功：\(fileURL.path)")
				print("📝 [iCloud Activation] 这确保了应用文件夹在iCloud Drive中可见")
			} catch {
				print("❌ [iCloud Activation] 创建 ios_data.json 失败: \(error)")
			}
		} else {
			print("ℹ️ [iCloud Activation] ios_data.json 已存在：\(fileURL.path)")
		}
	}
	
	/// 手动创建iCloud Drive文件夹（用户主动触发）
	func createiCloudDriveFolder() -> Bool {
		guard isiCloudAvailable else {
			print("❌ [iCloud Drive] iCloud不可用")
			return false
		}
		
		guard let documentsURL = getPublicDocumentsURL() else {
			print("❌ [iCloud Drive] 无法获取Documents URL")
			return false
		}
		
		let fm = FileManager.default
		
		// 创建Documents目录（如果不存在）
		if !fm.fileExists(atPath: documentsURL.path) {
			do {
				try fm.createDirectory(at: documentsURL, withIntermediateDirectories: true, attributes: nil)
				print("✅ [iCloud Drive] 创建Documents目录：\(documentsURL.path)")
			} catch {
				print("❌ [iCloud Drive] 创建Documents目录失败: \(error)")
				return false
			}
		}
		
		// 创建 ios_data.json（包含配置与刷新数据）
		let configJSON = documentsURL.appendingPathComponent("ios_data.json")
		if !fm.fileExists(atPath: configJSON.path) {
			do {
				let config = makeCurrentAppData()
				let data = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
				try data.write(to: configJSON)
				print("✅ [iCloud Drive] 创建 ios_data.json：\(configJSON.path)")
			} catch {
				print("❌ [iCloud Drive] 创建 ios_data.json 失败: \(error)")
				return false
			}
		}
		
		// 创建应用标识文件，帮助系统识别文件夹
		let appInfoFile = documentsURL.appendingPathComponent(".citetrack_app_info")
		if !fm.fileExists(atPath: appInfoFile.path) {
			do {
				let appInfo = [
					"app_name": "CiteTrack",
                    "bundle_id": "com.citetrack.CiteTrack",
					"version": "1.0.1",
					"created_at": ISO8601DateFormatter().string(from: Date())
				]
				let jsonData = try JSONSerialization.data(withJSONObject: appInfo, options: .prettyPrinted)
				try jsonData.write(to: appInfoFile)
				print("✅ [iCloud Drive] 创建应用标识文件：\(appInfoFile.path)")
			} catch {
				print("❌ [iCloud Drive] 创建应用标识文件失败: \(error)")
			}
		}
		
		// 强制同步到iCloud
		do {
			try fm.setUbiquitous(true, itemAt: documentsURL, destinationURL: documentsURL)
			print("✅ [iCloud Drive] 强制同步到iCloud")
		} catch {
			print("⚠️ [iCloud Drive] 强制同步失败: \(error)")
		}
		
		print("✅ [iCloud Drive] iCloud Drive文件夹创建成功！")
		
		// 延迟刷新文件夹状态，确保图标正确显示
		DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
			self.refreshFolderIcon()
		}
		
		return true
	}
	
	/// 刷新文件夹图标显示
	func refreshFolderIcon() {
		guard let documentsURL = getPublicDocumentsURL() else { return }
		
		let fm = FileManager.default
		
		// 创建一个临时文件来触发系统重新评估文件夹
		let tempFile = documentsURL.appendingPathComponent(".refresh_\(Date().timeIntervalSince1970)")
		do {
			try "refresh".write(to: tempFile, atomically: true, encoding: .utf8)
			// 立即删除临时文件
			try fm.removeItem(at: tempFile)
			print("✅ [iCloud Drive] 刷新文件夹图标")
		} catch {
			print("⚠️ [iCloud Drive] 刷新文件夹图标失败: \(error)")
		}
	}
	
	/// Get iCloud container URL - 按照指南的标准实现
	private var iCloudContainerURL: URL? {
		return getiCloudContainerURL()
	}
	
	/// Get Documents folder URL in iCloud
	private var documentsURL: URL? {
		guard let containerURL = iCloudContainerURL else {
			print("❌ [iCloud Debug] No iCloud container available")
			return nil
		}
		
		let documentsURL = containerURL.appendingPathComponent("Documents")
		print("🔍 [iCloud Debug] Documents URL: \(documentsURL.path)")
		return documentsURL
	}

    /// 导入/导出的首选目录（iOS 上使用容器 Documents，可在“文件”App 中显示为应用的 iCloud 文件夹）
    func preferredExportDirectory() -> URL? {
        return documentsURL
    }

	/// 用户可见的 iCloud Drive 根（com~apple~CloudDocs）下的推荐目录（CiteTrack）
	/// 仅用于作为 UIDocumentPicker 的初始目录，避免直接跨容器写入
	func preferredUserDriveDirectory() -> URL? {
		#if targetEnvironment(simulator)
		return nil
		#else
		// 取默认容器，然后回退到其父目录，拼接 com~apple~CloudDocs
		guard let container = iCloudContainerURL else { return nil }
		let cloudRoot = container.deletingLastPathComponent().appendingPathComponent("com~apple~CloudDocs", isDirectory: true)
		return cloudRoot.appendingPathComponent("CiteTrack", isDirectory: true)
		#endif
	}

	/// 构造容器 Documents 下数据文件 URL
	private func cloudDocsDataFileURL() -> URL? {
		return documentsURL?.appendingPathComponent(dataFileName)
	}

	/// 构造容器 Documents 下长期同步文件 URL（用于可见文件镜像）
	private func cloudDocsLongTermFileURL() -> URL? {
		return documentsURL?.appendingPathComponent(longTermSyncFileName)
	}
	
	/// 获取当前数据根目录：固定为容器 Documents
	private var citeTrackFolderURL: URL? {
		return documentsURL
	}
	
	/// Get citation data file URL
	private var citationDataURL: URL? {
		guard let folderURL = citeTrackFolderURL else {
			print("❌ [iCloud Debug] No CiteTrack folder available")
			return nil
		}
		
		let fileURL = folderURL.appendingPathComponent(dataFileName)
		print("🔍 [iCloud Debug] Citation data URL: \(fileURL.path)")
		return fileURL
	}
	
	/// Get config file URL
	private var configFileURL: URL? {
		guard let folderURL = citeTrackFolderURL else {
			print("❌ [iCloud Debug] No CiteTrack folder available")
			return nil
		}
		
		let fileURL = folderURL.appendingPathComponent(configFileName)
		print("🔍 [iCloud Debug] Config file URL: \(fileURL.path)")
		return fileURL
	}
	
	// MARK: - Import Functions
	
	/// Import data from iCloud
	func importFromiCloud(completion: @escaping (Result<ImportResult, iCloudError>) -> Void) {
		print("🚀 [iCloud Import] Starting import...")
		
		guard isiCloudAvailable else {
			print("❌ [iCloud Import] iCloud not available")
			completion(.failure(.iCloudNotAvailable))
			return
		}
		
		DispatchQueue.main.async {
			self.isImporting = true
			self.syncStatus = LocalizationManager.shared.localized("importing_from_icloud")
		}
		
		DispatchQueue.global(qos: .userInitiated).async {
			do {
				let result = try self.performImport()
				
				DispatchQueue.main.async {
					self.isImporting = false
					self.lastSyncDate = Date()
					self.syncStatus = LocalizationManager.shared.localized("import_completed")
					// 导入成功后，刷新小组件时间线，确保新学者出现在Widget
					DataManager.shared.refreshWidgets()
					completion(.success(result))
				}
			} catch {
				DispatchQueue.main.async {
					self.isImporting = false
					self.syncStatus = LocalizationManager.shared.localized("import_failed")
					if let iCloudError = error as? iCloudError {
						completion(.failure(iCloudError))
					} else {
						completion(.failure(.importFailed(error.localizedDescription)))
					}
				}
			}
		}
	}
	
	/// Perform the actual import
	private func performImport() throws -> ImportResult {
		print("🔍 [iCloud Import] Checking citation data URL...")
		
		let fileManager = FileManager.default
		var importedHistory = 0
		var importedScholars = 0
		var result: ImportResult = ImportResult(importedScholars: 0, importedHistory: 0, configImported: false, importDate: Date())
		
		if let citationURL = citationDataURL {
			print("🔍 [iCloud Import] citation_data.json URL: \(citationURL.path)")
			if fileManager.fileExists(atPath: citationURL.path) {
				print("✅ [iCloud Import] Found citation data file")
				let citationData = try Data(contentsOf: citationURL)
				result = try importFromJSONData(citationData)
				// 使用安全的加法，防止溢出
				importedHistory = min(importedHistory + result.importedHistory, Int.max - 1)
				importedScholars = min(importedScholars + result.importedScholars, Int.max - 1)
			} else {
				print("ℹ️ [iCloud Import] Citation data not found at path")
			}
		} else {
			print("⚠️ [iCloud Import] citationDataURL is nil")
		}
		
		// 尝试导入应用数据（设置 + 刷新数据）
		var configImported = false
		if let configURL = configFileURL {
			print("🔍 [iCloud Import] ios_data.json URL: \(configURL.path)")
			if fileManager.fileExists(atPath: configURL.path) {
				print("🔍 [iCloud Import] Found app data file, importing...")
				do {
					let configData = try Data(contentsOf: configURL)
					let config = try JSONSerialization.jsonObject(with: configData) as? [String: Any]
					let keys = config?.keys.map { $0 } ?? []
					print("📄 [iCloud Import] ios_data.json keys: \(keys)")
                    if let settings = config?["settings"] as? [String: Any] {
                        DispatchQueue.main.async {
                            if let updateInterval = settings["updateInterval"] as? TimeInterval { SettingsManager.shared.updateInterval = updateInterval }
                            if let notificationsEnabled = settings["notificationsEnabled"] as? Bool { SettingsManager.shared.notificationsEnabled = notificationsEnabled }
                            if let language = settings["language"] as? String { SettingsManager.shared.language = language }
                            if let themeRawValue = settings["theme"] as? String, let theme = AppTheme(rawValue: themeRawValue) { SettingsManager.shared.theme = theme }
                        }
                        configImported = true
                        print("✅ [iCloud Import] Settings imported successfully")
                    } else {
						print("ℹ️ [iCloud Import] settings missing in ios_data.json")
					}
					// 合并首次安装日期：取更早的值作为 FirstInstallDate
					if let firstInstallString = config?["firstInstallDate"] as? String,
					   let incoming = ISO8601DateFormatter().date(from: firstInstallString) {
                        let key = "FirstInstallDate"
                        let cal = Calendar.current
                        let local = (UserDefaults.standard.object(forKey: key) as? Date) ?? cal.startOfDay(for: Date())
                        let earliest = min(cal.startOfDay(for: local), cal.startOfDay(for: incoming))
                        // 同步写入两个键：FirstInstallDate 与 AppInstallDate
                        UserDefaults.standard.set(earliest, forKey: key)
                        UserDefaults.standard.set(earliest, forKey: "AppInstallDate")
                        if let ag = UserDefaults(suiteName: appGroupIdentifier) {
                            ag.set(earliest, forKey: key)
                            ag.set(earliest, forKey: "AppInstallDate")
                            ag.synchronize()
                        }
						print("✅ [iCloud Import] FirstInstallDate merged: \(earliest)")
					} else {
						print("ℹ️ [iCloud Import] firstInstallDate missing in ios_data.json")
					}
					if let refreshDict = config?["refreshData"] as? [String: Any] {
						let map = refreshDict["data"] as? [String: Int] ?? [:]
						UserBehaviorManager.shared.importRefreshData(map)
						let formatter = DateFormatter()
						formatter.dateFormat = "yyyy-MM-dd"
						if let oldestKey = map.keys.sorted().first, let oldest = formatter.date(from: oldestKey) {
							let cal = Calendar.current
							let start = cal.startOfDay(for: oldest)
                            // 同步写入两个键：FirstInstallDate 与 AppInstallDate
                            UserDefaults.standard.set(start, forKey: "FirstInstallDate")
                            UserDefaults.standard.set(start, forKey: "AppInstallDate")
                            if let ag = UserDefaults(suiteName: appGroupIdentifier) {
                                ag.set(start, forKey: "FirstInstallDate")
                                ag.set(start, forKey: "AppInstallDate")
                                ag.synchronize()
                            }
							print("📆 [iCloud Import] Set FirstInstallDate to earliest refresh date: \(start)")
						}
						print("✅ [iCloud Import] Refresh data imported and merged: days=\(map.count)")
					} else {
						print("⚠️ [iCloud Import] refreshData missing in ios_data.json")
					}
				} catch {
					print("⚠️ [iCloud Import] Failed to import app data: \(error)")
				}
			} else {
				print("ℹ️ [iCloud Import] No ios_data.json found at path")
			}
		} else {
			print("⚠️ [iCloud Import] configFileURL is nil")
		}
		
		// 额外兜底：如果存在统一备份文件（CiteTrack_sync.json / Citetrack_sync.json），也尝试导入
		if let docs = documentsURL {
			let candidates = ["CiteTrack_sync.json", "Citetrack_sync.json"]
			for name in candidates {
				let unifiedURL = docs.appendingPathComponent(name)
				if fileManager.fileExists(atPath: unifiedURL.path) {
					print("🔍 [iCloud Import] Found unified backup file: \(name)")
					do {
						let data = try Data(contentsOf: unifiedURL)
						// 在主线程导入，避免发布警告
						var res: ImportResult!
						DispatchQueue.main.sync { res = try? self.importFromUnifiedData(data) }
						if let res = res {
							// 使用安全的加法，防止溢出
							importedScholars = min(importedScholars + res.importedScholars, Int.max - 1)
							importedHistory = min(importedHistory + res.importedHistory, Int.max - 1)
							print("📥 [iCloud Import] Unified file imported: scholars=\(res.importedScholars), history=\(res.importedHistory)")
						}
						break
					} catch {
						print("⚠️ [iCloud Import] Failed to import unified file: \(error)")
					}
				}
			}
		}

		print("✅ [iCloud Import] Import completed: scholars=\(importedScholars), history=\(importedHistory), configImported=\(configImported)")
		// 通知界面刷新（热力图等）
		DispatchQueue.main.async {
			NotificationCenter.default.post(name: .userDataChanged, object: nil)
		}
		
		return ImportResult(
			importedScholars: importedScholars,
			importedHistory: importedHistory,
			configImported: configImported || result.configImported,
			importDate: Date()
		)
	}
	
	// MARK: - Export Functions
	
	/// Export data to iCloud
	func exportToiCloud(completion: @escaping (Result<Void, iCloudError>) -> Void) {
		print("🚀 [iCloud Export] Starting export...")
		
		guard isiCloudAvailable else {
			print("❌ [iCloud Export] iCloud not available")
			completion(.failure(.iCloudNotAvailable))
			return
		}
		
		DispatchQueue.main.async {
			self.isExporting = true
			self.syncStatus = LocalizationManager.shared.localized("exporting_to_icloud")
		}
		
		DispatchQueue.global(qos: .userInitiated).async {
			do {
				try self.performExport()
				
				DispatchQueue.main.async {
					self.isExporting = false
					self.lastSyncDate = Date()
					self.syncStatus = LocalizationManager.shared.localized("export_completed")
					completion(.success(()))
				}
			} catch {
				DispatchQueue.main.async {
					self.isExporting = false
					self.syncStatus = LocalizationManager.shared.localized("export_failed")
					if let iCloudError = error as? iCloudError {
						completion(.failure(iCloudError))
					} else {
						completion(.failure(.exportFailed(error.localizedDescription)))
					}
				}
			}
		}
	}
	
	/// Export only citation data JSON to iCloud app folder (Documents root)
	func exportDataOnlyToiCloud(completion: @escaping (Result<Void, iCloudError>) -> Void) {
		print("🚀 [iCloud Export] Starting export (data only) ...")
		guard isiCloudAvailable else {
			print("❌ [iCloud Export] iCloud not available")
			completion(.failure(.iCloudNotAvailable))
			return
		}
		DispatchQueue.main.async { self.isExporting = true; self.syncStatus = LocalizationManager.shared.localized("exporting_to_icloud") }
		DispatchQueue.global(qos: .userInitiated).async {
			do {
				let jsonData = try self.makeExportJSONData()
				// 优先 CloudDocs（若已书签/可访问），否则回退到应用容器
				if let cloudURL = self.cloudDocsDataFileURL() {
					let fm = FileManager.default
					let dir = cloudURL.deletingLastPathComponent()
					try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
					try jsonData.write(to: cloudURL, options: [.atomic])
					print("✅ [iCloud Export] Data exported to CloudDocs: \(cloudURL.path)")
				} else {
					try self.createiCloudFolder()
					guard let citationURL = self.citationDataURL else { throw iCloudError.invalidURL }
					try jsonData.write(to: citationURL)
					print("✅ [iCloud Export] Data exported to App Container: \(citationURL.path)")
				}
				DispatchQueue.main.async { self.isExporting = false; self.lastSyncDate = Date(); self.syncStatus = LocalizationManager.shared.localized("export_completed"); completion(.success(())) }
			} catch {
				DispatchQueue.main.async {
					self.isExporting = false
					self.syncStatus = LocalizationManager.shared.localized("export_failed")
					if let icErr = error as? iCloudError { completion(.failure(icErr)) } else { completion(.failure(.exportFailed(error.localizedDescription))) }
				}
			}
		}
	}

	/// Perform the actual export
	private func performExport() throws {
		print("🔍 [iCloud Export] Creating iCloud folder...")
		try createiCloudFolder()
		// 使用内联实现构建导出JSON
		guard let citationURL = citationDataURL else { throw iCloudError.invalidURL }
		let jsonData = try makeExportJSONData()
		try jsonData.write(to: citationURL)
		print("✅ [iCloud Export] Citation data exported successfully")
		try exportAppConfig()
	}
	
	/// Create CiteTrack folder in iCloud
	private func createiCloudFolder() throws {
		guard let folderURL = citeTrackFolderURL else {
			print("❌ [iCloud Export] Invalid folder URL")
			throw iCloudError.invalidURL
		}
		let fileManager = FileManager.default
		if !fileManager.fileExists(atPath: folderURL.path) {
			print("🔍 [iCloud Export] Creating CiteTrack folder...")
			try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
			print("✅ [iCloud Export] Created CiteTrack folder in iCloud: \(folderURL.path)")
		} else {
			print("ℹ️ [iCloud Export] CiteTrack folder already exists")
		}
	}
	
	/// Export app data (settings + refreshData) to iCloud
	private func exportAppConfig() throws {
		guard let configURL = configFileURL else {
			print("❌ [iCloud Export] Invalid config file URL")
			throw iCloudError.invalidURL
		}
		let config = makeCurrentAppData()
		let jsonData = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
		try jsonData.write(to: configURL)
		print("✅ [iCloud Export] App data exported to iCloud: \(configURL.path)")
	}

	/// 构建当前应用数据（设置 + 刷新数据）
	private func makeCurrentAppData() -> [String: Any] {
		var dict: [String: Any] = [
			"version": "1.1",
			"exportDate": ISO8601DateFormatter().string(from: Date()),
			"settings": [
				"updateInterval": SettingsManager.shared.updateInterval,
				"notificationsEnabled": SettingsManager.shared.notificationsEnabled,
				"language": SettingsManager.shared.language,
				"theme": SettingsManager.shared.theme.rawValue,
				"iCloudDriveFolderEnabled": SettingsManager.shared.iCloudDriveFolderEnabled
			]
		]
		// 刷新数据
		dict["refreshData"] = exportRefreshDataFromBehavior()
		// 首次安装日期（跨重装使用）
		dict["firstInstallDate"] = exportFirstInstallDate()
		return dict
	}

	/// 包装导出负载（学术数据）为统一应用数据 JSON
	private func makeAppDataJSON(exportPayload: Data) throws -> Data {
		var unified = makeCurrentAppData()
		if let arr = try? JSONSerialization.jsonObject(with: exportPayload) as? [[String: Any]] {
			unified["citationHistory"] = arr
		} else if let obj = try? JSONSerialization.jsonObject(with: exportPayload) as? [String: Any] {
			unified.merge(obj) { _, new in new }
		}
		return try JSONSerialization.data(withJSONObject: unified, options: .prettyPrinted)
	}
	
	// MARK: - Status Check
	
	/// Check iCloud sync status
	func checkSyncStatus() {
        NSLog("🔍 [iCloud Status] checkSyncStatus() called")
		print("🔍 [iCloud Status] Checking sync status...")
		
		guard isiCloudAvailable else {
			DispatchQueue.main.async {
				self.syncStatus = LocalizationManager.shared.localized("icloud_not_available")
			}
			return
		}
		
		let fileManager = FileManager.default
		let citationExists = citationDataURL.map { fileManager.fileExists(atPath: $0.path) } ?? false
		let configExists = configFileURL.map { fileManager.fileExists(atPath: $0.path) } ?? false
		
		print("🔍 [iCloud Status] Citation file exists: \(citationExists)")
		print("🔍 [iCloud Status] Config file exists: \(configExists)")

		// 统一以优先可得的最新时间为准：CloudDocs -> 容器镜像 -> 内存lastSyncDate
		var lastSync: Date? = nil
		if citationExists, let citationURL = citationDataURL {
			do {
				let attributes = try fileManager.attributesOfItem(atPath: citationURL.path)
				lastSync = attributes[.modificationDate] as? Date
				print("🔍 [iCloud Status] Last sync date (CloudDocs citation): \(lastSync?.description ?? "unknown")")
			} catch {
				print("❌ [iCloud Status] Failed to get citation file date: \(error)")
			}
		} else if let docs = documentsURL {
			let mirrorURL = docs.appendingPathComponent(longTermSyncFileName)
			if fileManager.fileExists(atPath: mirrorURL.path) {
				do {
					let attributes = try fileManager.attributesOfItem(atPath: mirrorURL.path)
					lastSync = attributes[.modificationDate] as? Date
					print("🔍 [iCloud Status] Last sync date (Container mirror): \(lastSync?.description ?? "unknown")")
				} catch {
					print("❌ [iCloud Status] Failed to get mirror file date: \(error)")
				}
			}
		}
		if lastSync == nil { lastSync = self.lastSyncDate }

		DispatchQueue.main.async {
			self.lastSyncDate = lastSync
			if let last = lastSync {
				let f = DateFormatter()
				f.locale = Locale(identifier: "en_US_POSIX")
				f.dateFormat = "yyyy-MM-dd HH:mm"
				let prefix = LocalizationManager.shared.localized("last_sync")
				self.syncStatus = "\(prefix): \(f.string(from: last))"
			} else {
				self.syncStatus = LocalizationManager.shared.localized("icloud_available_no_sync")
			}
		}
	}
}

// MARK: - Data Structures

struct ImportResult {
	let importedScholars: Int
	let importedHistory: Int
	let configImported: Bool
	let importDate: Date
	
	var description: String {
		var parts: [String] = []
		let localizationManager = LocalizationManager.shared
		
		if importedScholars > 0 {
			parts.append("\(localizationManager.localized("imported_scholars_count")) \(importedScholars) \(localizationManager.localized("scholars_unit"))")
		}
		
		if importedHistory > 0 {
			parts.append("\(localizationManager.localized("imported_history_count")) \(importedHistory) \(localizationManager.localized("history_entries_unit"))")
		}
		
		if configImported {
			parts.append(localizationManager.localized("imported_config"))
		}
		
		if parts.isEmpty {
			return localizationManager.localized("no_data_to_import")
		}
		
		return parts.joined(separator: "，")
	}
}

// MARK: - Error Types

enum iCloudError: LocalizedError {
	case iCloudNotAvailable
	case invalidURL
	case noDataFound
	case exportFailed(String)
	case importFailed(String)
	
	var errorDescription: String? {
		let localizationManager = LocalizationManager.shared
		switch self {
		case .iCloudNotAvailable:
			return localizationManager.localized("icloud_drive_unavailable")
		case .invalidURL:
			return localizationManager.localized("invalid_icloud_url")
		case .noDataFound:
			return localizationManager.localized("no_citetrack_data_in_icloud")
		case .exportFailed(let message):
			return "\(localizationManager.localized("export_failed_with_message")): \(message)"
		case .importFailed(let message):
			return "\(localizationManager.localized("import_failed_with_message")): \(message)"
		}
	}
}

// MARK: - File Picker and Manual Import

extension iCloudSyncManager {
	/// Show file picker for manual import
	func showFilePicker() { showingFilePicker = true }
	
	/// Import data from selected file
	func importFromFile(url: URL) {
		print("🚀 [Manual Import] Starting import from file: \(url.path)")
		DispatchQueue.main.async { self.isImporting = true }
		do {
			let data = try Data(contentsOf: url)
			let result = try importFromJSONData(data)
			DispatchQueue.main.async {
				self.importResult = result
				self.showingImportResult = true
				self.isImporting = false
				// 手动导入完成后也刷新Widget
				DataManager.shared.refreshWidgets()
			}
		} catch {
			print("❌ [Manual Import] Failed to import file: \(error)")
			DispatchQueue.main.async {
				self.errorMessage = "import_failed_with_message".localized + ": \(error.localizedDescription)"
				self.showingErrorAlert = true
				self.isImporting = false
			}
		}
	}

	// MARK: - 内联导入/导出实现
	private func makeExportJSONData() throws -> Data {
		let formatter = ISO8601DateFormatter()
		let scholars = DataManager.shared.scholars
		var exportEntries: [[String: Any]] = []

		for scholar in scholars {
			let histories = DataManager.shared.getHistory(for: scholar.id)
			if histories.isEmpty {
				if let citations = scholar.citations {
					let ts = scholar.lastUpdated ?? Date()
					exportEntries.append([
						"scholarId": scholar.id,
						"scholarName": scholar.displayName,
						"timestamp": formatter.string(from: ts),
						"citationCount": citations
					])
				}
			} else {
				for h in histories {
					exportEntries.append([
						"scholarId": scholar.id,
						"scholarName": scholar.displayName,
						"timestamp": formatter.string(from: h.timestamp),
						"citationCount": h.citationCount
					])
				}
			}
		}

		return try JSONSerialization.data(withJSONObject: exportEntries, options: .prettyPrinted)
	}

	@discardableResult
	private func importFromJSONData(_ data: Data) throws -> ImportResult {
		let json = try JSONSerialization.jsonObject(with: data, options: [])
		if let array = json as? [[String: Any]] {
			return importFromMacOSEntries(array)
		} else if let dict = json as? [String: Any], let citationHistory = dict["citationHistory"] as? [[String: Any]] {
			var importedHistory = 0
			let scholarNames = Set(citationHistory.compactMap { $0["scholarName"] as? String })
			for entry in citationHistory {
				if let _ = entry["scholarName"] as? String,
				   let _ = entry["citationCount"] as? Int,
				   let _ = entry["timestamp"] as? String {
					importedHistory += 1
				}
			}
			return ImportResult(importedScholars: scholarNames.count, importedHistory: importedHistory, configImported: false, importDate: Date())
		} else {
			throw iCloudError.importFailed("validation_error".localized)
		}
	}

	/// 统一导入：支持 settings/refreshData
	private func importFromUnifiedData(_ data: Data) throws -> ImportResult {
		let json = try JSONSerialization.jsonObject(with: data, options: [])
		if let dict = json as? [String: Any] {
			var importedHistory = 0
			var importedScholars = 0
			if let citationHistory = dict["citationHistory"] as? [[String: Any]] {
				let res = importFromMacOSEntries(citationHistory)
				importedHistory += res.importedHistory
				importedScholars += res.importedScholars
			}
			if let settings = dict["settings"] as? [String: Any] {
				if let updateInterval = settings["updateInterval"] as? TimeInterval { SettingsManager.shared.updateInterval = updateInterval }
				if let notificationsEnabled = settings["notificationsEnabled"] as? Bool { SettingsManager.shared.notificationsEnabled = notificationsEnabled }
				if let language = settings["language"] as? String { SettingsManager.shared.language = language }
				if let themeRawValue = settings["theme"] as? String, let theme = AppTheme(rawValue: themeRawValue) { SettingsManager.shared.theme = theme }
			}
			if let refreshDict = dict["refreshData"] as? [String: Any] {
				importRefreshDataToBehavior(refreshDict)
			}
			return ImportResult(importedScholars: importedScholars, importedHistory: importedHistory, configImported: (dict["settings"] != nil), importDate: Date())
		} else if let _ = json as? [[String: Any]] {
			return try importFromJSONData(data)
		} else {
			throw iCloudError.importFailed("validation_error".localized)
		}
	}

	@discardableResult
	private func importFromMacOSEntries(_ entries: [[String: Any]]) -> ImportResult {
		var importedHistory = 0
		var importedScholars = 0
		let scholarIds = Set(entries.compactMap { $0["scholarId"] as? String })

		for scholarId in scholarIds {
			let scholarEntries = entries.filter { $0["scholarId"] as? String == scholarId }
			if let latestEntry = scholarEntries.max(by: {
				($0["timestamp"] as? String ?? "") < ($1["timestamp"] as? String ?? "")
			}) {
				let citationCount = latestEntry["citationCount"] as? Int ?? 0
				var scholar = Scholar(id: scholarId, name: "scholar_default_name".localized + " \(scholarId.prefix(8))")
				if let scholarName = latestEntry["scholarName"] as? String, !scholarName.isEmpty {
					scholar.name = scholarName
				}
				var updated = scholar
				updated.citations = citationCount
				updated.lastUpdated = ISO8601DateFormatter().date(from: latestEntry["timestamp"] as? String ?? "") ?? Date()
				// Upsert with newest-wins. addScholar is a no-op for an EXISTING scholar,
				// so importing could never correct a number that was already stored — but a
				// stale cloud value must not clobber a fresher local one either.
				if let existing = DataManager.shared.getScholar(id: scholarId) {
					let importedTime = updated.lastUpdated ?? .distantPast
					let localTime = existing.lastUpdated ?? .distantPast
					// Newer AND a plausible (non-zero) value — never let a malformed export
					// (missing citationCount defaults to 0) overwrite a good local count.
					if importedTime > localTime && citationCount > 0 {
						DataManager.shared.updateScholar(updated)
					}
				} else {
					DataManager.shared.addScholar(updated)
				}
				importedScholars += 1

				for entry in scholarEntries {
					if let count = entry["citationCount"] as? Int,
					   let tsString = entry["timestamp"] as? String,
					   let ts = ISO8601DateFormatter().date(from: tsString) {
						DataManager.shared.saveHistoryIfChanged(scholarId: scholarId, citationCount: count, timestamp: ts)
						importedHistory += 1
					}
				}
			}
		}

		return ImportResult(
			importedScholars: importedScholars,
			importedHistory: importedHistory,
			configImported: false,
			importDate: Date()
		)
	}
} 

// MARK: - Refresh data bridge (file-based, no direct dependency)
extension iCloudSyncManager {
	/// 从行为管理器导出每日刷新数据，格式兼容历史 ios_data.json
	func exportRefreshDataFromBehavior() -> [String: Any] {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd"
		let behaviors = UserBehaviorManager.shared.getBehaviorsForLastDays(365)
		var dataMap: [String: Int] = [:]
		for b in behaviors {
			let key = formatter.string(from: b.date)
			dataMap[key] = b.refreshCount
		}
		return [
			"user_id": "default_user",
			"data": dataMap,
			"last_updated": ISO8601DateFormatter().string(from: Date())
		]
	}

	// 导出首次安装日期（若无则写入今天），用于跨设备/重装保持热力图起点
	func exportFirstInstallDate() -> String {
		let key = "FirstInstallDate"
		let cal = Calendar.current
		if let saved = UserDefaults.standard.object(forKey: key) as? Date {
			return ISO8601DateFormatter().string(from: cal.startOfDay(for: saved))
		} else {
			let today = cal.startOfDay(for: Date())
			UserDefaults.standard.set(today, forKey: key)
			if let ag = UserDefaults(suiteName: appGroupIdentifier) { ag.set(today, forKey: key); ag.synchronize() }
			return ISO8601DateFormatter().string(from: today)
		}
	}

	/// 将刷新数据导入到行为管理器（同日求和）
	func importRefreshDataToBehavior(_ dict: [String: Any]) {
		// 新逻辑：按日期精确写入；首次启动导入时，过滤掉“今天”的条目，避免无操作计数
		let incoming = dict["data"] as? [String: Int] ?? [:]
		let isFirstLaunchImport = (UserDefaults.standard.bool(forKey: "FirstLaunchImportDone") == false)
		let cal = Calendar.current
		let todayKey: String = {
			let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: cal.startOfDay(for: Date()))
		}()
		var filtered = incoming
		if isFirstLaunchImport {
			filtered.removeValue(forKey: todayKey)
		}
		// 同步设置首次安装日期为导入数据中最早一天
		if let earliestKey = filtered.keys.min(), let date = ({ let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: earliestKey) })() {
			let dayStart = cal.startOfDay(for: date)
			DispatchQueue.main.async {
				UserDefaults.standard.set(dayStart, forKey: "FirstInstallDate")
				if let ag = UserDefaults(suiteName: appGroupIdentifier) { ag.set(dayStart, forKey: "FirstInstallDate"); ag.synchronize() }
				UserDefaults.standard.set(dayStart, forKey: "AppInstallDate")
				if let ag = UserDefaults(suiteName: appGroupIdentifier) { ag.set(dayStart, forKey: "AppInstallDate"); ag.synchronize() }
			}
		}
		DispatchQueue.main.async {
			UserBehaviorManager.shared.importRefreshData(filtered)
		}
	}
}