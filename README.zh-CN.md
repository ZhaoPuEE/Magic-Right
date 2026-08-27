# Super Right

[English](README.md)

<p align="center"><img src="Design/AppIcon-master.png" width="160" alt="Super Right 图标"></p>

Super Right 是一款原生、开源的 macOS 工具，把 Finder 右键菜单变成面向开发工作和日常文件操作的快捷入口。它由轻量的 Finder Sync 扩展和菜单栏宿主 App 组成；设置、权限、历史记录以及耗时操作都由宿主 App 负责。

> Super Right 正在开发中。下列内容是 V1 产品范围，目前尚无稳定公开版本。

## 当前原型（0.1.0）

已经实现并通过源码级验证：

- 原生菜单栏 App、工具箱设置界面和 Finder Sync 扩展工程。
- 按 Bundle ID 动态发现常见编辑器、终端、IDE 和 Git 客户端，也可手工添加任意 `.app`。
- Finder 中以结构化参数打开 Terminal、Tabby、Visual Studio Code、Zed 等 App。
- Markdown、TXT、RTF、XML、JSON、YAML、`.gitignore` 七种安全新建预制，自动避让重名且绝不覆盖。
- 本地智能目录：2 秒停留阈值、30 分钟去重、30 天半衰期，以及固定 / 常用 / 最近、搜索、改名、排除和清空。
- 复制绝对路径、`file://` URL 和 Shell 安全路径。
- 原创 AppIcon、菜单栏 Template Icon、构建验证和 DMG 打包脚本。

尚未实现的是 Office/自定义模板、Git 动作、移动/复制/撤销、压缩解压和文件信息等后续 V1 模块。当前测试 DMG 没有 Developer ID 签名或公证；Finder 扩展的真实安装、跨进程 App Group 和任意目录写入仍需在 Xcode 选择 Personal Team 后进行用户可见验证。

## 为什么做 Super Right

- 在 Terminal、Tabby、Visual Studio Code、Zed 以及其他已安装 App 中打开选中的文件或目录。
- 动态发现后来安装的 App，不依赖写死的 `/Applications` 路径。
- 在本地学习常用目录，提供“固定 / 常用 / 最近”三类快速入口。
- 用内置或用户导入的模板创建真实文件，包括结构合法的 Office 文档。
- 把路径、Git、压缩、移动、复制和文件检查等高频能力放到当前选择旁边。
- Finder 扩展只做轻量工作；文件操作交给宿主 App，禁止静默覆盖，并保留可恢复的操作记录。
- 采用 MIT License，全部功能免费开源，不设置订阅墙。

## V1 计划

### 用任意 App 打开

Super Right 通过 Bundle ID 记录应用，并在动作执行时通过 Launch Services 解析应用当前位置。以后新安装 Zed 等 App，会先出现在设置的“可用应用”中；只有用户启用后才进入 Finder 右键。App 卸载后会自动从菜单隐藏，以相同 Bundle ID 重装时可恢复原有设置。

已知 App 可以使用专门适配的结构化启动参数；其他 App 使用 macOS 标准打开机制，或由用户手工选择任意 `.app`。Super Right 不执行用户提供的 Shell 命令字符串。

### 智能常用目录

菜单栏和 Finder 菜单提供三类本地列表：

- **固定**：用户明确固定的目录。
- **常用**：根据访问频率和最近程度排序的目录。
- **最近**：最近观察到的目录。

目录学习只记录路径和时间，不遍历目录内容，也不会把历史发送到 Mac 之外。用户可以暂停学习、排除路径、改名或固定条目、删除单条记录，或清空完整历史。

### Finder 动作

- 新建 Markdown、文本、RTF、XML、JSON、YAML、`.gitignore`、DOCX、XLSX、PPTX，以及自定义模板文件。
- 复制绝对路径、Shell 安全路径、`file://` URL 和 Git 根目录相对路径。
- 打开 Git 仓库根目录和远程页面；仅在适用的目录显示 Git 动作。
- 防冲突的移动/复制目标，以及撤销最近一次移动。
- 创建 ZIP、tar、tar.gz；先在临时位置解压并通过路径安全校验。
- 查看文件信息并按需计算哈希。

动作按“新建文件、移动到、复制到、目录、压缩与解压、打开方式、Git、工具”分组。用户可开关、排序、改名，把动作收进统一的 Super Right 子菜单，也可将少量高频动作提到外层。

### 工具箱控制中心

宿主 App 同时是 Finder 功能的控制中心，侧栏包含**总览、打开方式、新建文件与模板、常用目录、路径与 Git、文件工具、压缩与解压、设置**。每项能力都可启用、排序、改名，并单独决定是否进入 Finder 菜单。

首次配置提供三个可继续编辑的预设：

- **Developer（开发）**：突出编辑器、终端、路径与 Git。
- **File（文件）**：突出新建、目标目录、压缩和安全文件操作。
- **All（全部）**：启用当前支持的完整工具集合。

应用预设只会更新可编辑配置，不会把用户锁进固定模式。Super Right 可以研究成熟右键工具的交互规律，但代码、界面文案、图标、模板和其他品牌资产必须原创，不复刻竞品受保护的资产。

## 平台与设计

- macOS 15 或更高版本
- Swift 6、SwiftUI 与 AppKit
- 菜单栏宿主 App + Finder Sync 扩展
- 通过 App Group 共享状态
- 本地使用 DMG 分发；公开发行前必须完成 Developer ID 签名和 Apple 公证

原创图标方向为 macOS 圆角方形：石墨灰半透明玻璃、电光青高亮、三行右键菜单，中间高亮行嵌入 `>_`。菜单栏使用简化的单色 Template Icon。品牌形象不使用鼠标、闪电或 `SR` 字母；发布前需检查 16 至 1024 像素、深浅色和系统着色状态。

产品约束详见[架构](docs/ARCHITECTURE.md)、[隐私](docs/PRIVACY.md)和[权限](docs/PERMISSIONS.md)。

## 从源码构建

在 Xcode 中打开 `SuperRight.xcodeproj` 并选择 `SuperRight` scheme，或运行：

```sh
./scripts/verify-project.sh
```

验证脚本会在仓库根目录或 `Packages` 下一层存在 `Package.swift` 时运行 Swift Package 测试，然后列出 Xcode scheme，并使用临时 SwiftPM 缓存和 Derived Data 执行不签名的 Debug 构建。可用第一个参数或 `SUPER_RIGHT_SCHEME` 指定其他 scheme。

开发签名、Finder 扩展启用、Release 构建、DMG 打包和正式公证边界详见[构建与发布](docs/BUILDING.md)。

把已经构建的 App 打包成不会覆盖已有文件的 DMG：

```sh
./scripts/create-dmg.sh "/path/to/Super Right.app" ./dist
```

产物内含 App 和指向 `/Applications` 的软链接，可拖拽安装。脚本不会处理签名或公证。

## 项目原则

- 保持 Finder 响应迅速，耗时操作必须交给宿主 App。
- 用 Bundle ID 表示外部 App，而不是保存固定路径。
- 路径只能作为结构化参数传递，禁止拼接进 Shell 命令。
- 绝不静默覆盖用户文件。
- 目录学习数据只留在本机，且不读取目录内容。
- 构建产物、DMG、证书、凭据和公证配置不得进入 Git。
- 可以把竞品行为作为产品调研依据，但实现、文案、图标和内置资产必须保持原创。

## 参与开发

使用 `main` 分支，保持改动小且便于审查，为共享核心逻辑补充测试，并在提交改动前运行 `./scripts/verify-project.sh`。请勿提交签名材料或生成的发布产物。

版本进度见 [CHANGELOG](CHANGELOG.md)。

## 许可证

Super Right 使用 [MIT License](LICENSE)。
