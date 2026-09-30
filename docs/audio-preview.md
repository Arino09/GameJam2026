# 独立音频试听预览准备

此分支的 Web 预设启用 Godot 内置 PWA，并带 `audio_preview` 特性。预览使用独立的 `audio_preview_progress.cfg` 和 `audio_preview_settings.cfg`，避免在同源正式试玩中覆盖进度或设置。原生编辑器和不带该特性的构建仍使用原有路径。

## 发布方式与当前阻塞

现有 GitHub Pages 工作流每次替换整个站点；不能把两次部署当作两个独立站点。选定候选是：完整保留当前正式部署产物，在其目录中新加 `preview/audio/` 试听入口，游戏放在 `preview/audio/game/`。不合 master，不改正式文件，不新增仓库/服务/权限。

已通过 GitHub 连接器读取最近成功部署的日志并下载实际 Pages 产物：

- workflow run `36684685773`，部署 job `109787865927`，正式 SHA `f96de18049940f61482c8129902b3599cae3d179`。
- artifact `11083695867`，ZIP SHA-256 `9e22825b379f78c3e224735b9689eb76d2b4235a383350fe71a8ba18a6f2e142`，实算一致。
- 原始 tar 包有 10 个文件，包括 `.nojekyll`；保留核验应直接以 tar 内文件为准，不能把本地 Godot 生成的 `.import` 旁文件当成正式内容。

**尚未发布。** 容器网络代理在 CONNECT 阶段返回 403（server: envoy），不是已证明的 GitHub 权限拒绝；容器中的 `gh workflow run` 也在读取 workflow 时被该代理阻断。现已给 integration 分支的现有工作流添加明确手动输入，供已登录的 GitHub 网页触发。Pages 环境的分支保护保持不变，若正常请求被拒绝就停止，不改 policy。

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


## 手动触发入口（integration 分支）

现有工作流网页：<https://github.com/Arino09/GameJam2026/actions/workflows/godot-web.yml>。

点击 **Run workflow**，选择 `integration/audio-pr1-20260930`，将 **publish_audio_preview** 勾选为 true，再触发。该输入为 boolean，默认 false；不接受固定 production SHA/artifact 输入。若界面未显示新字段，不要用默认 master 发布代替；在能连接现有 GitHub API 的授权执行端可使用：

```sh
gh workflow run 355703229 \
  --repo Arino09/GameJam2026 \
  --ref integration/audio-pr1-20260930 \
  -f publish_audio_preview=true
```

实际触发必须同时满足 `workflow_dispatch`、`publish_audio_preview=true`、准确 integration ref 和准确 repository。master 或其他分支勾选此项会被校验任务拒绝；push/PR 永远不走预览发布。输入为 false 的正常 master 流程保持原样。

预览与 master 使用同一 `godot-web-refs/heads/master` 并发组，预览不会取消正在运行的正式发布。master 的原取消行为保留。预览任务使用同一个 `github-pages` environment，仅复用现有的 `contents: read`、`pages: write`、`id-token: write`，没有增加权限种类、PAT、服务、环境或分支策略。

### 自动保护步骤

`tools/publish_audio_preview.py` 只执行 GET，请求拒绝时不切换凭据、不重试匿名接口：

1. 列出 production workflow 的 master runs，按更新时间处理，核对成功部署 job 与日志中的 artifact ID 和 source SHA，避免把仅构建成功或旧产物当正式站点。
2. 若 master 正在发布、master 已超前、最近部署结果不明确、最新产物过期/缺失或日志无法证明来源，立即失败；不回退旧包。
3. 下载最新 artifact，校验 API 提供的 SHA-256，安全解包完整目录。拒绝路径穿越、链接、重复文件和异常体积。
4. 逐文件 SHA-256 对照正式 HTTPS 内容（目录 index 别名也检查；`.nojekyll` 是不公开服务的控制文件，只核验产物与组合包）。只在原产物未占用的 `preview/audio/` 下添加新内容。
5. 记录源 SHA、production run/artifact/digest，以及组合包全部文件清单。上传 Pages artifact 后、部署前再查 production 快照、master SHA、组合包和线上正式文件，任何变化都失败。
6. 通过原 `deploy-pages@v4` 发布完整组合包；然后通过 HTTPS 比较正式文件与所有预览文件，确认包含准确的预览 SHA。后检失败明确标记，不自动回滚覆盖可能更近的正式部署。

**已知权限边界：** [GitHub 产物下载 API](https://docs.github.com/en/rest/actions/artifacts#download-an-artifact)要求细粒度 token 的 `Actions: read`。原 workflow 没有声明它，本次按“不扩权限”要求也未添加。运行时可能在跨 run 元数据/日志/产物读取处得到 403；这是预期的 fail-closed 阻塞，应报告具体失败端点，不自行加权限。没有新增 write 权限。工作流准备完成不代表当前 token 一定能发布。

保护测试包含 18 项：新旧 snapshot 选择、旧 run 重新执行、过期/失败/活跃 production 拒绝、master 超前拒绝、部署日志来源验证、ZIP digest 与路径攻击、正式文件篡改/越界、并发 snapshot 变化、严格触发条件、403 不换凭据、重定向不泄露 API token，以及 HTTPS 哈希和根路径检查。PWA 另有 2 项测试；实际下载的正式 ZIP 和真实预览构建也通过离线校验。
