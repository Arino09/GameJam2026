# Wwise 音频事件表

项目只在 `WwiseManager` 中接触 Wwise。玩法脚本（或 `WwiseManager` 内置的自动钩子，如场景切换、按钮点击）只发语义键，音频同事编辑 `assets/Audio/audio_events.tsv` 的事件名，不需要给每个节点拖一个事件，也不需要请程序员加播放调用（见下文"键名和兜底链"）。TSV 可以用 Excel 直接打开和另存为 UTF-8（带 BOM）；使用制表符是为了避开 Godot 把普通 `.csv` 自动识别成翻译表。

## 表格字段

表格只有 4 列，UTF-8 with BOM，制表符分隔：

| 字段 | 用途 |
| --- | --- |
| `key` | 程序（或 `WwiseManager` 的自动钩子）查找的稳定键，例如 `interact_chest`。以 `#` 开头的行整行当注释跳过。 |
| `event` | Wwise Event 名称，不带路径。空值表示暂时静音——玩法照常运行，只是不发声。 |
| `stop_event` | 循环声音（音乐/环境音/移动）对应的 Stop Event；留空时 `stop(key)` 会改为直接停止这一行自己的 `event`（见下文"Auto-Defined SoundBank 和 WwiseEvent"），而不是什么都不做。 |
| `note` | 给音频同事看的自由文字：什么时候触发、在哪个场景。 |

不再有 `category`/`trigger_key`/`bank`/`enabled` 列：分类和触发说明写进 `note` 即可；`bank` 恒为 Auto-Defined SoundBank（详见下文），已没有需要单独配置的场景；`enabled` 用清空 `event` 代替关闭一行。

当前表只给 `test_play` 填入真实存在的 `Play_Test`，其余行都保留 `event` 为空作为音频制作填写的接口，避免开发期间误播放测试音。

## 键名和兜底链（fallback）

`WwiseManager.play(keys, source)` / `WwiseManager.stop(keys, source)` 的 `keys` 可以是单个 `String`，也可以是一个 `Array[String]`——按顺序尝试，第一个在表里存在且 `event` 非空的键胜出。`play(key)` 单个 `String` 的旧用法不变。玩法脚本调用时总是传入"具体键在前、通用兜底键在后"的数组，所以音频同事绝大多数情况下只需要在表里新增/填写一行，不需要请程序员加代码：

- **场景音乐** `scene_<场景键>`：`WwiseManager` 追踪当前场景自动播放/停止，场景键来自 `INITIAL_SCENE_KEYS` 或场景根节点的 `wwise_scene_key` meta。新增场景时补一行即可。
- **按钮反馈** `ui_button_<节点名>` → `ui_button`：所有按钮自动接线，默认共用 `ui_button` 这一条通用行；某个按钮想要专属声音时新增一行 `ui_button_<节点名>`，例如登录页开始按钮 `ui_button_StartButton`、营地探索按钮 `ui_button_Explore`。
- **互动结果** `interact_<kind>` → `interact`：教程道具（`TutorialProp.kind`，如 `guide`/`chest`）互动成功时触发；新的道具种类只要在 `kind` 枚举里加一项、表里加一行 `interact_<新 kind>`，不改代码就能配音。当前表：`interact_guide`、`interact_chest`，以及兜底的 `interact`。
- **攻击命中** `hit_<kind>` → `hit`：命中生效时触发。当前表：`hit_boss`，以及兜底的 `hit`。
- **击败** `defeat_<kind>` → `defeat`：目标被击败的瞬间触发。当前表：`defeat_boss`。
- **进入出口/传送门** `enter_<kind>` → `enter`：角色进入地图出口的瞬间触发。当前表：`enter_portal`。
- **移动** `walk_<场景键>` → `walk`、`run_<场景键>` → `run`：角色实际发生位移时按走路/奔跑状态触发，场景键来自 `WwiseManager.get_scene_key()`；停止移动或切换状态会先对上一次实际命中的键发送 `stop_event`（没填就停自身 `event`）。需要某个场景专属脚步声时新增 `walk_<场景键>` / `run_<场景键>` 行即可，不要把脚步事件设计成每帧触发的短音效。
- **弹窗** `modal_open`、`modal_close`：登录页设置/退出/新游戏/错误提示等弹窗显示和关闭时触发。
- **地图总览** `map_open`、`map_close`：教程和森林地图总览状态变化时触发；重复设置同一状态不会重复发声。
- **森林区域** `region_bridge`、`region_corridor`、`region_altar`、`region_south`、`region_crossroads`：森林已有的五个坐标区域发生切换时触发（桥、回廊、祭坛、南境、岔路）；离开一个区域会先 `stop()` 它，再 `play()` 新区域，避免环境音叠加。只使用现有 `location_name()` 的坐标判定，不猜测贴图材质。
- **测试** `test_play`：F9 热键和 `tools/wwise_play_test.gd` 冒烟测试共用，对应表里唯一真实存在的事件 `Play_Test`。

一个动作如果同时需要 UI 反馈和玩法结果两种声音，分别填两条键对应的行即可；只想要一个声音时清空另一行的 `event`。不要把同一个长循环事件同时填到多个场景/区域行。

### 什么情况仍然需要程序员

- 一个全新的动作类型，目前没有任何钩子会发送它的键（例如新的战斗判定、新的场景切换方式）——需要在对应脚本里加一行 `WwiseManager.play(...)`/`stop(...)` 调用。
- 需要精确到动画帧的音效时机（例如脚步必须卡在落地帧），现有钩子只在状态切换/结果发生时触发，不追踪逐帧动画进度。
- 按地面材质区分脚步声——地图目前没有材质/地表分区数据，`walk_<场景键>` 只能按场景区分，做不到按贴图材质区分。

## Auto-Defined SoundBank 和 WwiseEvent

本工程的 Wwise 项目用的是 Auto-Defined SoundBanks：每个 Event 会自动生成一个同名 Bank（例如 `Event/Play_Test.bnk`），媒体文件则以松散的 `.wem` 形式单独存放（例如 `Media/867510329.wem`），不打进那个 Bank 文件本身。

早期实现直接调用 `Wwise.load_bank("Event/Play_Test")` 再 `Wwise.post_event("Play_Test", node)`。`load_bank()` 内部固定以 `AkBankType_User`（User-Defined Bank 类型）加载，这个类型只认打进 Bank 文件里的内容——Auto-Defined Bank 的结构能加载成功，但松散媒体文件永远不会被加载，于是每次 `post_event` 都会在控制台打印 `Media <id> was not loaded for this source`，声音不会播放，但 `post_event` 仍然返回一个"看起来有效"的 Playing ID，容易被误判为成功。Wwise 插件 wiki 对此有明确说明：Auto-Defined SoundBank 必须使用 `WwiseEvent` 资源类型，而不是 `load_bank` + `post_event`。

现在 `scripts/wwise_manager.gd` 改为给每个用到的 Event 名维护一个缓存的 `WwiseEvent` 资源（`_get_wwise_event()`）：

- 用 `Wwise.get_id_from_string(event_name)`（Wwise 内置的 FNV-1 32 位哈希）算出 Event 的 ShortID，写入 `WwiseEvent.id`。表里的每一行都用 Auto-Defined Bank（与 Event 同名），所以 `WwiseEvent.bank_id` 直接用同一个 ID，`is_in_user_defined_sound_bank` 恒为 `false`；表格已不再有 `bank` 列，也没有 User-Defined SoundBank 的分支。
- 构造后手动调用一次 `WwiseEvent._on_post_resource_init()`。这个方法平时是 Godot 从 `.tres` 资源加载 `WwiseEvent` 时自动触发的钩子，本工程是用 `ClassDB.instantiate("WwiseEvent")` 现造对象，不会经过资源加载流程，所以必须手动调用——它才是真正触发 Auto-Defined Bank/媒体异步预加载（`PrepareEvent`）、并最终把 `is_auto_bank_loaded` 置为 `true` 的地方。漏掉这一步，现象和旧 bug 完全一样：`post()` 仍然返回有效 Playing ID，但控制台会打印 `Media ... was not loaded for this source`，且听不到声音。
- 之后调用 `WwiseEvent.post(node)` 播放、`WwiseEvent.stop(node, 0, AK_CURVE_LINEAR)`（曲线常量 `4`，对应 `AkUtils.AK_CURVE_LINEAR`，为避免脚本硬依赖 `AkUtils` 类而在 `wwise_manager.gd` 里直接写成整数常量）停止。`stop(key)` 的规则如果没填 `stop_event`，现在会直接停止该规则自己的播放事件，而不是像以前那样什么都不做。

`Wwise` 单例、`WwiseEvent`/`ClassDB` 相关调用全部通过 `ClassDB.class_exists()` / `has_method()` 反射检查，Wwise GDExtension 缺失或版本不匹配时只记录一次诊断，不会导致脚本编译失败或游戏崩溃。

## 运行时路径和导出

运行时只读取：

`res://assets/Audio/WwiseProject/TapTapJam26/GeneratedSoundBanks/<平台>/`

平台名由 Godot 运行环境决定：`Windows`、`Web`、`Mac`、`Android`、`iOS` 或 `Linux`。`Wwise.init()` 会先加载 `Init.bnk`；表里每一行引用的 Event Bank 都是 Auto-Defined，按需通过 `WwiseEvent` 懒加载，不需要程序预先加载列表。本项目当前 Bank 的语言目录是 Wwise 的 `SFX`，所以 Godot 的启动语言也配置为 `SFX`；如果以后生成了本地化语言 Bank，需要按实际输出目录调整它。创作工程和其他平台的 Bank 不应成为运行时依赖；导出预设应按目标平台排除其他平台目录。

`assets/Audio/audio_events.tsv` 不是导入资源（没有 `.import` 文件），Godot 的 `export_filter="all_resources"` 默认不会把它打进 PCK。导出预设必须在 `include_filter` 里显式加上 `*.tsv`（见 `export_presets.cfg` 的 `[preset.0]`），否则运行时 `FileAccess.open(res://assets/Audio/audio_events.tsv)` 会返回 null，`WwiseManager` 只会记录一次 `Wwise audio table not found` 诊断并继续以空规则表运行；新增导出预设（例如未来的 Windows Desktop 预设）时要同步加上这条 `include_filter`。

### 关于 AK_AlreadyInitialized

`scripts/wwise_manager.gd` 是当前唯一接入场景树的初始化入口（`project.godot` 的 `[autoload]` 中的 `WwiseManager`），它在 `_initialize()`（约第 140 行）里调用一次 `Wwise.call("init")`。Wwise 插件自带的 `addons/Wwise/runtime/wwise_runtime_manager.gd` 在其 `_init()`（第 8 行）里也会调用 `Wwise.init()`，但该文件目前没有 `plugin.cfg`、没有出现在 `project.godot` 的 `[autoload]` 或 `[editor_plugins]` 中，也没有被任何 `.tscn` 引用挂载——它是死代码，本次未能复现 `AK_AlreadyInitialized`（Windows headless 冒烟测试和 `--quit-after` 场景实例化都只打印一次 "Sound engine initialized successfully"）。为防止将来有人把这个插件自带的运行时管理器也接成 autoload 造成重复初始化，`wwise_manager.gd::_initialize()` 现在会先调用 `is_initialized()`，只有尚未初始化时才调用 `init()`，否则记录一次 `already_initialized` 诊断并直接沿用现有的初始化状态。

Wwise 扩展缺失、初始化失败或 Bank 不存在时，桥接器只记录一次诊断并让游戏继续运行。`post_event` 返回有效 Playing ID 只代表 Wwise 接受了事件，不代表当前设备一定能听到声音；真实听感仍需在有音频输出的运行环境中验证。

## 手动测试

在项目根目录执行下面的命令即可运行项目内的独立测试入口，不需要改游戏场景：

```text
Godot_v4.7.2-stable_win64_console.exe --path . --script tools/wwise_play_test.gd
```

这条命令只会在调用方看来启动一个进程，但脚本内部会用 `OS.execute()` 把自己作为子进程再跑一次（带隐藏的 `-- wwise-play-test-child` 标记），这样外层进程才能拿到子进程完整的 stdout/stderr 文本去 grep 那句 `Media ... was not loaded for this source`——脚本没法直接检查自己这个进程的输出。子进程内部通过 `WwiseManager.play_test_with_callback()` 用 `AK_END_OF_EVENT | AK_DURATION` 回调发送 `test_play` 规则对应的 Event（当前表里是 `Play_Test`），并轮询等待最多 5 秒（用真实经过的毫秒数而不是固定帧数，兼顾无音频设备时可能变慢的情况），不使用阻塞式 sleep。

脚本最终会打印这些行（子进程内部还会先打印一遍前缀相同、不带外层判定的版本）：

- `WWISE_PLAY_TEST_POSTED`：`play_test_with_callback()` 是否成功拿到了有效 Playing ID。
- `WWISE_PLAY_TEST_AUTO_BANK_LOADED`：对应 `WwiseEvent.is_auto_bank_loaded`，为 `true` 才说明 Auto-Defined Bank 及媒体的异步预加载真正完成了（见上文"Auto-Defined SoundBank 和 WwiseEvent"）。
- `WWISE_PLAY_TEST_DURATION_MS`：`AK_DURATION` 回调里的 `fDuration`（毫秒）。这是媒体被真正解码过的直接证据——旧 bug 下这个回调根本不会触发，值恒为 `0`。
- `WWISE_PLAY_TEST_END_OF_EVENT`：是否收到了 `AK_END_OF_EVENT` 回调，即事件是否播放完成。
- `WWISE_PLAY_TEST_STATUS`：`WwiseManager.get_status()` 的完整内容，包含 `wwise_events` 字段（每个缓存的 `WwiseEvent` 的 `is_auto_bank_loaded`），可用于检查初始化。
- `WWISE_PLAY_TEST_MEDIA_ERROR_SEEN`：外层进程在子进程完整输出里 grep `was not loaded for this source` 的结果，为 `true` 说明媒体加载失败复现了。
- `WWISE_PLAY_TEST_RESULT`：本次测试是否通过。判定为 `true` 需要同时满足：成功 post、`is_auto_bank_loaded` 为 `true`、收到了大于 `0` 的 `AK_DURATION`、收到了 `AK_END_OF_EVENT`，并且外层没有 grep 到 `WWISE_PLAY_TEST_MEDIA_ERROR_SEEN`。只要缺失任意一项（尤其是等了 5 秒也没等到 `AK_DURATION` 回调，或者出现了媒体报错），退出码就是 `1`，即使 `post()` 仍然返回了一个"看起来有效"的 Playing ID。

`WwiseManager.play_test()`（不带回调、给游戏内其它调用方用的版本）语义不变：仍然只是 `_play_rule("test_play", source)`，返回值只代表 `post()` 拿到了有效 Playing ID，不代表媒体真的解码成功——要验证媒体，请用上面的 `wwise_play_test.gd`，或在有音频输出设备的桌面运行中直接听。

实测（2026-09-22，Windows headless 与非 headless 均已验证）：`Play_Test` 的 `fDuration` 稳定为 `550.6875` 毫秒，`is_auto_bank_loaded` 为 `true`，未出现过 `Media ... was not loaded for this source`；headless 模式下 Wwise 的音频渲染管线照常工作，`AK_DURATION` / `AK_END_OF_EVENT` 回调都能正常触发，不需要额外加 `--rendering-driver` 之类的参数。

替换正式事件前，先确认对应平台目录下的 Auto-Defined Bank（`GeneratedSoundBanks/<平台>/Event/<EventName>.bnk`）和其松散媒体文件都存在；本仓库目前已有 Windows、Web、Mac、Android、iOS，未发现 Linux Bank。编辑 `audio_events.tsv` 后重启这次测试或重新运行游戏即可生效，当前桥接器没有热重载表格。

## 跨平台手动检查：F9 热键和控制台状态行

上面的 `tools/wwise_play_test.gd` 只能跑桌面 headless 进程，Web 导出包没有独立进程可以运行它。`scripts/wwise_manager.gd` 因此内置了两组不依赖额外进程、在编辑器 / Windows 构建 / 浏览器 DevTools 控制台里都能直接看到的诊断打印，作为跑通 `tools/wwise_play_test.gd` 之外的日常/跨平台复查手段：

- **`WWISE_STATUS` 启动行**（`_initialize()`，约第 168 行，包裹住原本的初始化逻辑 `_do_initialize()`）：不管 Wwise 扩展缺失、`init()` 失败还是成功，`_ready() -> _initialize.call_deferred()` 触发的这次初始化流程结束后都会打印且只打印一次：

  ```text
  WWISE_STATUS platform=<Windows|Web|Mac|Android|iOS|Linux> initialized=<bool> rules=<n> table_loaded=<bool>
  ```

  `platform` / `initialized` 直接来自 `get_status()`；`rules` 是解析出的规则行数（`_rules.size()`）；`table_loaded` 是新增字段（`get_status()` 里也能读到），标记 `assets/Audio/audio_events.tsv` 是否被 `_load_config()` 成功打开并解析完（即使解析出 0 条规则也算 `true`；文件打不开/为空则保持 `false`，同时会看到 `Wwise audio table not found` 或 `Wwise audio table is empty` 诊断）。

- **F9 热键**（`_unhandled_input()`，约第 53 行）：按一次 F9（`KEY_F9`，过滤了 `echo`，不区分焦点在哪个节点，且没有在 `project.godot` 里新增任何 InputMap action）会调用和 `tools/wwise_play_test.gd` 相同的 `play_test_with_callback()`，用 `AK_END_OF_EVENT | AK_DURATION` 回调发送 `test_play` 规则的 Event（当前表里是 `Play_Test`），并打印：

  ```text
  WWISE_HOTKEY_TEST posted=<bool>
  WWISE_HOTKEY_TEST duration_ms=<fDuration>   # 收到 AK_DURATION 回调时才打印
  WWISE_HOTKEY_TEST end_of_event               # 收到 AK_END_OF_EVENT 回调时才打印
  ```

  `posted` 只代表 `post_callback()` 拿到了有效 Playing ID，和 `WWISE_PLAY_TEST_POSTED` 语义一致；真正证明媒体解码成功的是后续出现的 `duration_ms`（非 0）和 `end_of_event` 两行。

  浏览器（尤其是 Web 导出）有自动播放策略：页面刚加载完时 AudioContext 可能还处于 suspended 状态，第一次 F9 有可能因为音频尚未真正跑起来而拿不到有效回调（或者第一次 `posted=false` 之后，之前的引擎批处理 callback 才姗姗来迟打印在下一帧）。请先在画布上点一下（提供一次用户手势去 resume AudioContext），F9 无反应或结果不完整时再按一次，通常第二次就能看到完整的 `posted=true` + `duration_ms=...` + `end_of_event` 三行。

  实测（2026-09-22，Web 导出，`build/web` 用 `python -m http.server` 起本地静态服务器，浏览器 DevTools 控制台观察）：启动后先看到

  ```text
  WWISE_STATUS platform=Web initialized=true rules=25 table_loaded=true
  ```

  点击画布、第一次按 F9 打印 `WWISE_HOTKEY_TEST posted=false`（随后仍收到了 `duration_ms=550.6875` / `end_of_event`，疑似前一帧回调延迟到达，不是媒体真的没解码），第二次按 F9 打印出完整的 `WWISE_HOTKEY_TEST posted=true` / `duration_ms=550.6875` / `end_of_event`。全程未出现 `Media ... was not loaded for this source` 或 `Wwise audio table not found`；控制台里唯一的相关警告是已被 `_do_initialize()` 显式处理过的 `Wwise was already initialized before WwiseManager ran; skipping duplicate init() call.`（说明 Web 导出包里还有别的代码路径先调用了一次 `Wwise.init()`，但 `wwise_manager.gd` 的 `is_initialized()` 判断挡住了重复初始化，属于预期内的降级诊断，不是错误）。

  这两组打印在 Godot 编辑器运行、Windows 打包运行、浏览器 DevTools 控制台里的格式完全一致，可以作为不跑 `tools/wwise_play_test.gd` 时的快速人工/跨平台确认手段。
