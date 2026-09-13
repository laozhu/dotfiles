# Pi Agent 与 Claude 配置声明式管理设计

## 背景

本仓库已经通过 Home Manager 管理 Pi 的 `settings.json`、Rose Pine Moon
主题和 `terminal-status-title.js`，并通过一个共享的 `home/AGENTS.md` 为
Claude、Codex 和 OpenCode 提供统一规则。参考仓库近期增加了 Pi 第三方包
声明和 Claude 原生 `@AGENTS.md` 导入方式。

本次变更采用这些适合当前仓库的部分，同时保留已有的 Orca 标题栏兼容
处理、细粒度文件所有权和本地运行时数据边界。

## 目标

1. 用 Claude 原生 `@AGENTS.md` 导入替代直接把
   `~/.claude/CLAUDE.md` 链接到共享规则文件，避免误写 CLAUDE.md 时覆盖
   AGENTS.md。
2. 由 Home Manager 管理 Pi 的声明式 settings、主题和仓库维护的本地插件。
3. 通过 Pi 的 settings 精确固定并自动安装：
   - `npm:pi-web-access@0.29.0`
   - `npm:@ryan_nookpi/pi-extension-codex-fast-mode@0.2.7`
4. 保持 Pi 的凭证、会话、缓存和 npm 下载目录由 Pi 自己管理。
5. 在不激活当前系统的情况下验证配置和 Pi 0.83 兼容性。

## 非目标

- 不引入 Pi Calm。
- 不安装 `ffmpeg` 或 `yt-dlp`。
- 不单独安装 `unpdf`。它是 Pi Web Access 的 npm 依赖，由 Pi 的包管理器
  自动处理。
- 不加入 upstream `models.json` 中的 272000 上下文窗口覆盖。
- 不接管整个 `~/.pi/agent`、`themes` 或 `extensions` 目录。
- 不管理 Pi 的认证信息、API 密钥、搜索服务配置、会话、缓存或下载后的
  npm 包源码。
- 实现阶段不运行 `rebuild.sh`，不改变当前正在运行的应用。

## 设计

### Claude 规则导入

仓库新增 `home/CLAUDE.md`，内容只包含说明注释和：

```md
@AGENTS.md
```

Home Manager 分别管理：

- `~/.claude/CLAUDE.md`，指向仓库的 `home/CLAUDE.md`。
- `~/.claude/AGENTS.md`，指向仓库唯一的 `home/AGENTS.md`。
- `~/.codex/AGENTS.md` 与 `~/.config/opencode/AGENTS.md`，继续直接指向
  `home/AGENTS.md`。

这样即使某个工具错误写入 CLAUDE.md，受影响的也只是可恢复的导入文件，
不会直接覆盖共享规则。

### Pi settings 与第三方包

`home/.pi/agent/settings.json` 继续由 Home Manager 映射到
`~/.pi/agent/settings.json`，并增加精确版本的 `packages` 数组。

Home Manager 只管理包声明。Pi 启动后读取 settings，并将包及其 npm 依赖
安装到 Pi 自己的运行时目录。该运行时目录不进入 Git，也不由 Home Manager
接管。

Pi Web Access 的网页搜索、URL、GitHub 和 PDF 功能不需要额外系统包。
`unpdf` 作为 npm 依赖随包安装。`ffmpeg` 与 `yt-dlp` 只用于视频帧提取，
本次不安装。

Codex Fast Mode 没有独立的系统依赖，其 Pi peer dependencies 由现有 Pi
安装提供。

### Pi 主题与本地插件

继续细粒度管理以下资源：

- `~/.pi/agent/themes/rose-pine-moon.json`
- `~/.pi/agent/extensions/terminal-status-title.js`

不采用 upstream 对整个 themes 和 extensions 父目录的接管。这样既能复现
仓库资源，也允许用户在本机保留其他不受仓库管理的 Pi 资源。

`terminal-status-title.js` 中现有的 `ORCA_PANE_KEY` 防护必须保留，避免与
Orca 自己的标题栏状态发生竞争。

## 安全与隐私边界

- 两个 npm 包都以当前用户权限运行，必须使用精确版本，不能使用浮动版本。
- Pi Web Access 可以访问网络，并可按用户后续配置调用第三方搜索服务。
  本次不创建 API 密钥、不启用浏览器 Cookie 读取，也不新增搜索服务配置。
- `home/.pi/agent/settings.json` 不包含凭证。
- `~/.pi/agent/auth.json`、搜索服务本地配置和 Pi 运行时目录继续保持未跟踪。
- 现有未跟踪文件 `home/.claude/settings.json.bak` 不属于本次变更，不能修改
  或提交。

## 测试策略

实现采用测试优先方式：

1. 扩展 Pi 配置测试，要求 settings 包含两个精确 pin，且不包含 Calm、
   compaction 包或浮动 npm 版本。
2. 扩展 Home Manager 映射测试，验证 settings、主题、terminal title、
   Claude wrapper 和 Claude AGENTS 目标均被声明。
3. 验证 CLAUDE.md 是普通导入文件，而不是直接链接到 AGENTS.md 的配置。
4. 验证 Pi 运行时目录和凭证没有被 Home Manager 接管。
5. 在隔离的临时 HOME 中让现有 Pi 0.83 读取配置，验证两个包可以解析和
   加载，不使用真实凭证、不改变当前用户状态。
6. 运行仓库完整测试套件和 `git diff --check`。

## 应用方式

实现和测试通过后先提交代码，但不自动执行 `rebuild.sh`。用户随后在合适的
时间运行 rebuild，使 Home Manager 更新链接。Pi 下次启动时根据 settings
安装缺少的精确版本包。
