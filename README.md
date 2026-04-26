# Codexkit

Codexkit 是一个 macOS 菜单栏应用，用来在本机管理 OpenAI OAuth 账号、自定义 API provider、OpenRouter，以及内置的 CLIProxyAPI 本地服务。

它不是 SDK，也不是只包了一层界面的启动器。Codexkit 会读写本地配置、切换当前账号或 provider、启动本地 API Service，并在需要时把选择同步到原生 Codex 配置里。也正因为会碰到这些本地状态，README 里只写已经接上线或有明确验证路径的能力。

## 下载与安装

最新正式版：`v0.2.0`

请从 GitHub Release 下载与你机器架构匹配的包：

- Apple Silicon：`codexkit-0.2.0-macOS-arm64.dmg` 或 `.zip`
- Intel Mac：`codexkit-0.2.0-macOS-x86_64.dmg` 或 `.zip`

推荐用 `.dmg`：打开后把 `Codexkit.app` 拖到 `Applications`。如果 macOS 提示“无法验证开发者”，这是因为当前开源分发包使用 ad-hoc codesign，还没有接 Apple Developer ID 签名和 notarization。可以用下面两种方式之一打开：

1. 在 Finder 里右键 `Codexkit.app`，选择 `Open`。
2. 如果你确认包来自本仓库 Release，也可以移除 quarantine 标记：

```bash
xattr -dr com.apple.quarantine /Applications/Codexkit.app
```

这不是在绕过安全建议。意思只是：当前包是开源构建产物，不伪装成已 notarize 的商业分发包。介意这一点的话，建议从源码自行构建。

## 当前能做什么

### 菜单栏控制面

Codexkit 的主入口是菜单栏。你可以在一个地方查看账号、provider、API Service 状态，并进入设置、日志、更新等页面。

相关实现主要在：

- `Sources/CodexkitApp/Views/MenuBarView.swift`
- `Sources/CodexkitApp/Services/MenuBarStatusItemController.swift`
- `Sources/CodexkitApp/Models/MenuBarStatusItemPresentation.swift`

### OpenAI OAuth 账号管理

Codexkit 可以管理本机 OpenAI OAuth 账号，包括导入、更新、删除、激活、默认目标切换、配额窗口展示，以及 refresh / reauth 相关状态。

相关实现主要在：

- `Sources/CodexkitApp/Services/TokenStore.swift`
- `Sources/CodexkitApp/Services/OpenAIOAuthFlowService.swift`
- `Sources/CodexkitApp/Services/OpenAIOAuthRefreshService.swift`
- `Sources/CodexkitApp/Models/OpenAIAccountPresentation.swift`

### Provider 与 OpenRouter

除了 OpenAI OAuth，项目也支持兼容 OpenAI API 的自定义 provider，以及 OpenRouter 的 provider、账号、模型选择。

相关实现主要在：

- `Sources/CodexkitApp/Services/OpenRouterGatewayService.swift`
- `Sources/CodexkitApp/Services/OpenRouterGatewayLeaseStore.swift`
- `Sources/CodexkitApp/Views/CompatibleProviderRowView.swift`
- `Sources/CodexkitApp/Models/CodexBarConfig.swift`

### 内置 CLIProxyAPI 服务

仓库内带有 CLIProxyAPI bundle。Codexkit 可以启动、停止、探测这个本地服务，并把 staged auth export、member accounts、routing strategy、usage / quota snapshot 等状态接到菜单栏和设置页。

相关实现主要在：

- `Sources/CodexkitApp/Services/CLIProxyAPIRuntimeController.swift`
- `Sources/CodexkitApp/Services/CLIProxyAPIService.swift`
- `Sources/CodexkitApp/Services/CLIProxyAPIManagementService.swift`
- `Sources/CodexkitApp/Services/CLIProxyAPIProbeService.swift`

### 原生 Codex 配置同步与恢复

Codexkit 会把当前选中的账号、provider 或 API Service 配置写回到本地 Codex 目标目录。写入前会走备份和托管状态记录；需要退出托管时，也提供恢复路径。

相关实现主要在：

- `Sources/CodexkitApp/Services/CodexSyncService.swift`
- `Sources/CodexkitApp/Services/CodexPaths.swift`
- `Sources/CodexkitApp/Services/CodexBarConfigStore.swift`

## 项目结构

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

大致分层如下：

- `Models/`：配置模型、展示模型、状态枚举、兼容性解码。
- `Services/`：OAuth、token、quota、provider、runtime、native sync 等副作用逻辑。
- `Views/`：菜单栏、设置页、列表行、弹窗和局部交互。
- `Tests/`：目前主要的自动化验证来源。

## 本地开发

进入仓库：

```bash
cd Codexkit
```

构建：

```bash
swift build
```

运行：

```bash
swift run Codexkit
```

测试建议先用串行模式。当前项目里有一些和运行时状态、文件系统、进程探测相关的测试，串行结果更稳定：

```bash
swift test --no-parallel
```

常用的重点测试：

```bash
swift test --no-parallel --filter AppLifecycleDiagnosticsTests
swift test --no-parallel --filter SettingsWindowCoordinatorTests
swift test --no-parallel --filter CLIProxyAPIRuntimeControllerTests
swift test --no-parallel --filter CLIProxyAPIProbeServiceTests
swift test --no-parallel --filter TokenStoreGatewayLifecycleTests
swift test --no-parallel --filter CodexSyncServiceTests
```

## 本地打包

本地可以生成接近 Release 形态的 `.app`、`.dmg` 和 `.zip`：

```bash
scripts/release/build_local_release.sh
```

可用环境变量覆盖版本和 bundle identifier：

```bash
CODEXKIT_RELEASE_VERSION=0.2.0-local \
CODEXKIT_BUNDLE_IDENTIFIER=com.example.codexkit \
scripts/release/build_local_release.sh
```

默认输出到 `dist/release/`：

- `Codexkit.app`
- `codexkit-<version>-macOS-<arch>.dmg`
- `codexkit-<version>-macOS-<arch>.zip`
- `release-manifest.json`

本地打包只适合开发验收。正式发布以 GitHub Actions 产物为准。

## GitHub Actions 发布

`.github/workflows/release.yml` 负责正式打包。推送 `v*` tag 会自动发布 GitHub Release。

发布流程会做这些事：

1. 解析版本号和 Release 元数据。
2. 在 GitHub macOS runner 上跑串行 Swift 测试。
3. 分别在 Apple Silicon 和 Intel runner 上打包。
4. 上传 `.dmg` / `.zip` 到 GitHub Release。

例如发布 `v0.2.0`：

```bash
git tag v0.2.0
git push origin v0.2.0
```

工作流成功后，Release 里应出现四个资产：

- `codexkit-0.2.0-macOS-arm64.dmg`
- `codexkit-0.2.0-macOS-arm64.zip`
- `codexkit-0.2.0-macOS-x86_64.dmg`
- `codexkit-0.2.0-macOS-x86_64.zip`

## 验收口径

对正式包来说，本地 `swift build` 或本地打包通过都不算最终验收。真正的验收至少要看这几项：

- GitHub Actions `Package and Release` workflow 成功。
- `Verify tests`、`Package arm64`、`Package x86_64`、`Publish GitHub Release` 全部通过。
- Release 页面存在对应版本的 `.dmg` / `.zip`。
- 从 Release 下载真实包，挂载或解压后能启动 `Codexkit.app`。

## 已知边界

- 当前发布包使用 ad-hoc codesign，没有 notarization。
- 菜单栏真实交互还没有完整 UI automation 覆盖；很多保障来自单元和集成测试。
- Swift 6 并发隔离相关 warning 还没有完全清完。
- `MenuBarView.swift`、`TokenStore.swift`、`SettingsWindowCoordinator.swift`、`CodexBarConfig.swift` 仍是后续架构收敛的重点。
- API Service readiness 不能只看设置项是否存在。涉及真实路由启用、probe、失败回滚和 runtime recovery 的路径，仍应以测试和真实运行证据为准。

## 不是什么

- 不是通用 API SDK。
- 不是 Mac App Store 分发包。
- 不是已经 notarize 的商业安装包。
- `../forks/` 只是参考源码，不是当前产品目录。
