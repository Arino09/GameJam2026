# GameJam0911

## 项目需求文档

默认需求来源：[腾讯文档需求表](https://docs.qq.com/sheet/DTHZQbWVySG1aa2Fx?tab=nirmvp&_t=1789908056652&nlc=1)。

后续需求如果没有明确指定参考资料或来源，默认先读取这份在线文档的相关最新内容。项目协作规则见 [AGENTS.md](AGENTS.md)。

## 运行与登录页

在 Godot 4.7 中打开项目，按 **F5** 进入登录主菜单 `scenes/login.tscn`。

登录页依据腾讯文档「程序美术」表 B3 的草图：游戏名称、开始游戏、继续游戏、设置、退出。

- 开始游戏：先进入新手草坪，再进入山洞；击败新手 Boss 后，从山洞右侧出口进入待机主界面。有存档时，先确认再开始新进度。
- 继续游戏：教程未完成时恢复所在教程地图、位置和交互进度；教程完成或使用旧版存档时进入营地。没有有效存档时置灰。地图每 3 秒、失去焦点和返回菜单时自动保存。
- 设置：主音量与全屏显示。设置保存在本机；浏览器全屏需要点击开启。
- 退出：桌面版确认后退出；Web 版提示关闭标签页。
- 支持鼠标、触屏，以及方向键 / Tab、Enter、Esc。教程中右上角或 Esc 保存并返回标题；森林中返回营地。Esc 优先关闭地图总览。
- 进度保存在 `user://progress.cfg`，设置保存在 `user://settings.cfg`；Web 版限当前浏览器、当前站点，清理站点数据会移除存档。
- 可在 Login 根节点 Inspector 的 `game_title` 替换游戏名称，按钮和弹窗均为独立 Control 节点；背景和主题位于 `assets/ui/`。

## 待机主界面

新手教程完成后进入 `scenes/main_menu.tscn`，按「程序美术」表 B7 草图摆放任务、成就、图鉴、设置、技能树、背包、主角装备、交易行和出发探索入口。

- 点击主角查看装备；各系统有独立内容节点、空状态与关闭交互。当前先完成按钮和节点，未接入系统玩法及正式美术。
- 点击关闭、遮罩或按 Esc 关闭弹窗；「出发探索」进入地图，「返回标题」回到登录页。
- 设置音量与登录页共享，保存到现有本地设置。场景节点及接入说明见 `docs/main-menu.md`。

## 地图与角色序列帧动画

新手教程依据「地图写生区」A2:U12（草坪）、A14:U24（山洞）搭建，场景为 `scenes/tutorial_grass.tscn`、`scenes/tutorial_cave.tscn`。PC 使用 WASD / 方向键移动、Shift 奔跑、E 与向导交谈或开箱、空格 / J 攻击新手 Boss、M 查看总览。手机自动显示摇杆与触控按钮，具体操作见下节。地形碰撞、格位对照、占位交互与存档说明见 `docs/tutorial-maps.md`。

营地点击「出发探索」进入地图 `scenes/forest.tscn`，也可单独打开后按 **F6** 运行。地图「返回营地」保存位置与四方向朝向后回到主界面；Esc 优先关闭地图总览，再次按下返回营地。再次探索或从标题页继续游戏均恢复已保存的位置。

原动画预览 UI、预览场景和旧空白地图场景已删除。

## PC 与移动端操作

当前配置的发布目标为 Web，Godot 编辑器也可直接在桌面运行项目，尚未配置 Android / iOS 安装包。同一个 Web 页面会识别运行设备，自动选择控制方式：PC 保留键鼠；Android、iPhone、iPad 显示触控。iPad 桌面浏览模式也纳入识别，Windows 触屏笔记本仍使用 PC 方式。

- 手机横屏：左下摇杆移动，右下按住「奔跑」加速，可同时使用两个手指。草坪中靠近向导或宝箱后，动作按钮显示「交谈」或「开箱」；山洞中轻点「攻击」，遵守原有攻击距离和冷却。
- 右上「地图」打开或收起总览；总览期间停止移动和动作，「关闭地图」先回到游戏。正常游玩时可返回标题（教程）或营地（森林）。
- 登录、营地、设置和弹窗使用轻点操作。松手、触摸取消、失去焦点、旋转屏幕、打开地图或切换场景都会清理触控状态，避免角色持续移动。
- 设备识别集中在 `scripts/input_profile.gd`；三张地图共用 `scenes/mobile_controls.tscn` 和 `scripts/ui/mobile_controls.gd`，按钮和摇杆直接绘制，无需新增美术或音效资源。

## 验证与图集重建

### 分辨率适配

- 桌面 / 桌面 Web：统一使用 1280 × 720（16:9）逻辑视口，等比缩放至窗口可用区域，非 16:9 窗口居中留边。支持小窗口和非整数倍缩放。
- 手机 / 平板（含移动浏览器）：横屏游玩，以 720 逻辑像素高度适配，宽度随设备比例变化。登录、营地与地图共用同一适配入口，不在切换场景时改变缩放规则。
- 原生移动端使用双向横屏；移动浏览器进入全屏时尝试锁定横屏。不支持方向锁的浏览器在竖屏时提示旋转设备并暂停游戏，回到横屏后继续，旋转会释放触控输入。
- 桌面调试可附加 `-- --mobile-controls` 模拟移动端，再调整窗口尺寸检查横屏和竖屏。
- 实现入口为 `scripts/input_profile.gd`。分辨率回归覆盖桌面宽屏、4:3、小窗口、手机长屏、平板以及设备旋转。

```sh
godot --headless --path . --editor --import --quit
godot --headless --fixed-fps 60 --path . --script tools/test_display.gd
godot --headless --fixed-fps 60 --path . --script tools/test_mobile_controls.gd
godot --headless --fixed-fps 60 --path . --script tools/test_forest.gd
godot --headless --fixed-fps 60 --path . --script tools/test_scene_flow.gd
godot --headless --fixed-fps 60 --path . --script tools/test_tutorial.gd
```

检查移动方向、斜向速度、奔跑、双向过桥、河岸/建筑/地图边界碰撞以及地图开关。需要实际渲染截图时：

```sh
godot --fixed-fps 60 --path . --script tools/test_forest.gd -- --screenshots
godot --fixed-fps 60 --path . --script tools/test_tutorial.gd -- --screenshots
godot --fixed-fps 60 --path . --script tools/test_display.gd -- --screenshots
godot --fixed-fps 60 --path . --script tools/test_mobile_controls.gd -- --screenshots
```

触控回归使用独立进度文件，覆盖浏览器设备识别、多指移动/奔跑/攻击、触点取消、旋转、菜单轻点以及教程到营地和森林的流程。截图自动写入 `build/qa/`；桌面模拟不能替代手机浏览器真机验证。已有图集可直接使用；需要从原始生成图重新规整时：

```sh
python tools/build_elf_v2.py --pipeline <sprite-pipeline 插件的 scripts 目录>
```

图集重建需要 Pillow；运行游戏直接使用已生成资源。四方向循环预览是 `build/qa/elf_v2/walk_cycle.gif`，游戏内行走截图序列在 `build/qa/elf_v2/ingame/`。

## Web 构建与自动部署

在线试玩：<https://arino09.github.io/GameJam2026/>

GitHub Actions 工作流：`.github/workflows/godot-web.yml`。

- 推送到 `master`：使用 Godot **4.7.2** 导入项目、导出 Web，然后部署到 GitHub Pages。
- 向 `master` 提交 Pull Request：只构建验证，不发布。
- 也可在 Actions → Godot Web build and deploy → Run workflow 手动运行。
- 每次构建提供 `godot-web` 下载包，保留 14 天。
- 导出资源使用内容版本号命名，避免重新部署后浏览器继续使用旧资源。
- CI 从官方发布下载引擎和同版本 Web 模板，并校验 SHA-512。
- Pages 的 Source 必须设置为 **GitHub Actions**；未启用时仍保留构建产物并提示，跳过部署。

本地需安装 Godot 4.7.2 及对应导出模板，然后执行：

```sh
bash tools/build-web.sh
python3 -m http.server 8000 --directory build/web
```

打开 <http://localhost:8000>。不要直接双击 HTML 文件；浏览器需要通过 HTTP 加载 WASM 和资源包。可通过 `GODOT_BIN=/path/to/godot bash tools/build-web.sh` 指定引擎。

Web 使用兼容渲染器和单线程导出，不依赖 GitHub Pages 无法自定义的跨源隔离响应头。输出为 `build/web/index.html` 及同目录资源，构建目录不提交到仓库。Pages 部署仅使用 GitHub 自带的临时令牌，无需额外部署密钥。
