# 角色序列帧动画

## 项目需求文档

默认需求来源：[腾讯文档需求表](https://docs.qq.com/sheet/DTHZQbWVySG1aa2Fx?tab=nirmvp&_t=1789908056652&nlc=1)。

后续需求如果没有明确指定参考资料或来源，默认先读取这份在线文档的相关最新内容。项目协作规则见 [AGENTS.md](AGENTS.md)。

在 Godot 4.7 中打开项目，按 **F5** 运行空白地图 `scenes/map.tscn`。

- WASD / 方向键或左下角屏幕按钮：上下左右移动，支持斜向移动。
- 空格或右下角攻击按钮：攻击。攻击期间可以继续移动和转向，动作不会被移动打断。
- 屏幕按钮支持鼠标及多点触控；人物不能离开地图边界。
- 现有素材没有独立行走帧，移动时沿用 4 帧动画。

原动画预览仍可打开 `scenes/preview.tscn` 后按 **F6** 运行。

- 上排 4 帧：`idle`，5 FPS，循环播放。
- 下排 7 帧：`attack`，10 FPS，带少量预备与收招停顿，播放完自动回到待机。
- 按空格或点击 ATTACK 发起攻击；攻击期间重复输入不会重置动画。
- FLIP 可检查水平翻转效果。

## 在其他场景中使用

实例化 `scenes/character.tscn`，把根节点放在希望角色脚底落地的位置，然后调用角色的 `attack()`。可连接 `attack_finished` 信号处理攻击结束事件。

`assets/character/character_frames.tres` 是可在编辑器中调整的 SpriteFrames 资源，使用 AtlasTexture 逐帧选区和 margin 对齐脚底。材质与脚本配套使用，负责黑底透明处理及相邻攻击帧的局部遮罩；每个角色实例拥有独立材质。

输入图片原样保存在 `assets/character/character_sheet.jpg`，尺寸 2520 × 1280。由于原图是黑底 JPG，没有原生透明通道，当前材质按亮度去黑底，深色细节和边缘可能受到轻微影响。以后如有透明 PNG 原始素材，可以替换图集并移除去黑底材质。没有生成或补画新的动作帧。

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
