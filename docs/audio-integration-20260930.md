# 音频 PR #1 集成验证（2026-09-30）

分支：`integration/audio-pr1-20260930`。
基准：`origin/master` 的 `f96de18049940f61482c8129902b3599cae3d179`。
音频 PR：<https://github.com/Arino09/GameJam2026/pull/1>，实取 head `309450ce907184485fb792c439906ffb6523bbd1`。
合并提交：`616b04a8180dfd64759e0f09a6b38887c2c75e15`，保留两个父提交和原作者历史。

## 结论

玩法与导出可集成。默认非 PWA 导出在无隔离头的 Pages 条件下仍静音；后续本地隔离与内置 PWA 候选已验证 Wwise 初始化、回调和波形可用，详见下方“后续本地隔离/PWA 实测”。这不等于线上或真机音频验收通过。没有合回 master，没有部署，没有修改原 PR 或审批状态，没有修改网络安全/凭据或接受新许可。

腾讯需求表网页工具访问失败，未声称重新读取成功。本次按委托中的明确范围处理：音频同学填写已有触发点的 Wwise Event，并生成对应平台 Bank/媒体即可接入；walk/run/region 的空行仍是静音占位。不扩展教程功能。

## 二进制来源核验（先核验，后执行）

上游发布：<https://github.com/alessandrofama/wwise-godot-integration/releases/tag/wwise_v2025.1.9>。
下载文件：`wwise-2025.1.9-for-godot.zip`，官方发布附件公开 SHA-256 与下载实算均为：

```text
5948039d37c420e984ab2a6a5484c66720ba384b9c6ad2c474e12aa2dfbc6536
```

PR 中 Linux editor/debug/release 库及 DSP、四个 Web WASM 都与此 ZIP 逐字节一致。关键执行文件：

| 文件 | SHA-256 |
|---|---|
| Linux editor/profile/libwwise.linux.editor.profile.so | `94355c930748fb7389c8f35fcc32592fee217997f11fb03125ee06489fef19c2` |
| Web release/libwwise.web.template_release.release.nothreads.wasm | `a9d737b69dd90f45c7940701b901147050a189e5935bbf347a851c658608133f` |
| Web debug/libwwise.web.template_debug.profile.nothreads.wasm | `6e8db47bdd2004e5bde13af60a7001301cbd9204afd14b5afcf13029017e0fe9` |

核验了 native 目录 303 个文件：254 个逐字节一致，47 个文本文件仅 CRLF/LF 差异（包括 AudioWorklet JS），其余是 Godot UID 和 `~libwwise.windows.editor.profile.dll` 备份文件。备份 DLL 不在 gdextension 库映射中、未执行，不对其来源作保证。完整比对留在 `build/qa/audio-integration/provenance.json`。上游源码 tag 对应 `da5f19a08c77aac91f1ce9f3db0ff56024ca7277`，用来核实 volume API、编辑器自动 autoload 和 Web 异步 post 行为。

## 冲突与兼容修复

- 唯一合并冲突为 `project.godot` 渲染设置；保留主线 ETC2/ASTC 导入、像素对齐及云端安装脚本。Web 移动纹理选项恢复为主线的 true。
- autoload 改用可读资源路径。上游运行时在项目桥接器存在时交出生命周期，避免重复初始化/render/shutdown；扩展缺失时动态查找 singleton，不再发生解析错误。
- 缺平台 Init.bnk 时静音降级。仓库只有 Windows/Mac/Web Bank，未伪造 Linux Bank。
- 设置音量同步当前 Wwise 发声对象输出增益，post 前继承保存值，清理销毁对象；当前直接输出可用接口级测试验证，辅助发送/混响需以后音频配置与听测。
- Web 在缺 SharedArrayBuffer/跨源隔离时不启动 Wwise，并给出一次诊断，保持游戏可用。

## 实测

| 项目 | 结果及范围 |
|---|---|
| Godot 4.7.2 导入 | 完成；上游 Linux 数据库报告无该平台，退出有 ObjectDB 泄漏警告，未隐藏 |
| 原有回归 | 343/343 PASS：display 203、mobile_controls 42、forest 42、scene_flow 22、tutorial 34；0 脚本错误 |
| 音频桥接回归 | 9/9 PASS：生命周期、25 行配置、空占位、缺 Bank 降级、音量、静音、新对象继承静音、销毁清理、恢复音量；使用记录 API，不代表实际输出 |
| 无扩展隔离副本 | 不带 GDExtension 的项目副本导入并跑同一 9 项，全部通过 |
| Web release 导出 | 通过，extensions_support=true、thread_support=false，工作区产物约 76.4 MiB（80,098,953 字节）（不是约 756 MB 的仓库原生库体积） |
| 初次 Web 音频 | 普通本地 HTTP、Chromium、crossOriginIsolated=false，重复 SharedArrayBuffer 未定义错误；捕获的输出 RMS/peak 为 0，未得到有效播放回调 |
| 降级后 Web | initialized=false、rules=25、table_loaded=true；一次能力警告，无持续初始化错误；F9 posted=false，属于明确未接通 |
| 浏览器交互 | 登录→设置→0%→恢复→进入草坪→移动→Esc 返回标题均完成，截图复核；未新增玩法 |
| 实际音频验收 | Web 初始化/回调/音量波形/切场景音乐停止均被平台前提阻塞；Linux 无 Bank；桌面有声设备听感、移动真机均未测 |

本地日志、比对和截图位于 `build/qa/audio-integration/`（不提交构建产物）。关键文件：`browser-initial.log`、`browser-final.log`、`browser-muted.png`、`browser-grass.png`、`browser-return.png`、`test_*.log`、`no-extension-test.log`、`build-web.log`。

复验命令：

```sh
source .godot/cloud/env.sh
for test in display mobile_controls forest scene_flow tutorial audio_integration; do
  godot --headless --fixed-fps 60 --path . --script "tools/test_${test}.gd" || break
done
bash tools/build-web.sh
python3 -m http.server 8000 --directory build/web
```

## 后续与发布边界

可优先审阅 Godot 内置 PWA 隔离候选，不必据当前结果认定需要更换 Pages。仍需明确启用决定，检查线上 HTTPS 的首次访问/更新缓存，以及移动浏览器和实际设备听感；当前默认 PWA 开关没有改变。

已检查唯一 Actions 工作流 `.github/workflows/godot-web.yml`：push 仅 master、pull_request 仅 base master，deploy 还要求 master ref 且不是 pull_request。此集成分支的普通推送不触发正式部署。未手动触发 workflow，也未创建或审批 PR。


## 后续本地隔离/PWA 实测（同日，未新增推送）

用户明确批准仅本次云容器测试 Chromium 进程使用 `--no-sandbox`。所有页面均为任务自己的 127.0.0.1 HTTP 服务；没有登录、打开外站、修改系统/共享网络策略或部署。测试使用系统 Chromium + Playwright，未关闭浏览器同源/跨源隔离检查，也没有用自动播放豁免参数。每次浏览器在 finally 中关闭，结束时确认无测试 Chromium 进程残留。

| 环境 | 隔离/SAB | Wwise、回调与输出 |
|---|---|---|
| plain 本地 HTTP，默认非 PWA | false / undefined | 游戏可运行，Wwise 明确静音降级；点击后 Godot AudioContext running，输出仍为 0；F9 posted=false，无音频回调 |
| 本地 COOP same-origin + COEP require-corp | true / function | initialized=true、25 行、listener=true；F9 得到 duration_ms=550.6875 和 end_of_event；非零输出 |
| Godot 原生 PWA 原始导出，服务器无隔离头 | 首次 false，手动重载后 true | 首次静音；重载后事件回调与非零输出均成功 |
| PWA + 原有资源版本化脚本 | 缓存清单失效 | 8 个缓存项仍为 index.*，但文件已改名；必须修复，不能直接启用 |
| PWA + 本地构建兼容修复，服务器无隔离头 | 首次自动重载后 true | 首次访问自动重载一次后 initialized=true，点击后非零输出与完整回调；后续手动重载仍通过 |
| 同一候选挂在 `/GameJam2026/` 子路径 | 首次自动重载一次，true / function | worker=true、initialized=true、回调完整，点击后采样 RMS=0.034545、peak=0.101150；无资源请求失败 |

所有页面 `document.title` 为 `月隐林地 · Moonveil`，游戏登录画面实际标题仍为原 PR 的“游戏名称”。登录、设置、进入草坪、返回标题都有游戏画面验证。没有遇到缺 Bank/媒体或 HTTP 失败；早期首次异步 post 返回 0 的警告之后仍收到回调，这是上游排队行为，不应误记为媒体不存在。

### 音量、场景与浏览器政策

每个阶段对连接到 WebAudio destination 的节点另接 analyser，取 15 个时间域样本（约 1.5 秒）。以下是各帧最大节点 RMS 的均值，表示计算出的信号，不是扬声器听感：

| 阶段 | COOP/COEP | 修复后 PWA |
|---|---:|---:|
| 0% | 0 | 0 |
| 50% | 0.033671 | 0.044295 |
| 100% | 0.106026 | 0.080887 |
| 进入草坪 | 0.076871 | 0.074459 |
| 返回标题 | 0.076772 | 0.090977 |

音乐随时间变化，因此不同阶段不能用于证明精确的 2 倍振幅关系。0% 静音和恢复非零输出已证实。切场景后播放继续且没有资源/脚本错误；尚未逐声部计数或专门配置静音目标场景，所以不宣称排除了所有旧声部叠音。

早期 `page.evaluate`/title 查询可能携带 DevTools 用户手势，故不把早期“点击前有波形”当成自动播放保证。后续严格复验使用 CDP `Runtime.evaluate(userGesture=false)`：PWA 首载与重载在真实点击前均 suspended、RMS/peak=0；点击后 running、非零波形、完整回调。初次加载出现浏览器 autoplay 警告和上游重复尝试创建/关闭音频上下文；用户手势后成功。没有用自动播放豁免消除这些警告。

### 本地修复与下一步

`tools/version-web-assets.py` 现在支持可选输出目录，并同步重写 Godot 自带 worker、manifest、offline 页面中的资源名称。PWA 导出还会在单线程引擎启动前要求隔离，并等待内置 worker 的 `ready` 后才重载；原来的 2 秒超时“直接重载”改为明确超时报错，避免 worker 尚未激活就重载导致空白首屏。只调整 Godot 自带 worker 的引用和现有页面引导，没有引入第三方 worker。

两个构建回归检查通过，分别覆盖缓存引用/隔离引导，以及非 PWA 输出保持不请求隔离；默认非 PWA 的完整 Web 构建再次通过。没有再次运行 343 项玩法测试，因为这轮未修改玩法或音频 GDScript。`export_presets.cfg` 已恢复 `progressive_web_app/enabled=false`，因此本轮没有悄悄启用发布方案。

可行方案：审阅这些构建修复后，在另行明确授权的发布变更中启用 Godot 自带 PWA + ensure_cross_origin_isolation_headers；先验证 Pages HTTPS 的缓存升级/首载以及 Safari/Android 真机，再决定发布。本次没有线上成功或实际听感结论。

证据仍在 `build/qa/audio-integration/`：`isolated-console.log` / `isolated-samples.json`、`pwa-summary.log`、`pwa-ready-summary.log` / `pwa-ready-samples.json`、`plain-strict.json`、`pwa-subpath-strict.json`、对应截图。原始 PWA 包在 `build/qa/audio-pwa/`，修复候选在 `build/qa/audio-pwa-candidate/`；这些临时产物不提交。
