# 独立音频试听预览准备

此分支的 Web 预设启用 Godot 内置 PWA，并带 `audio_preview` 特性。预览使用独立的 `audio_preview_progress.cfg` 和 `audio_preview_settings.cfg`，避免在同源正式试玩中覆盖进度或设置。原生编辑器和不带该特性的构建仍使用原有路径。

## 发布方式与当前阻塞

现有 GitHub Pages 工作流每次替换整个站点；不能把两次部署当作两个独立站点。选定候选是：完整保留当前正式部署产物，在其目录中新加 `preview/audio/` 试听入口，游戏放在 `preview/audio/game/`。不合 master，不改正式文件，不新增仓库/服务/权限。

已通过 GitHub 连接器读取最近成功部署的日志并下载实际 Pages 产物：

- workflow run `36684685773`，部署 job `109787865927`，正式 SHA `f96de18049940f61482c8129902b3599cae3d179`。
- artifact `11083695867`，ZIP SHA-256 `9e22825b379f78c3e224735b9689eb76d2b4235a383350fe71a8ba18a6f2e142`，实算一致。
- 原始 tar 包有 10 个文件，包括 `.nojekyll`；保留核验应直接以 tar 内文件为准，不能把本地 Godot 生成的 `.import` 旁文件当成正式内容。

**尚未发布。** 当前执行环境请求正式 HTTPS 入口返回 403，网页工具也无法读取；GitHub CLI 的 Pages API 返回 Forbidden，连接器通用 GET 不支持 Pages/环境管理端点。因此当前不能确认最新线上内容与上述产物逐文件一致，也不能确认集成分支是否被现有 Pages 环境允许部署。未修改环境限制、凭据或权限，未触发替换部署。

解除阻塞后，需在能访问站点及现有部署环境的授权执行环境内：

1. 重新确认最新部署 SHA/artifact，读取完整产物并逐文件对照正式 HTTPS 文件。
2. 只在 `preview/audio/` 下新增文件；部署前比较正式文件路径和 SHA-256 全部相同，并再次检查正式部署未发生变化。
3. 使用现有部署权限发布组合产物；不能放宽 Pages 环境分支限制。若限制不允许，应停止并报告。
4. 部署后逐文件重查正式内容，以及预览 SHA、HTTPS 资源、worker 作用域与手机播放。

## 隔离与验证

- worker 位于 `preview/audio/game/`，使用默认同目录作用域，不设置 `Service-Worker-Allowed: /`。
- worker 缓存前缀包含 `self.registration.scope`；旧缓存清理只匹配同一预览作用域，不能清理同源正式版/其他预览的缓存。
- 内置 PWA 缓存、manifest 和资源版本引用一起更新；首次等待 worker ready 后再自动重载。
- 本地组合站点已验证：预览隔离=true、SAB 可用、完整 Wwise 时长/结束回调；返回正式根路径后 `navigator.serviceWorker.controller=null`。
- 本地浏览器按既有授权仅访问 localhost，未将禁用沙箱的授权用于线上浏览。
- 构建脚本创建 `build/.gdignore`，避免将本地核验文件导入或打入游戏包。

试听入口的说明为：打开媒体音量、横屏体验；首次加载可能自动刷新一次；进入游戏后轻点画面解锁音频，可在设置中调节音量并尝试互动。当前音乐/音效为测试素材。本地回调与波形不能替代手机扬声器听感。

准备包和逐文件清单位于工作区 `build/qa/preview-publish/`，不提交构建产物。确切构建 SHA 记录在预览的 `preview-info.json` 与 `preservation-manifest.json`。线上试听链接只有部署和核验成功后才能提供；本文件中的预览路径不是已上线承诺。
