import Foundation

/// Bilingual string helper — detects system language at runtime, with user override.
enum L {
    /// nil = follow system, true = force Chinese, false = force English
    nonisolated static var languageOverride: Bool? {
        get {
            let d = UserDefaults.standard
            guard d.object(forKey: "languageOverride") != nil else { return nil }
            return d.bool(forKey: "languageOverride")
        }
        set {
            if let v = newValue {
                UserDefaults.standard.set(v, forKey: "languageOverride")
            } else {
                UserDefaults.standard.removeObject(forKey: "languageOverride")
            }
        }
    }

    nonisolated static var zh: Bool {
        if let override = languageOverride { return override }
        let lang = Locale.current.language.languageCode?.identifier ?? ""
        return lang.hasPrefix("zh")
    }

    // MARK: - Status Bar
    static var weeklyLimit: String { zh ? "周限额" : "Weekly Limit" }
    static var hourLimit: String   { zh ? "5h限额" : "5h Limit" }

    // MARK: - MenuBarView
    static var noAccounts: String      { zh ? "还没有账号"          : "No Accounts" }
    static var addAccountHint: String  { zh ? "点击下方 + 添加账号"   : "Tap + below to add an account" }
    static var refreshUsage: String    { zh ? "刷新用量"            : "Refresh Usage" }
    static var checkForUpdates: String { zh ? "检查更新"            : "Check for Updates" }
    static func menuUpdateAvailableTitle(_ version: String) -> String {
        zh ? "发现新版本 v\(version)" : "Version \(version) Is Available"
    }
    static func menuUpdateAvailableSubtitle(_ currentVersion: String, _ latestVersion: String) -> String {
        zh ? "当前为 \(currentVersion)，现在可以继续下载或安装 \(latestVersion)。" : "You're on \(currentVersion). Download or install \(latestVersion) now."
    }
    static var menuUpdateAction: String { zh ? "更新" : "Update" }
    static var addAccount: String      { zh ? "添加账号"            : "Add Account" }
    static var openAICSVToolbar: String { zh ? "导入或导出 OpenAI CSV" : "Import or Export OpenAI CSV" }
    static func codexLaunchSwitchedInstanceStarted(_ account: String) -> String {
        zh ? "已切换到「\(account)」，并为该账号新开一个 Codex 实例。" : "Switched to \"\(account)\" and launched a new Codex instance for it."
    }
    static var codexLaunchProbeAppNotFound: String {
        zh ? "未找到 Codex.app" : "Codex.app was not found"
    }
    static var codexLaunchProbeExecutableMissing: String {
        zh ? "未找到 bundled codex 可执行文件" : "The bundled codex executable was not found"
    }
    static var codexLaunchProbeTimedOut: String {
        zh ? "启动 Codex.app 超时" : "Launching Codex.app timed out"
    }
    static func codexLaunchProbeFailed(_ message: String) -> String {
        zh ? "受管启动探针失败：\(message)" : "Managed launch probe failed: \(message)"
    }
    static var exportOpenAICSVAction: String { zh ? "导出 OpenAI CSV…" : "Export OpenAI CSV…" }
    static var importOpenAICSVAction: String { zh ? "导入 OpenAI CSV…" : "Import OpenAI CSV…" }
    static var settings: String { zh ? "设置" : "Settings" }
    static func updateInstallActionHelp(_ version: String) -> String {
        zh ? "下载或安装 \(version)" : "Download or Install \(version)"
    }
    static var updateInstallLocationOther: String {
        zh ? "非标准路径" : "Non-standard Location"
    }
    static var updateArchitectureUniversal: String {
        zh ? "通用构建" : "Universal Build"
    }
    static var updateSignatureUnknown: String {
        zh ? "未能读取应用签名信息" : "Unable to read the app signature"
    }
    static var updateBlockerGuidedDownloadOnlyRelease: String {
        zh ? "当前可用版本仍要求走引导下载/安装，不宣称自动替换闭环。" : "The current release still requires guided download/install instead of automatic replacement."
    }
    static func updateBlockerBootstrapRequired(_ currentVersion: String, _ minimumAutomaticVersion: String) -> String {
        zh
            ? "Bootstrap / Rollout Gate 未满足：\(currentVersion) 仍需先人工安装到 \(minimumAutomaticVersion) 或更高版本，自动更新闭环才从后续版本开始。"
            : "Bootstrap / rollout gate not satisfied: \(currentVersion) must first be manually upgraded to \(minimumAutomaticVersion) or later before automatic updates can be closed-loop."
    }
    static var updateBlockerAutomaticUpdaterUnavailable: String {
        zh ? "当前仓库尚未接入可用的成熟自动更新引擎。" : "A mature automatic update engine is not wired into this repository yet."
    }
    static func updateBlockerMissingTrustedSignature(_ summary: String) -> String {
        zh
            ? "当前安装缺少可用于成熟 updater 的可信签名：\(summary)"
            : "This installation lacks a trusted signature suitable for a mature updater: \(summary)"
    }
    static func updateBlockerGatekeeperAssessment(_ summary: String) -> String {
        zh
            ? "当前安装未通过 Gatekeeper / 分发前置条件：\(summary)"
            : "This installation does not satisfy the Gatekeeper / distribution prerequisites: \(summary)"
    }
    static func updateBlockerUnsupportedInstallLocation(_ pathDescription: String) -> String {
        zh
            ? "当前安装路径为 \(pathDescription)，尚未纳入可自动替换的受支持范围。"
            : "The current install location is \(pathDescription), which is not yet in the supported auto-replace matrix."
    }
    static var updateErrorMissingReleasesURL: String {
        zh ? "未配置 GitHub Releases API 地址。" : "The GitHub Releases API URL is not configured."
    }
    static func updateErrorInvalidCurrentVersion(_ version: String) -> String {
        zh ? "当前版本号无效：\(version)" : "Invalid current version: \(version)"
    }
    static func updateErrorInvalidReleaseVersion(_ version: String) -> String {
        zh ? "最新稳定版本号无效：\(version)" : "Invalid latest stable version: \(version)"
    }
    static var updateErrorInvalidResponse: String {
        zh ? "GitHub Releases 响应无效。" : "The GitHub Releases response is invalid."
    }
    static func updateErrorUnexpectedStatusCode(_ statusCode: Int) -> String {
        zh ? "GitHub Releases API 返回异常状态码：\(statusCode)" : "The GitHub Releases API returned status code \(statusCode)."
    }
    static var updateErrorNoInstallableStableRelease: String {
        zh ? "GitHub Releases 中未找到可安装的正式稳定版本。" : "No installable stable release was found on GitHub Releases."
    }
    static func updateErrorNoCompatibleArtifact(_ architecture: String) -> String {
        zh ? "最新稳定版本中缺少适用于 \(architecture) 的安装包。" : "The latest stable release does not contain a compatible installer for \(architecture)."
    }
    static func updateErrorFailedToOpenDownloadURL(_ url: String) -> String {
        zh ? "无法打开下载链接：\(url)" : "Failed to open the download URL: \(url)"
    }
    static var updateErrorAutomaticUpdateUnavailable: String {
        zh ? "当前构建尚未接入可执行的自动更新引擎。" : "An executable automatic update engine is not available in this build."
    }
    static var settingsWindowTitle: String { self.settings }
    static var settingsWindowHint: String {
        zh
            ? "左侧可切换 Accounts、General、Usage、Provider、API Service 子页与 Updates。每个页签独立保存；切换页签或关闭窗口时，如果当前页有未保存修改，会先提示你确认。"
            : "Use the sidebar to switch between Accounts, General, Usage, Provider, API Service subpages, and Updates. Each page saves independently, and switching pages or closing the window will confirm unsaved edits on the current page."
    }
    static var settingsUnsavedChangesTitle: String {
        zh ? "当前页有未保存修改" : "Unsaved Changes on This Page"
    }
    static func settingsUnsavedChangesMessage(_ pageTitle: String) -> String {
        zh
            ? "“\(pageTitle)”页有未保存修改。离开前是否保存当前页？"
            : "\"\(pageTitle)\" has unsaved changes. Do you want to save this page before leaving?"
    }
    static var settingsDiscardChangesAction: String {
        zh ? "不保存" : "Don't Save"
    }
    static var settingsAccountsPageTitle: String { zh ? "账户设置" : "Account Settings" }
    static var settingsGeneralPageTitle: String { zh ? "通用" : "General" }
    static var settingsUsagePageTitle: String { zh ? "用量设置" : "Usage Settings" }
    static var settingsAPIServicePageTitle: String { zh ? "API 服务" : "API Service" }
    static var settingsProviderPageTitle: String { zh ? "Provider" : "Provider" }
    static var settingsAPIServiceGroupTitle: String { zh ? "API 服务" : "API Service" }
    static var settingsAPIServiceOverviewPageTitle: String { zh ? "Overview / Config" : "Overview / Config" }
    static var settingsAPIServiceDashboardPageTitle: String { zh ? "Dashboard" : "Dashboard" }
    static var settingsAPIServiceLogsPageTitle: String { zh ? "Logs" : "Logs" }
    static var settingsCodexAppPathPageTitle: String { zh ? "Codex App 路径设置" : "Codex App Path" }
    static var settingsUpdatesPageTitle: String { zh ? "更新" : "Updates" }
    static var settingsProviderPageHint: String {
        zh ? "这里管理 provider / account 资产与模型元数据。popup 仍保留 Use / 切换 / 快速操作。" : "Manage provider/account assets and model metadata here. The popup still keeps Use / switching / quick actions."
    }
    static var settingsProviderEmptyState: String { zh ? "当前还没有已注册的 Provider 资产。" : "No provider assets have been registered yet." }
    static var settingsProviderCompatibleProvidersTitle: String { zh ? "Compatible Providers" : "Compatible Providers" }
    static var settingsProviderOpenRouterTitle: String { zh ? "OpenRouter" : "OpenRouter" }
    static var settingsProviderAddCompatibleProvider: String { zh ? "新增 Compatible Provider" : "Add Compatible Provider" }
    static var settingsProviderAddOpenRouter: String { zh ? "新增 OpenRouter" : "Add OpenRouter" }
    static var settingsProviderWindowTitle: String { zh ? "Provider 管理" : "Provider Management" }
    static var settingsProviderEditProviderTitle: String { zh ? "编辑 Provider" : "Edit Provider" }
    static var settingsProviderAddOpenRouterAccountTitle: String { zh ? "新增 OpenRouter 账号" : "Add OpenRouter Account" }
    static var settingsProviderEditOpenRouterTitle: String { zh ? "编辑 OpenRouter 模型" : "Edit OpenRouter Models" }
    static var settingsAPIServiceDashboardPageHint: String {
        zh ? "集中查看 API Service 的长期运行摘要、Quota 快照与流量统计。服务停止时这里仍会保留空态入口。" : "Use this page for long-lived API Service summaries, quota snapshots, and traffic stats. The page stays visible even when the service is stopped."
    }
    static var settingsAPIServiceDashboardRuntimeTitle: String { zh ? "运行状态" : "Runtime" }
    static var settingsAPIServiceDashboardRequestsTitle: String { zh ? "请求量" : "Requests" }
    static var settingsAPIServiceDashboardTokensTitle: String { zh ? "Tokens" : "Tokens" }
    static var settingsAPIServiceDashboardNoRuntimeIssue: String { zh ? "暂无运行告警" : "No runtime warning" }
    static func settingsAPIServiceDashboardFailedRequests(_ value: Int) -> String {
        zh ? "失败请求：\(value)" : "Failed requests: \(value)"
    }
    static func settingsAPIServiceDashboardQuotaWindow(_ primary: String, _ weekly: String) -> String {
        zh ? "最低剩余：5H \(primary) · 7D \(weekly)" : "Lowest remaining: 5H \(primary) · 7D \(weekly)"
    }
    static var settingsAPIServiceDashboardNoQuotaWindow: String { zh ? "暂无配额窗口数据" : "No quota window data yet" }
    static var settingsAPIServiceDashboardEmptyState: String { zh ? "当前没有可展示的 API Service Dashboard 数据。" : "No API Service dashboard data is available yet." }
    static var settingsAPIServiceLogsPageHint: String {
        zh ? "读取 CLIProxyAPI management logs。若服务未运行或未启用写文件日志，这里会展示只读空态。" : "Read CLIProxyAPI management logs here. When the service is stopped or file logging is disabled, this page shows a read-only empty state."
    }
    static var settingsAPIServiceLogsRefresh: String { zh ? "刷新日志" : "Refresh Logs" }
    static var settingsAPIServiceLogsRefreshing: String { zh ? "刷新日志中…" : "Refreshing Logs…" }
    static var settingsAPIServiceLogsLoading: String { zh ? "加载日志中…" : "Loading logs…" }
    static var settingsAPIServiceLogsStoppedHint: String { zh ? "API Service 当前已停止。你仍可保留此入口；重新启动服务后即可拉取日志。" : "API Service is currently stopped. The page stays available; start the service again to fetch logs." }
    static var settingsAPIServiceLogsMissingSecret: String { zh ? "缺少 management key，无法请求日志。" : "Missing management key; unable to request logs." }
    static var settingsAPIServiceLogsEmptyState: String { zh ? "当前没有日志行。" : "No log lines are available right now." }
    static func settingsAPIServiceLogsLineCount(_ count: Int) -> String {
        zh ? "日志行数：\(count)" : "Lines: \(count)"
    }
    static func settingsAPIServiceLogsLatestTimestamp(_ value: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(value))
        let formatted = date.formatted(date: .abbreviated, time: .shortened)
        return zh ? "最新时间：\(formatted)" : "Latest: \(formatted)"
    }
    static var settingsGeneralMenuBarDisplayHint: String {
        zh ? "这里控制菜单栏图标旁的文字内容。百分比语义（已用 / 剩余）仍沿用“用量设置”页面。" : "Control the text shown next to the menu bar icon here. Percentage semantics (used vs remaining) still come from the Usage page."
    }
    static var settingsMenuBarQuotaVisibilityTitle: String { zh ? "显示内容" : "Quota Windows" }
    static var settingsMenuBarQuotaVisibilityHint: String {
        zh ? "选择菜单栏图标旁展示哪些配额窗口。隐藏文字时，原有警告图标仍会保留。" : "Choose which quota windows appear next to the menu bar icon. Warning icons still remain even when the text is hidden."
    }
    static var settingsMenuBarQuotaVisibilityBoth: String { zh ? "显示 5H 和 7D" : "Show 5H and 7D" }
    static var settingsMenuBarQuotaVisibilityPrimaryOnly: String { zh ? "仅显示 5H" : "Show 5H Only" }
    static var settingsMenuBarQuotaVisibilitySecondaryOnly: String { zh ? "仅显示 7D" : "Show 7D Only" }
    static var settingsMenuBarQuotaVisibilityHidden: String { zh ? "全部关闭" : "Hide All" }
    static var settingsMenuBarQuotaVisibilityBothHint: String { zh ? "同时展示 5 小时与 7 天配额。" : "Show both the 5-hour and 7-day quota windows." }
    static var settingsMenuBarQuotaVisibilityPrimaryOnlyHint: String { zh ? "只展示 5 小时配额。" : "Show only the 5-hour quota window." }
    static var settingsMenuBarQuotaVisibilitySecondaryOnlyHint: String { zh ? "只展示 7 天配额。" : "Show only the 7-day quota window." }
    static var settingsMenuBarQuotaVisibilityHiddenHint: String { zh ? "不显示配额文字，仅保留图标状态。" : "Hide quota text and keep the icon state only." }
    static var settingsMenuBarAPIServiceStatusTitle: String { zh ? "API 服务状态" : "API Service Status" }
    static var settingsMenuBarAPIServiceStatusHint: String {
        zh ? "当菜单栏当前展示 API 服务时，决定是否显示“当前可路由账号池 / 已选账号池”的可用数。" : "When the menu bar is showing API Service status, choose whether to show availability for the current routable pool versus the selected member pool."
    }
    static var settingsMenuBarAPIServiceStatusVisible: String { zh ? "显示可用账号/总账号" : "Show Available/Total" }
    static var settingsMenuBarAPIServiceStatusHidden: String { zh ? "不显示" : "Hide" }
    static var settingsMenuBarAPIServiceStatusVisibleHint: String { zh ? "优先按运行时观测结果显示可用账号/总账号。" : "Show available/total accounts, preferring runtime observations when available." }
    static var settingsMenuBarAPIServiceStatusHiddenHint: String { zh ? "API 服务启用时不显示菜单栏文字。" : "Hide menu bar text when API Service is enabled." }
    static var settingsAPIServiceEnabled: String { zh ? "启用 CLIProxyAPI 服务" : "Enable CLIProxyAPI Service" }
    static var settingsAPIServiceConfigEnabled: String { zh ? "启用 API Service 配置接管" : "Enable API Service Routing" }
    static var settingsAPIServiceConfigHint: String {
        zh
            ? "这个开关只控制 Codex 配置是否交给 API Service 接管；运行中的服务请用上方 Start Now / Stop Service 控制。"
            : "This toggle only controls whether Codex routing is owned by API Service. Use Start Now / Stop Service above to control the running process."
    }
    static var settingsAPIServiceAddress: String { zh ? "服务地址" : "Service Address" }
    static var settingsAPIServicePort: String { zh ? "服务端口" : "Service Port" }
    static var settingsAPIServiceManagementKey: String { zh ? "管理密钥" : "Management Key" }
    static var settingsAPIServiceClientAPIKey: String { zh ? "客户端 API Key" : "Client API Key" }
    static var settingsAPIServiceImportConfig: String { zh ? "导入 CliproxyAPI 配置" : "Import CliproxyAPI Config" }
    static var settingsAPIServiceMembers: String { zh ? "服务成员账号" : "Service Member Accounts" }
    static var settingsAPIServiceRestrictFreeAccounts: String { zh ? "限制 FREE 账号" : "Limit FREE Accounts" }
    static var settingsAPIServiceAddressPlaceholder: String { zh ? "例如：127.0.0.1" : "For example: 127.0.0.1" }
    static var settingsAPIServiceClientAPIKeyPlaceholder: String {
        zh ? "输入或生成客户端 API Key" : "Enter or generate a client API key"
    }
    static var settingsAPIServiceCopyValue: String { zh ? "复制" : "Copy" }
    static var settingsAPIServiceRandomizePort: String { zh ? "随机端口" : "Random Port" }
    static var settingsAPIServiceRandomizeKey: String { zh ? "随机生成密钥" : "Random Key" }
    static var settingsAPIServiceImportPath: String { zh ? "路径" : "Path" }
    static var settingsAPIServiceDetectPath: String { zh ? "检测" : "Detect" }
    static var settingsAPIServiceImportAction: String { zh ? "导入" : "Import" }
    static var settingsAPIServiceImporting: String { zh ? "导入中…" : "Importing…" }
    static var settingsAPIServiceChoosePath: String { zh ? "选择路径" : "Choose Path" }
    static var settingsAPIServiceImportPathReady: String { zh ? "已选择外部 CPA 配置路径，可继续导入。" : "External CPA config path selected. You can import it now." }
    static var settingsAPIServiceDetectedPathReady: String { zh ? "已检测到外部 CPA 配置，可继续导入。" : "External CPA config detected. You can import it now." }
    static var settingsAPIServiceImportPathRequired: String { zh ? "请先选择或检测外部 CPA 配置路径" : "Choose or detect an external CPA config path first." }
    static var settingsAPIServiceNoDetectedPath: String { zh ? "未检测到外部 CPA 路径" : "No external CPA path detected." }
    static var settingsAPIServiceUsagePanelTitle: String { zh ? "按账号统计" : "Usage by Account" }
    static func settingsAPIServiceSuccessFailed(_ success: Int, _ failed: Int) -> String {
        zh ? "成功 \(success) / 失败 \(failed)" : "Success \(success) / Failed \(failed)"
    }
    static func settingsAPIServiceTokens(_ tokens: Int) -> String {
        zh ? "\(tokens) Tokens" : "\(tokens) Tokens"
    }
    static var settingsAPIServiceNoUsageData: String { zh ? "暂无账号统计数据" : "No account usage data yet" }
    static var settingsAPIServiceNoQuotaData: String { zh ? "暂无配额快照" : "No quota snapshot yet" }
    static var settingsAPIServiceNoImportedAccounts: String { zh ? "未读取到外部 CPA 账号" : "No imported CPA accounts" }
    static var settingsAPIServiceQuotaPanelTitle: String { zh ? "Quota Snapshot" : "Quota Snapshot" }
    static var settingsAPIServiceTrafficPanelTitle: String { zh ? "Traffic Stats" : "Traffic Stats" }
    static var settingsAPIServiceRefreshQuota: String { zh ? "刷新配额" : "Refresh Quota" }
    static var settingsAPIServiceRefreshingQuota: String { zh ? "刷新配额中…" : "Refreshing Quota…" }
    static func settingsAPIServiceQuotaFreshness(_ status: String, _ updatedAt: String) -> String {
        zh ? "状态：\(status) · 更新时间：\(updatedAt)" : "Status: \(status) · Updated: \(updatedAt)"
    }
    static var settingsAPIServiceRuntimeControls: String { zh ? "运行策略" : "Runtime Controls" }
    static var settingsAPIServiceRoutingStrategy: String { zh ? "路由策略" : "Routing Strategy" }
    static var settingsAPIServiceRoutingRoundRobin: String { zh ? "轮询" : "Round Robin" }
    static var settingsAPIServiceRoutingFillFirst: String { zh ? "填满优先" : "Fill First" }
    static var settingsAPIServiceRetryPolicy: String { zh ? "重试策略" : "Retry Policy" }
    static var settingsAPIServiceRequestRetry: String { zh ? "重试次数" : "Request Retry" }
    static var settingsAPIServiceMaxRetryInterval: String { zh ? "最大等待" : "Max Retry Interval" }
    static var settingsAPIServiceSwitchProjectOnQuota: String { zh ? "配额耗尽时自动切项目" : "Switch Project on Quota Exceeded" }
    static var settingsAPIServiceSwitchPreviewModelOnQuota: String { zh ? "配额耗尽时自动切 Preview 模型" : "Switch Preview Model on Quota Exceeded" }
    static var settingsAPIServiceDisableCooling: String { zh ? "禁用全局冷却" : "Disable Cooling" }
    static var settingsAPIServicePriorityLabel: String { zh ? "优先级" : "Priority" }
    static var apiServiceFallbackDegradedTitle: String { zh ? "API 服务运行异常" : "API Service is degraded" }
    static var apiServiceFallbackDegradedMessage: String { zh ? "CLIProxyAPI 当前不处于健康运行态；在恢复前不应把它当作可用的 OAuth 池真相源。" : "CLIProxyAPI is not currently healthy; do not treat it as the source of truth for OAuth pool routing until it recovers." }
    static var apiServiceFallbackUnserviceableTitle: String { zh ? "API 服务账号池已不可服务" : "API Service pool is unserviceable" }
    static var apiServiceFallbackUnserviceableMessageWithFallback: String { zh ? "已选中的 CPA auth 全部处于 disabled 或冷却中。现在可以关闭 API 服务，回退到 direct OAuth / Provider 路径。" : "All selected CPA auth files are disabled or cooling down. You can now disable API Service and fall back to direct OAuth / provider routing." }
    static var apiServiceFallbackUnserviceableMessageWithoutFallback: String { zh ? "已选中的 CPA auth 全部处于 disabled 或冷却中，而且当前没有可自动回退的 direct OAuth / Provider 候选。请打开设置页执行显式恢复。" : "All selected CPA auth files are disabled or cooling down, and there is no direct OAuth / provider candidate to fall back to automatically. Open settings to perform an explicit recovery." }
    static var apiServiceFallbackDisableAction: String { zh ? "关闭 API 服务" : "Disable API Service" }
    static var apiServiceFallbackOpenSettingsAction: String { zh ? "打开设置" : "Open Settings" }
    static var apiServiceFallbackRestoreAction: String { zh ? "恢复原生登录" : "Restore Native Access" }
    static var apiServiceFallbackRestoreConfirmTitle: String { zh ? "确认恢复 Codex 原生登录？" : "Restore Codex native access?" }
    static var apiServiceFallbackRestoreConfirmMessage: String { zh ? "这会关闭 API Service 路由，并优先恢复启用前的 direct 快照；若快照账号与当前目标不一致，则直接重写为目标账号的直连配置。" : "This disables API Service routing and restores the pre-enable direct snapshot when it matches the target account; otherwise it rewrites native config for the selected direct account." }
    static func apiServiceFallbackRestoreResult(_ status: String) -> String {
        zh ? "原生恢复结果：\(status)" : "Native restore result: \(status)"
    }
    static var apiServiceFallbackRestoreCompleted: String { zh ? "已恢复原生登录，请重启终端" : "Native access restored. Please restart Terminal." }
    static var settingsAPIServiceRemaining5h: String { zh ? "5h" : "5h" }
    static var settingsAPIServiceRemainingWeekly: String { zh ? "Weekly" : "Weekly" }
    static var settingsStatsPanelTitle: String { zh ? "统计面板" : "Stats Panel" }
    static var settingsAPIServiceStartNow: String { zh ? "立即启动" : "Start Now" }
    static var settingsAPIServiceStopNow: String { zh ? "停止服务" : "Stop Service" }
    static var settingsAPIServiceCheckHealth: String { zh ? "检查健康" : "Check Health" }
    static var settingsAPIServiceChecking: String { zh ? "检查中…" : "Checking…" }
    static func settingsAPIServiceRuntimeStatus(_ status: String) -> String {
        zh ? "运行状态：\(status)" : "Runtime Status: \(status)"
    }
    static func settingsAPIServiceAuthFileCount(_ count: Int) -> String {
        zh ? "凭据文件：\(count)" : "Auth Files: \(count)"
    }
    static func settingsAPIServiceModelCount(_ count: Int) -> String {
        zh ? "模型数量：\(count)" : "Models: \(count)"
    }
    static var settingsAPIServiceModelIDsTitle: String { zh ? "Model IDs" : "Model IDs" }
    static var settingsAPIServiceModelIDsEmpty: String {
        zh ? "当前运行态没有返回可用模型列表。" : "The current runtime did not return any available model IDs."
    }
    static var settingsAPIServiceModelIDsCopyAll: String { zh ? "复制全部" : "Copy All" }
    static func settingsAPIServiceTotalRequests(_ count: Int) -> String {
        zh ? "总请求数：\(count)" : "Total Requests: \(count)"
    }
    static func settingsAPIServiceFailedRequests(_ count: Int) -> String {
        zh ? "失败请求：\(count)" : "Failed Requests: \(count)"
    }
    static func settingsAPIServiceTotalTokens(_ count: Int) -> String {
        zh ? "总 Token：\(count)" : "Total Tokens: \(count)"
    }
    static var settingsAPIServiceHint: String {
        zh
            ? "保存后会把 CLIProxyAPI 启停配置写入 Codexkit 配置；实际运行时会使用安全写入的 config.yaml 与显式仓库路径解析。"
            : "Saving stores CLIProxyAPI startup settings in Codexkit config. Runtime launch uses a securely-written config.yaml and explicit repository-root resolution."
    }
    static var menuAPIServiceTitle: String { zh ? "API 服务" : "API Service" }
    static var menuAPIServiceQuotaLabel: String { zh ? "Quota" : "Quota" }
    static var menuAPIServiceUpdatedLabel: String { zh ? "Updated" : "Updated" }
    static var menuAPIServiceRunningState: String { zh ? "运行中" : "Running" }
    static var menuAPIServiceStoppedState: String { zh ? "已停止" : "Stopped" }
    static var menuAPIServiceEnabled: String { zh ? "API服务 已启用" : "API Service Enabled" }
    static var menuAPIServiceDisabled: String { zh ? "API服务 已停止" : "API Service Stopped" }
    static var menuAPIServiceRoutingEnabled: String { zh ? "配置接管已启用" : "Routing Enabled" }
    static var menuAPIServiceRoutingDisabled: String { zh ? "配置接管未启用" : "Routing Disabled" }
    static var menuAPIServiceAddressLabel: String { zh ? "地址" : "Address" }
    static var menuAPIServiceKeyLabel: String { zh ? "管理密钥" : "Management Key" }
    static var menuAPIServicePortLabel: String { zh ? "端口" : "Port" }
    static var menuAPIServiceRepoLabel: String { zh ? "仓库" : "Repo" }
    static var menuAPIServiceMembersLabel: String { zh ? "成员" : "Members" }
    static var menuAPIServiceRuntimeLabel: String { zh ? "运行态" : "Runtime" }
    static var menuAPIServiceRuntimeToggleTitle: String { zh ? "服务运行" : "Run Service" }
    static var menuAPIServiceConfigToggleTitle: String { zh ? "配置启用" : "Enable Routing" }
    static var menuAPIServicePreflightTitle: String { zh ? "API 服务前置检查" : "API Service prerequisite" }
    static var menuAPIServiceSetupRequiredMessage: String { zh ? "请先在设置中完成 API 服务配置" : "Finish API Service setup in Settings first." }
    static var menuAPIServiceStartRequiredMessage: String { zh ? "请先在设置中完成 API 服务配置并启动 API 服务，再启用 Routing" : "Finish API Service setup and start the service before enabling routing." }
    static var menuAPIServiceEnableAction: String { zh ? "启动" : "Enable" }
    static var menuAPIServiceDisableAction: String { zh ? "停止" : "Disable" }
    static var menuAPIServiceConfigureAction: String { zh ? "配置" : "Configure" }
    static var menuAPIServiceRefreshQuotaAction: String { zh ? "刷新配额" : "Refresh Quota" }
    static var menuAPIServiceStopFirstMessage: String { zh ? "请先停止API服务" : "Stop the API service first" }
    static var menuAPIServiceRoutingProbeSuccess: String { zh ? "配置应用成功，请重启终端" : "Configuration applied. Please restart Terminal." }
    static func menuAPIServiceRoutingProbeFailed(_ detail: String) -> String {
        zh
            ? "Routing 探针失败：\(detail)。已自动回滚原生配置并关闭 Routing。"
            : "Routing probe failed: \(detail). Native config was rolled back and routing was disabled."
    }
    static func menuAPIServiceRoutingRollbackFailed(_ detail: String) -> String {
        zh
            ? "Routing 探针失败，且自动回滚失败：\(detail)"
            : "Routing probe failed and automatic rollback also failed: \(detail)"
    }
    static var menuOpenAIHeaderEmptyHint: String {
        zh ? "使用标题栏操作添加 OpenAI OAuth 账号。" : "Use the header actions to add OpenAI OAuth accounts."
    }
    static var menuProvidersTitle: String { zh ? "Providers" : "Providers" }
    static var menuProvidersEditAction: String { zh ? "编辑 Provider" : "Edit Provider" }
    static var menuLanguageToggle: String { zh ? "切换语言" : "Toggle Language" }
    static var menuLanguageAuto: String { zh ? "跟随系统" : "System Default" }
    static var menuLanguageChinese: String { zh ? "中文" : "Chinese" }
    static var menuLanguageEnglish: String { zh ? "English" : "English" }
    static var revealSecretAction: String { zh ? "查看密钥" : "Reveal Key" }
    static var hideSecretAction: String { zh ? "隐藏密钥" : "Hide Key" }
    static var openAIAccountsSettingsAction: String { zh ? "打开账户设置" : "Open Account Settings" }
    static var settingsUpdatesPageHint: String {
        zh
            ? "这里统一管理 Codexkit 与 Cliproxyapi 的更新设置。两者的版本检测来源与策略都在代码中硬编码，不提供自定义源。"
            : "Manage Codexkit and CLIProxyAPI update settings here. Both update checks use hardcoded sources and strategies rather than custom feeds."
    }
    static var settingsUpdatesCodexkitTitle: String { zh ? "Codexkit 更新" : "Codexkit Updates" }
    static var settingsUpdatesCLIProxyAPITitle: String { zh ? "Cliproxyapi 更新" : "CLIProxyAPI Updates" }
    static var settingsUpdatesAutoCheckTitle: String { zh ? "自动检查更新" : "Automatically Check for Updates" }
    static var settingsUpdatesAutoInstallTitle: String { zh ? "自动安装更新" : "Automatically Install Updates" }
    static var settingsUpdatesScheduleTitle: String { zh ? "定期检查策略" : "Scheduled Check Strategy" }
    static var settingsUpdatesManualCheckAction: String { zh ? "手动检查更新" : "Check for Updates Manually" }
    static var settingsUpdatesCurrentVersionTitle: String { zh ? "当前版本" : "Current Version" }
    static var settingsUpdatesInstalledVersionTitle: String { zh ? "当前已安装版本" : "Installed Version" }
    static var settingsUpdatesLatestVersionTitle: String { zh ? "最新版本" : "Latest Version" }
    static var settingsUpdatesStatusTitle: String { zh ? "更新状态" : "Update Status" }
    static var settingsUpdatesUnknownVersion: String { zh ? "尚未检查" : "Not Checked Yet" }
    static var settingsUpdatesCheckAction: String { zh ? "检查 GitHub 上的最新稳定版本" : "Check the Latest Stable Version on GitHub" }
    static var settingsUpdatesInstallAction: String { zh ? "继续下载或安装更新" : "Continue Download or Install" }
    static var settingsUpdatesChecking: String { zh ? "正在检查 GitHub 上的最新稳定版本…" : "Checking the latest stable version on GitHub..." }
    static var settingsUpdatesIdle: String { zh ? "尚未发起更新检查。" : "No update check has been started yet." }
    static var settingsUpdatesSourceNote: String {
        zh
            ? "运行时会扫描 GitHub Releases 列表，只认非 draft、非 prerelease、且带 dmg/zip 安装包的正式 release。"
            : "Runtime checks scan the GitHub Releases list and only accept non-draft, non-prerelease releases that ship installable dmg/zip assets."
    }
    static var settingsUpdatesCodexkitSourceNote: String {
        zh
            ? "Codexkit 更新检测硬编码为 GitHub Releases 列表扫描；自动安装开启后，自动检查命中更新会直接触发既有下载/安装动作。"
            : "Codexkit update detection is hardcoded to scan GitHub Releases. When auto-install is enabled, automatic checks trigger the existing download/install action immediately."
    }
    static var settingsUpdatesCLIProxyAPISourceNote: String {
        zh
            ? "Cliproxyapi 更新检测硬编码为本地 `git describe --tags --always --dirty` + GitHub latest release；操作按钮会打开固定发布页。"
            : "CLIProxyAPI update detection is hardcoded to local `git describe --tags --always --dirty` plus the GitHub latest-release endpoint; the action button opens the fixed release page."
    }
    static var settingsUpdatesReissueLimitNote: String {
        zh
            ? "如果你已安装首发 1.1.9，同版本重发不会自动显示为可升级；需要手工下载重发 build。"
            : "If you already installed the first 1.1.9 build, a same-version reissue will not show up as an upgrade automatically; you must download the reissued build manually."
    }
    static func settingsUpdatesManualDialogTitle(_ target: String) -> String {
        zh ? "\(target) 手动检查结果" : "Manual Update Check — \(target)"
    }
    static func settingsUpdatesUpToDate(_ version: String) -> String {
        zh ? "当前版本 \(version) 已是最新版本。" : "The current version \(version) is already up to date."
    }
    static func settingsUpdatesAvailable(_ currentVersion: String, _ latestVersion: String) -> String {
        zh ? "当前版本 \(currentVersion)，发现最新版本 \(latestVersion)。" : "Current version \(currentVersion); latest available version \(latestVersion)."
    }
    static func settingsUpdatesExecuting(_ version: String) -> String {
        zh ? "正在处理 \(version) 的更新动作。" : "Processing the update action for \(version)."
    }
    static func settingsUpdatesFailed(_ message: String) -> String {
        zh ? "更新失败：\(message)" : "Update failed: \(message)"
    }
    static var updateScheduleDaily: String { zh ? "每天" : "Daily" }
    static var updateScheduleWeekly: String { zh ? "每周" : "Weekly" }
    static var updateScheduleMonthly: String { zh ? "每月" : "Monthly" }
    static var usageDisplayModeTitle: String { zh ? "用量显示方式" : "Usage Display" }
    static var remainingUsageDisplay: String { zh ? "剩余用量" : "Remaining Quota" }
    static var usedQuotaDisplay: String { zh ? "已用额度" : "Used Quota" }
    static var remainingShort: String { zh ? "剩余" : "Remaining" }
    static var usedShort: String { zh ? "已用" : "Used" }
    static var quotaSortSettingsTitle: String { zh ? "用量排序参数" : "Quota Sort Parameters" }
    static var quotaSortSettingsHint: String {
        zh
            ? "排序仍按用量规则计算，正在使用和运行中的账号优先。这里仅调整套餐权重换算：默认 free=1、plus=10、pro=plus×10（可调 5 到 30）、team=plus×1.5。"
            : "Sorting still follows quota usage rules, with active and running accounts first. These controls only adjust plan weighting: by default free=1, plus=10, pro=plus×10 (adjustable from 5 to 30), and team=plus×1.5."
    }
    static var quotaSortPlusWeightTitle: String { zh ? "Plus 相对 Free 权重" : "Plus Weight vs Free" }
    static var quotaSortProRatioTitle: String { zh ? "Pro 相对 Plus 倍数" : "Pro Ratio vs Plus" }
    static var quotaSortTeamRatioTitle: String { zh ? "Team 相对 Plus 倍数" : "Team Ratio vs Plus" }
    static func quotaSortPlusWeightValue(_ value: Double) -> String {
        let formatted = String(format: "%.1f", value)
        return zh ? "plus=\(formatted)" : "plus=\(formatted)"
    }
    static func quotaSortProRatioValue(_ value: Double, absoluteProWeight: Double) -> String {
        let ratio = String(format: "%.1f", value)
        let proWeight = String(format: "%.1f", absoluteProWeight)
        return zh ? "pro=plus×\(ratio) (= \(proWeight))" : "pro=plus×\(ratio) (= \(proWeight))"
    }
    static func quotaSortTeamRatioValue(_ value: Double, absoluteTeamWeight: Double) -> String {
        let ratio = String(format: "%.1f", value)
        let teamWeight = String(format: "%.1f", absoluteTeamWeight)
        return zh ? "team=plus×\(ratio) (= \(teamWeight))" : "team=plus×\(ratio) (= \(teamWeight))"
    }
    static var accountOrderTitle: String { zh ? "OpenAI 账号顺序" : "OpenAI Account Order" }
    static var accountOrderingModeTitle: String { zh ? "账号排序方式" : "Account Ordering" }
    static var accountOrderingModeHint: String {
        zh
            ? "可在“按用量排序”和“按手动顺序”之间切换。只有切到手动顺序时，下面的手动排序才会影响主菜单展示。"
            : "Switch between quota-based sorting and manual order. The manual list below only affects the main menu when manual order is selected."
    }
    static var accountOrderingModeQuotaSort: String { zh ? "按用量排序" : "Sort by Quota" }
    static var accountOrderingModeQuotaSortHint: String {
        zh ? "直接按当前用量权重排序，剩余可用更多的账号优先。" : "Use the current quota-weighted ranking directly, with accounts that have more usable quota first."
    }
    static var accountOrderingModeManual: String { zh ? "按手动顺序" : "Manual Order" }
    static var accountOrderingModeManualHint: String {
        zh ? "按你保存的手动顺序展示；active / running 账号仍会临时浮顶。" : "Use your saved manual order for display; active and running accounts still float to the top temporarily."
    }
    static var accountOrderHint: String {
        zh
            ? "这里定义手动顺序。只有在上方选了“按手动顺序”后它才生效；active / running 账号仍会临时浮顶。"
            : "This defines the manual order. It only takes effect when \"Manual Order\" is selected above, and active/running accounts still float to the top."
    }
    static var accountOrderInactiveHint: String {
        zh ? "当前按用量排序；你仍可预先调整手动顺序，等切到“按手动顺序”后再生效。" : "Quota sorting is currently active. You can still prepare the manual order below, and it will apply once you switch to Manual Order."
    }
    static var noOpenAIAccountsForOrdering: String { zh ? "当前没有可排序的 OpenAI 账号。" : "There are no OpenAI accounts to reorder." }
    static var moveUp: String { zh ? "上移" : "Move Up" }
    static var moveDown: String { zh ? "下移" : "Move Down" }
    static var manualActivationBehaviorTitle: String { zh ? "手动点击 OpenAI 账号时" : "When Manually Clicking an OpenAI Account" }
    static var manualActivationBehaviorHint: String {
        zh
            ? "只影响 OpenAI OAuth 账号的手动点击，不会扩展到 custom provider。"
            : "This only affects manual clicks on OpenAI OAuth accounts and does not extend to custom providers."
    }
    static var manualActivationUpdateConfigOnly: String { zh ? "只改默认目标" : "Default Target Only" }
    static var manualActivationUpdateConfigOnlyHint: String {
        zh ? "只更新 future default target；当前运行中的 thread 不保证切换。" : "Only updates the future default target; running threads are not guaranteed to switch."
    }
    static var manualActivationLaunchNewInstance: String { zh ? "新开实例" : "Launch New Instance" }
    static var manualActivationLaunchNewInstanceHint: String {
        zh
            ? "更新默认目标后立刻拉起新的 Codex App 实例；已在运行的 Codex 实例会继续保留。"
            : "Update the default target and immediately launch a new Codex App instance. Already-running Codex instances stay open."
    }
    static var manualActivationUpdateConfigOnlyOneTime: String { zh ? "只改默认目标（本次）" : "Default Target Only (This Time)" }
    static var manualActivationLaunchNewInstanceOneTime: String { zh ? "新开实例（本次）" : "Launch New Instance (This Time)" }
    static var manualActivationSetDefaultTargetAction: String { zh ? "设为默认" : "Set Default" }
    static var manualActivationLaunchInstanceAction: String { zh ? "新开实例" : "Launch Instance" }
    static var accountServiceTierTitle: String { zh ? "请求速度" : "Request Speed" }
    static var accountServiceTierHint: String {
        zh
            ? "写入当前应用范围内的 native Codex config.toml。Standard 不写 service_tier；Fast 会写入 service_tier = \"fast\"。启用 API 服务时也会沿用该配置。"
            : "Writes to the native Codex config.toml targets selected by Activation Scope. Standard omits service_tier; Fast writes service_tier = \"fast\". The same setting is reused when the API service is enabled."
    }
    static var accountServiceTierStandard: String { zh ? "标准" : "Standard" }
    static var accountServiceTierFast: String { zh ? "快速" : "Fast" }
    static var manualSwitchDefaultTargetUpdatedTitle: String {
        zh ? "默认目标已更新" : "Default target updated"
    }
    static func manualSwitchDefaultTargetUpdatedDetail(_ target: String?) -> String {
        if let target, target.isEmpty == false {
            return zh
                ? "后续新请求默认走 \(target)；当前运行中的 thread 不保证切换。"
                : "New requests now default to \(target); running threads are not guaranteed to switch."
        }
        return zh
            ? "后续新请求会使用新的默认目标；当前运行中的 thread 不保证切换。"
            : "New requests will use the new default target; running threads are not guaranteed to switch."
    }
    static var manualSwitchLaunchedInstanceTitle: String {
        zh ? "默认目标已更新并已新开实例" : "Default target updated and new instance launched"
    }
    static func manualSwitchLaunchedInstanceDetail(_ target: String?) -> String {
        if let target, target.isEmpty == false {
            return zh
                ? "新的 Codex 实例会使用 \(target)；已在运行的实例会继续保留，现有 thread 也不会被接管。"
                : "The new Codex instance will use \(target); existing instances stay open, and running threads keep their current target."
        }
        return zh
            ? "新的 Codex 实例会使用新的默认目标；已在运行的实例会继续保留，现有 thread 也不会被接管。"
            : "The new Codex instance will use the new default target; existing instances stay open, and running threads keep their current target."
    }
    static var manualSwitchImmediateEffectHint: String {
        zh ? "如要立刻生效，请新开实例。" : "Launch a new instance if you need it to take effect immediately."
    }
    static var accountActivationScopeTitle: String { zh ? "应用范围" : "Activation Scope" }
    static var accountActivationScopeHint: String {
        zh
            ? "控制 API 服务、OAuth 与 provider 启用时，会把 native Codex 配置写到哪些 .codex 目录。"
            : "Controls which native Codex `.codex` directories receive synced configuration when API service, OAuth, or providers are activated."
    }
    static var accountActivationScopeGlobal: String { zh ? "Global" : "Global" }
    static var accountActivationScopeSpecificPaths: String { zh ? "指定路径" : "Specific Paths" }
    static var accountActivationScopeGlobalAndSpecificPaths: String { zh ? "Global+指定路径" : "Global + Specific Paths" }
    static var accountActivationScopeGlobalHint: String {
        zh ? "只写入当前用户主目录下的 ~/.codex。" : "Only write to ~/.codex in the current user's home directory."
    }
    static var accountActivationScopeSpecificPathsHint: String {
        zh ? "只写入下方所选根路径内的 .codex。" : "Only write to `.codex` inside the selected root paths below."
    }
    static var accountActivationScopeGlobalAndSpecificPathsHint: String {
        zh ? "同时写入 ~/.codex 与下方所选根路径内的 .codex。" : "Write to both ~/.codex and `.codex` inside the selected root paths below."
    }
    static var accountActivationRootPathsTitle: String { zh ? "激活路径" : "Activation Paths" }
    static var accountActivationRootPathsEmpty: String {
        zh ? "请点击右侧 + 添加至少一个路径。" : "Click + to add at least one path."
    }
    static var accountActivationRootPathPlaceholder: String { zh ? "尚未选择路径" : "No path selected" }
    static var accountActivationRootPathChoose: String { zh ? "选择路径" : "Choose Path" }
    static var accountActivationCodexMissing: String {
        zh ? "未检测到该路径下的 .codex 目录，保存时会按作用域规则创建/写入。" : "No `.codex` directory detected under this path yet; save will create/write it using the selected scope."
    }
    static func accountActivationCodexDetected(_ path: String) -> String {
        zh ? "已检测到 \(path)" : "Detected at \(path)"
    }
    static var accountActivationRootPathsRequired: String {
        zh ? "当前应用范围至少需要一个激活路径。" : "The selected activation scope requires at least one activation path."
    }
    static var save: String { zh ? "保存" : "Save" }
    static var codexAppPathTitle: String { zh ? "文件路径" : "Path" }
    static var codexAppPathHint: String {
        zh
            ? "手动路径优先；路径失效时会自动回退系统探测。有效路径必须是绝对路径、指向 Codex.app，并包含 Contents/Resources/codex。"
            : "A manual path takes priority, but invalid paths fall back to automatic detection. Valid paths must be absolute, point to Codex.app, and include Contents/Resources/codex."
    }
    static var codexAppPathChooseAction: String { zh ? "选择" : "Choose" }
    static var codexAppPathResetAction: String { zh ? "恢复自动探测" : "Use Auto Detection" }
    static var codexAppPathPanelTitle: String { zh ? "选择 Codex.app" : "Choose Codex.app" }
    static var codexAppPathPanelMessage: String {
        zh ? "请选择一个有效的 Codex.app。" : "Choose a valid Codex.app."
    }
    static var codexAppPathEmptyValue: String { zh ? "当前未设置手动路径" : "No manual path selected" }
    static var codexAppPathUsingManualStatus: String { zh ? "使用手动路径" : "Using the manual path" }
    static var codexAppPathInvalidFallbackStatus: String { zh ? "手动路径无效，已回退自动探测" : "Manual path is invalid; falling back to automatic detection" }
    static var codexAppPathAutomaticStatus: String { zh ? "当前使用自动探测" : "Currently using automatic detection" }
    static var codexAppPathInvalidSelection: String {
        zh
            ? "所选路径不是有效的 Codex.app。请确认它是绝对路径、名为 Codex.app，并包含 Contents/Resources/codex。"
            : "The selected path is not a valid Codex.app. Make sure it is an absolute path named Codex.app and includes Contents/Resources/codex."
    }
    static var openAICSVExportPrompt: String { zh ? "导出" : "Export" }
    static var openAICSVImportPrompt: String { zh ? "导入" : "Import" }
    static var noOpenAIAccountsToExport: String {
        zh ? "没有可导出的 OpenAI 账号" : "No OpenAI accounts available to export"
    }
    static func openAICSVExportSucceeded(_ count: Int) -> String {
        zh ? "已导出 \(count) 个 OpenAI 账号到 CSV。" : "Exported \(count) OpenAI account\(count == 1 ? "" : "s") to CSV."
    }
    static func openAICSVImportSucceeded(
        added: Int,
        updated: Int,
        activeChanged: Bool,
        providerChanged: Bool,
        preservedCompatibleProvider: Bool
    ) -> String {
        let prefix = zh
            ? "已导入 OpenAI CSV：新增 \(added) 个，覆盖 \(updated) 个。"
            : "Imported OpenAI CSV: \(added) added, \(updated) updated."
        let suffix: String
        if preservedCompatibleProvider {
            suffix = zh ? " 当前使用 provider 保持不变。" : " The current provider was left unchanged."
        } else if providerChanged {
            suffix = zh ? " 当前 provider 已切换到 OpenAI。" : " The current provider was switched to OpenAI."
        } else if activeChanged {
            suffix = zh ? " 当前 OpenAI 账号已更新。" : " The current OpenAI account was updated."
        } else {
            suffix = zh ? " 当前 active 选择未变化。" : " The current active selection was unchanged."
        }
        return prefix + suffix
    }
    static var openAICSVEmptyFile: String { zh ? "CSV 为空，或只有表头。" : "The CSV is empty or only contains a header." }
    static var openAICSVMissingColumns: String { zh ? "CSV 缺少必需列。" : "The CSV is missing required columns." }
    static var openAICSVUnsupportedVersion: String { zh ? "不支持的 CSV 版本。" : "Unsupported CSV format version." }
    static func openAICSVInvalidRow(_ row: Int) -> String {
        zh ? "CSV 第 \(row) 行格式无效。" : "CSV row \(row) has an invalid format."
    }
    static func openAICSVMissingRequiredValue(_ row: Int) -> String {
        zh ? "CSV 第 \(row) 行缺少必填字段。" : "CSV row \(row) is missing required fields."
    }
    static func openAICSVInvalidAccount(_ row: Int) -> String {
        zh ? "CSV 第 \(row) 行的 token 校验失败。" : "CSV row \(row) failed token validation."
    }
    static func openAICSVAccountIDMismatch(_ row: Int) -> String {
        zh ? "CSV 第 \(row) 行的 account_id 校验失败。" : "CSV row \(row) failed account_id validation."
    }
    static func openAICSVEmailMismatch(_ row: Int) -> String {
        zh ? "CSV 第 \(row) 行的 email 校验失败。" : "CSV row \(row) failed email validation."
    }
    static var openAICSVDuplicateAccounts: String { zh ? "CSV 中存在重复的 account_id。" : "The CSV contains duplicate account_id values." }
    static var openAICSVMultipleActiveAccounts: String { zh ? "CSV 中包含多个 is_active=true 的账号。" : "The CSV contains multiple accounts marked as is_active=true." }
    static func openAICSVInvalidActiveValue(_ row: Int) -> String {
        zh ? "CSV 第 \(row) 行的 is_active 值无效。" : "CSV row \(row) has an invalid is_active value."
    }
    static var quit: String            { zh ? "退出"               : "Quit" }
    static var cancel: String          { zh ? "取消"               : "Cancel" }
    static var copied: String          { zh ? "已复制"             : "Copied" }
    static var justUpdated: String     { zh ? "刚刚更新"            : "Just updated" }

    static func available(_ n: Int, _ total: Int) -> String {
        zh ? "\(n)/\(total) 可用" : "\(n)/\(total) Available"
    }
    static func minutesAgo(_ m: Int) -> String {
        zh ? "\(m) 分钟前更新" : "Updated \(m) min ago"
    }
    static func hoursAgo(_ h: Int) -> String {
        zh ? "\(h) 小时前更新" : "Updated \(h) hr ago"
    }
    // MARK: - AccountRowView
    static var reauth: String          { zh ? "重新授权"     : "Re-authorize" }
    static var useBtn: String          { zh ? "使用"         : "Use" }
    static var switchBtn: String       { useBtn }
    static var tokenExpiredMsg: String { zh ? "Token 已过期，请重新授权" : "Token expired, please re-authorize" }
    static var bannedMsg: String       { zh ? "账号已停用"   : "Account suspended" }
    static var deleteBtn: String       { zh ? "删除"         : "Delete" }
    static var deleteConfirm: String   { zh ? "删除"         : "Delete" }
    static var nextUseTitle: String    { zh ? "下一次使用"   : "Next Use" }
    static var inUseNone: String       { zh ? "未检测到正在使用的 OpenAI 会话" : "No live OpenAI sessions detected" }
    static var runningThreadNone: String { zh ? "未检测到运行中的 OpenAI 线程" : "No running OpenAI threads detected" }
    static var runningThreadUnavailable: String { zh ? "运行中状态不可用" : "Running status unavailable" }
    static var runningThreadUnavailableRuntimeLogMissing: String {
        zh ? "运行中状态不可用（未找到运行日志库）" : "Running status unavailable (runtime log database missing)"
    }
    static var runningThreadUnavailableRuntimeLogUninitialized: String {
        zh ? "运行中状态不可用（运行日志库未初始化）" : "Running status unavailable (runtime logs not initialized)"
    }

    static func inUseSessions(_ count: Int) -> String {
        zh ? "使用中 · \(count) 个会话" : "In Use · \(count) session\(count == 1 ? "" : "s")"
    }

    static func runningThreads(_ count: Int) -> String {
        zh ? "运行 \(count)" : "Running \(count)"
    }

    static func inUseSummary(_ sessions: Int, _ accounts: Int) -> String {
        if zh {
            return "使用中 · \(sessions) 个会话 / \(accounts) 个账号"
        }
        return "In Use · \(sessions) session\(sessions == 1 ? "" : "s") across \(accounts) account\(accounts == 1 ? "" : "s")"
    }

    static func runningThreadSummary(_ threads: Int, _ accounts: Int) -> String {
        if zh {
            return "运行中 · \(threads) 个线程 / \(accounts) 个账号"
        }
        return "Running · \(threads) thread\(threads == 1 ? "" : "s") / \(accounts) account\(accounts == 1 ? "" : "s")"
    }

    static func inUseUnknownSessions(_ count: Int) -> String {
        zh ? "另有 \(count) 个未归因会话" : "\(count) unattributed session\(count == 1 ? "" : "s")"
    }

    static func runningThreadUnknown(_ count: Int) -> String {
        zh ? "另有 \(count) 个未归因线程" : "\(count) unattributed thread\(count == 1 ? "" : "s")"
    }

    static func openAIRouteSummaryCompact(_ value: String) -> String {
        zh ? "约\(value)" : "~\(value)"
    }

    static var delete: String         { zh ? "删除"     : "Delete" }
    static var tokenExpiredHint: String { zh ? "Token 已过期，请重新授权" : "Token expired, please re-authorize" }
    static var accountSuspended: String { zh ? "账号已停用" : "Account suspended" }
    static var weeklyExhausted: String  { zh ? "周额度耗尽" : "Weekly quota exhausted" }
    static var primaryExhausted: String { zh ? "5h 额度耗尽" : "5h quota exhausted" }
    nonisolated static func compactResetDaysHours(_ days: Int, _ hours: Int) -> String {
        zh ? "\(days)天\(hours)时" : "\(days)d \(hours)h"
    }
    nonisolated static func compactResetHoursMinutes(_ hours: Int, _ minutes: Int) -> String {
        zh ? "\(hours)时\(minutes)分" : "\(hours)h \(minutes)m"
    }
    nonisolated static func compactResetMinutes(_ minutes: Int) -> String {
        zh ? "\(minutes)分" : "\(minutes)m"
    }
    nonisolated static var compactResetSoon: String {
        zh ? "1分内" : "<1m"
    }

    // MARK: - TokenAccount status
    static var statusOk: String       { zh ? "正常"     : "OK" }
    static var statusWarning: String  { zh ? "即将用尽" : "Warning" }
    static var statusExceeded: String { zh ? "额度耗尽" : "Exceeded" }
    static var statusBanned: String   { zh ? "已停用"   : "Suspended" }

    // MARK: - Reset countdown
    static var resetSoon: String { zh ? "即将重置" : "Resetting soon" }
    static func resetInMin(_ m: Int) -> String {
        zh ? "\(m) 分钟后重置" : "Resets in \(m) min"
    }
    static func resetInHr(_ h: Int, _ m: Int) -> String {
        zh ? "\(h) 小时 \(m) 分后重置" : "Resets in \(h)h \(m)m"
    }
    static func resetInDay(_ d: Int, _ h: Int) -> String {
        zh ? "\(d) 天 \(h) 小时后重置" : "Resets in \(d)d \(h)h"
    }
}
