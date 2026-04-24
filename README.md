# Codexkit

Codexkit 是一个 **macOS 菜单栏应用**，用于把多种上游能力收敛到同一个本地控制面里：

- OpenAI OAuth 账号管理与切换
- 兼容 OpenAI API 的自定义 provider 管理
- OpenRouter provider / model 管理
- 内置 `CLIProxyAPI`（API Service）运行时的启停、观测、配额刷新与路由配置
- 本地原生 Codex 配置的同步、接管与恢复

它不是一个通用 SDK，也不是一个简单的 UI 壳。当前代码已经覆盖 **菜单栏状态展示、配置持久化、运行时编排、本地文件写回、账号/路由切换** 这些真实产品职责。

---

## 当前状态

- 平台要求：`macOS 14+`
- 构建方式：Swift Package Manager
- 可执行目标：`Codexkit`
- 内置资源：`Bundled/CLIProxyAPIServiceBundle`
- 当前验证结果（2026-04-22，本地串行执行）：
  - `swift test --package-path Codexkit --no-parallel`
  - **串行全量测试通过（基于当时工作树）**

> 说明：当前仓库能提供较强的单元/集成测试证据，但**尚未看到独立的 UI automation / E2E harness**。因此 README 中对“能力”的描述会尽量基于已验证事实，不把未跑通的 GUI 场景包装成完全闭环。

---

## 核心能力

### 1. 菜单栏统一控制面
应用的主入口是菜单栏，而不是传统主窗口。当前实现已经具备：

- 菜单栏图标与状态展示
- OpenAI 账号分组与配额可视化
- Provider / OpenRouter 列表与切换入口
- API Service 卡片、状态、配额与日志/仪表板跳转
- 设置窗口、更新入口、语言切换等全局操作

对应核心实现主要位于：

- `Sources/CodexkitApp/Views/MenuBarView.swift`
- `Sources/CodexkitApp/Services/MenuBarStatusItemController.swift`
- `Sources/CodexkitApp/Models/MenuBarStatusItemPresentation.swift`

### 2. OpenAI OAuth 账号管理
Codexkit 能管理本地 OpenAI OAuth 账号及其相关状态，包括：

- 账号导入 / 更新 / 删除
- 手动激活与默认目标切换
- 使用量展示（5h / 7d 等窗口）
- token 生命周期相关元数据同步
- reauth / refresh / fallback 辅助逻辑

核心实现位于：

- `Sources/CodexkitApp/Services/TokenStore.swift`
- `Sources/CodexkitApp/Services/OpenAIOAuthFlowService.swift`
- `Sources/CodexkitApp/Services/OpenAIOAuthRefreshService.swift`
- `Sources/CodexkitApp/Models/OpenAIAccountPresentation.swift`

### 3. 兼容 provider / OpenRouter 管理
除 OpenAI OAuth 外，项目还支持：

- 自定义兼容 provider 的账号与路由配置
- OpenRouter provider、账号与模型选择
- gateway lease / model catalog / active selection 协调

核心实现位于：

- `Sources/CodexkitApp/Services/OpenRouterGatewayService.swift`
- `Sources/CodexkitApp/Services/OpenRouterGatewayLeaseStore.swift`
- `Sources/CodexkitApp/Views/CompatibleProviderRowView.swift`
- `Sources/CodexkitApp/Models/CodexBarConfig.swift`

### 4. API Service（CLIProxyAPI）内置运行时
项目内置了 `CLIProxyAPI` bundle，并在菜单与设置中提供完整的运行时控制面。当前代码包含：

- 启动 / 停止本地 API Service
- staged auth export 与运行时配置写入
- health check、auth files、usage、quota snapshot 回读
- selected member accounts / restrict-free / routing strategy 等设置
- 设置页中的 overview / dashboard / logs 分页

核心实现位于：

- `Sources/CodexkitApp/Services/CLIProxyAPIRuntimeController.swift`
- `Sources/CodexkitApp/Services/CLIProxyAPIService.swift`
- `Sources/CodexkitApp/Services/CLIProxyAPIManagementService.swift`
- `Sources/CodexkitApp/Services/CLIProxyAPIProbeService.swift`

### 5. 原生 Codex 配置接管与恢复
Codexkit 不只是显示状态，还会把选中的 provider / account / API Service 配置同步到本地原生 Codex 目标目录，并支持显式恢复。当前实现包含：

- 原生目标路径解析
- auth/config 备份与安全写入
- managed state 清理
- native restore
- removed target cleanup

核心实现位于：

- `Sources/CodexkitApp/Services/CodexSyncService.swift`
- `Sources/CodexkitApp/Services/CodexPaths.swift`
- `Sources/CodexkitApp/Services/CodexBarConfigStore.swift`

补充说明：以上 API Service / runtime / native sync 条目描述的是当前已经接通的能力表面，不应直接解读为 `core-account-flow readiness` 已完全闭环。按照当前 PRD / test-spec，Routing enable 仍需要以真实 `gpt-5.4-mini` probe 作为成功 gate，并在 probe 失败时提供明确的 rollback UX / state；runtime failure 也仍需补齐与 disable path 对齐的统一 auto-recovery / fallback state machine，以及 `runtime_state_root_policy`、`routing_probe_result`、`recovery_trigger`、`recovery_epoch`、`fallback_outcome` 等结构化观测字段与对应测试证据。

---

## 架构概览

当前代码大体可以分成四层：

### App / Lifecycle
负责应用启动、session 记录、单进程运行时拉起。

- `Sources/CodexkitApp/CodexkitApp.swift`
- `Sources/CodexkitApp/Services/AppLifecycleDiagnostics.swift`
- `Sources/CodexkitApp/Services/SingleProcessAppRuntimeController.swift`

### Models / Config
负责配置模型、展示模型、状态枚举和兼容性解码。

- `Sources/CodexkitApp/Models/CodexBarConfig.swift`
- `Sources/CodexkitApp/Models/CLIProxyAPIState.swift`
- `Sources/CodexkitApp/Models/MenuBarStatusItemPresentation.swift`

### Services
负责真正的业务编排和副作用：

- 本地配置持久化
- OAuth / token / quota / sync / runtime
- provider / OpenRouter / API Service / 更新检查

这是当前项目最重的一层，真实业务复杂度主要集中在这里。

### Views
负责菜单栏、设置页和行级交互。

- `Sources/CodexkitApp/Views/MenuBarView.swift`
- `Sources/CodexkitApp/Views/Settings/SettingsWindowView.swift`
- 各类 row / sheet / page views

---

## 目录结构

```text
Codexkit/
├── Package.swift
├── README.md
├── Sources/
│   └── CodexkitApp/
│       ├── CodexkitApp.swift
│       ├── Models/
│       ├── Services/
│       ├── Views/
│       └── Bundled/
│           └── CLIProxyAPIServiceBundle/
└── Tests/
    └── CodexkitAppTests/
```

说明：

- `Models/`：配置、展示、状态和解码兼容层
- `Services/`：业务编排与副作用主战场
- `Views/`：菜单栏和设置界面
- `Tests/`：当前主要验证来源

---

## 本地开发

### 进入目录

```bash
cd Codexkit
```

### 构建

```bash
swift build
```

### 运行

```bash
swift run Codexkit
```

如果你在仓库根目录执行，也可以使用：

```bash
swift run --package-path Codexkit Codexkit
```

### 测试

推荐优先使用串行模式，当前子树已有明确约定：

```bash
swift test --no-parallel
```

如果从仓库根目录执行：

```bash
swift test --package-path Codexkit --no-parallel
```

### 建议优先跑的关键测试

```bash
swift test --package-path Codexkit --no-parallel --filter AppLifecycleDiagnosticsTests
swift test --package-path Codexkit --no-parallel --filter SettingsWindowCoordinatorTests
swift test --package-path Codexkit --no-parallel --filter CLIProxyAPIRuntimeControllerTests
swift test --package-path Codexkit --no-parallel --filter CLIProxyAPIProbeServiceTests
swift test --package-path Codexkit --no-parallel --filter TokenStoreGatewayLifecycleTests
swift test --package-path Codexkit --no-parallel --filter CodexSyncServiceTests
```

### 本地打包（真实包体验收）

当前仓库还没有 notarization / 正式签名闭环，但已经可以生成**真实可安装体验**的本地 release 工件：

```bash
cd Codexkit
scripts/release/build_local_release.sh
```

如需显式版本或 bundle identifier，可通过环境变量覆盖：

```bash
CODEXKIT_RELEASE_VERSION=1.2.0-local \
CODEXKIT_BUNDLE_IDENTIFIER=com.example.codexkit \
scripts/release/build_local_release.sh
```

默认输出到 `dist/release/`，包含：

- `Codexkit.app`
- `codexkit-<version>-macOS-<arch>.dmg`
- `codexkit-<version>-macOS-<arch>.zip`
- `release-manifest.json`

建议验收方式：

1. 双击打开 `dmg`
2. 将 `Codexkit.app` 拖到 `Applications`
3. 从 `Applications` 启动并检查菜单栏入口

说明：

- 脚本会复用 `swift build -c release` 产物，并把 `Codexkit_CodexkitApp.bundle` 资源包一并装入 `.app`
- 默认执行 ad-hoc `codesign`，用于本地体验；这**不等于** Apple Developer 签名 / notarization
- `release-manifest.json` 会记录本次本地产物名与 `sha256`，方便后续接 GitHub Release 或 update feed

### GitHub Actions 打包分发

仓库现在包含 `.github/workflows/release.yml`，用于把本地打包脚本接到 GitHub Actions：

- **Tag 发布**：推送 `v*` tag（例如 `v1.2.0`）后，自动：
  - 运行 `swift test --no-parallel`
  - 在 `macos-15`（Apple Silicon）与 `macos-15-intel` 两个 runner 上分别打包
  - 上传 `dmg` / `zip` 到 GitHub Release
- **手动触发**：在 Actions 页面运行 `Package and Release`
  - 可只做打包（`publish_release = false`）
  - 也可指定 `version` 后直接创建 GitHub Release；若同名 release 已存在，则覆盖同名资产

当前限制：

- CI 分发仍然是 **ad-hoc codesign**，还**没有**接 Apple Developer 签名 / notarization
- 手动触发的 `workflow_dispatch` 只有在工作流文件位于默认分支时才能从 GitHub UI 触发

---

## 当前验证策略

当前项目的“真实可用性”主要通过三类证据支撑：

1. **代码结构证据**：关键链路是否真的接通、真相源是否明确
2. **单元 / 集成测试证据**：例如 settings、API runtime、probe、fallback、native sync
3. **显式限制说明**：没有证据的地方直接写出来，不伪装成“已经完全闭环”

这意味着：

- 账号配置、settings 持久化、API Service runtime、native sync 这类能力已有较强自动化保护
- 菜单栏 UI 的最终交互体验目前仍主要依赖代码级测试和人工验证，而不是独立 UI 测试框架

---

## 当前已知边界与限制

### 1. UI 编排层职责边界过宽
`MenuBarView.swift` 当前体量很大，而且同时承担视图布局、状态计时、账号切换、CSV 导入导出、API Service 控制、窗口/悬浮面板编排等多类职责。它不是“坏掉”，但已经是未来维护和继续扩展时最容易失控的热点之一。

### 2. 状态真相源与编排副作用过于集中
`TokenStore.swift`、`SettingsWindowCoordinator.swift`、`CodexBarConfig.swift` 都承担了较多横切职责。其中 `TokenStore` 已接近高耦合 orchestrator；现阶段这带来了较强的一致性控制，但也提高了后续拆分和扩展成本。

### 3. 仍存在 Swift 6 并发/隔离警告
当前构建依赖 `-strict-concurrency=minimal`，并且核心代码与测试里仍能看到 actor isolation / deprecated API 相关 warning。这说明项目**可以运行和通过测试**，但并发边界还没有完全收干净。

### 4. 缺少独立 UI / e2e 自动化
当前测试很多，但主要是单元/集成测试。对于菜单栏真实交互、窗口行为和复杂联动，仍然缺少更上层的自动化保障。

### 5. Notifications 设置里至少存在一处“死开关”风险
当前工作树里，Notifications 页面已经暴露了 `Critical Delivery Level / 严重通知级别` 这类高级配置；但从现有运行时代码看，通知发送逻辑仍主要根据 `event.severity` 决定投递级别，而不是读取该设置。这意味着相关配置目前更像**已持久化但未完全接线的能力**，在继续对外宣传前应先补齐行为或明确降级为未来能力。

### 6. API Service readiness 文档仍落后于目标验收
README 当前对 API Service / native sync 的描述仍偏实现面总结。在 `gpt-5.4-mini` probe gate、runtime-failure recovery state machine，以及对应 observability fields / test evidence 全部落地前，不应把这些能力描述视为 `core-account-flow readiness` 任务已经完成的验收证据。

---

## 适合谁使用

当前版本更适合：

- 需要在本地统一管理 OpenAI OAuth / provider / OpenRouter / API Service 的高级用户
- 愿意接受 macOS 原生菜单栏工作流的个人开发者
- 希望在本地明确控制配置接管与恢复边界的用户

它暂时**不适合**被描述成“零门槛、零维护成本”的工具型发行版；它更像一个已经具备明确产品方向、且正在收敛架构边界的真实应用。

---

## 后续改进方向

结合当前代码结构，后续最值得优先推进的方向是：

1. 缩小 `MenuBarView` 的编排半径，把展示与动作协调再拆细
2. 继续收敛 `TokenStore` / `SettingsWindowCoordinator` / `CodexBarConfig` 的职责边界
3. 补一层更高阶的 UI / e2e 验证，降低“静态可信但动态未证实”的比例
4. 把当前仍依赖 warning 容忍的并发边界逐步清干净

---

## 非目标

- `../forks/` 是参考源码，不是当前产品目录
- 本目录不是一个通用 API SDK
- 当前 README 不承诺所有 GUI 场景都已具备 e2e 级自动化保证

如果你要继续做正式架构收敛，建议先围绕以下热点展开：

- `Sources/CodexkitApp/Views/MenuBarView.swift`
- `Sources/CodexkitApp/Services/TokenStore.swift`
- `Sources/CodexkitApp/Views/Settings/SettingsWindowCoordinator.swift`
- `Sources/CodexkitApp/Models/CodexBarConfig.swift`
