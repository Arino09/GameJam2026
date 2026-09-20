# GameJam0911

## 项目需求文档

默认需求来源：[腾讯文档需求表](https://docs.qq.com/sheet/DTHZQbWVySG1aa2Fx?tab=nirmvp&_t=1789908056652&nlc=1)。

后续需求如果没有明确指定参考资料或来源，默认先读取这份在线文档的相关最新内容。项目协作规则见 [AGENTS.md](AGENTS.md)。

## 运行与登录页

在 Godot 4.7 中打开项目，按 **F5** 进入登录主菜单 `scenes/login.tscn`。

登录页依据腾讯文档「程序美术」表 B3 的草图：游戏名称、开始游戏、继续游戏、设置、退出。

- 开始游戏：进入待机营地；有存档时，先确认再开始新进度。
- 继续游戏：恢复角色位置和朝向；没有有效存档时置灰。地图每 3 秒、失去焦点和返回菜单时自动保存。
- 设置：主音量与全屏显示。设置保存在本机；浏览器全屏需要点击开启。
- 退出：桌面版确认后退出；Web 版提示关闭标签页。
- 支持鼠标、触屏，以及方向键 / Tab、Enter、Esc。地图右上角或 Esc 可返回营地。
- 进度保存在 `user://progress.cfg`，设置保存在 `user://settings.cfg`；Web 版限当前浏览器、当前站点，清理站点数据会移除存档。
- 可在 Login 根节点 Inspector 的 `game_title` 替换游戏名称，按钮和弹窗均为独立 Control 节点；背景和主题位于 `assets/ui/`。

## 待机主界面

登录后进入 `scenes/main_menu.tscn`，按「程序美术」表 B7 草图摆放任务、成就、图鉴、设置、技能树、背包、主角装备、交易行和出发探索入口。

- 点击主角查看装备；各系统有独立内容节点、空状态与关闭交互。当前先完成按钮和节点，未接入系统玩法及正式美术。
- 点击关闭、遮罩或按 Esc 关闭弹窗；「出发探索」进入地图，「返回标题」回到登录页。
- 设置音量与登录页共享，保存到现有本地设置。场景节点及接入说明见 `docs/main-menu.md`。

## 地图与角色序列帧动画

营地点击「出发探索」进入地图 `scenes/map.tscn`，也可单独打开后按 **F6** 运行。

原动画预览 UI、预览场景和旧空白地图场景已删除。

## 验证与图集重建

```sh
godot --headless --path . --editor --import --quit
godot --headless --fixed-fps 60 --path . --script tools/test_forest.gd
```

检查移动方向、斜向速度、奔跑、双向过桥、河岸/建筑/地图边界碰撞以及地图开关。需要实际渲染截图时：

```sh
godot --fixed-fps 60 --path . --script tools/test_forest.gd -- --screenshots
```

截图自动写入 `build/qa/`。已有图集可直接使用；需要从原始生成图重新规整时：

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
