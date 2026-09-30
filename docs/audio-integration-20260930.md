# 音频 PR #1 集成验证（2026-09-30）

分支：`integration/audio-pr1-20260930`。
基准：`origin/master` 的 `f96de18049940f61482c8129902b3599cae3d179`。
音频 PR：<https://github.com/Arino09/GameJam2026/pull/1>，实取 head `309450ce907184485fb792c439906ffb6523bbd1`。
合并提交：`616b04a8180dfd64759e0f09a6b38887c2c75e15`，保留两个父提交和原作者历史。

## 结论

玩法与导出可集成，当前 Pages 条件下的 Wwise 音频仍阻塞，不能标为音频验收通过。没有合回 master，没有部署，没有修改原 PR 或审批状态，没有修改网络安全/凭据或接受新许可。

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

需先决定适用于最终托管环境的音频输出方案：支持跨源隔离的环境或不依赖它的输出实现，然后重跑真实 Wwise 初始化、事件回调、波形/静音和场景切换，最后由有设备的人员听测。当前不能通过改网络安全设置绕过，也不能因 nothreads 文件名就认定无需隔离。

已检查唯一 Actions 工作流 `.github/workflows/godot-web.yml`：push 仅 master、pull_request 仅 base master，deploy 还要求 master ref 且不是 pull_request。此集成分支的普通推送不触发正式部署。未手动触发 workflow，也未创建或审批 PR。
