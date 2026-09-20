# 待机主界面

依据 [开发表「程序美术」B7/C7](https://docs.qq.com/sheet/DTHZQbWVySG1aa2Fx?tab=nirmvp) 的参考图和说明制作：先实现可点击的系统按钮与节点，暂不接入美术资源。

`scenes/main_menu.tscn` 是待机营地场景，可在编辑器直接调整布局。登录后进入营地，点击「出发探索」进入现有地图，地图返回营地，营地可返回标题页。

| 草图位置 | 入口节点（Navigation 下） | 弹窗内容节点 |
| --- | --- | --- |
| 右上 | TopSystems/Tasks | Tasks |
| 右上 | TopSystems/Achievements | Achievements |
| 右上 | TopSystems/Codex | Codex |
| 右上 | TopSystems/Settings | Settings |
| 左侧 | SkillTree | SkillTree |
| 左侧下方 | Backpack | Backpack |
| 中央主角 | Character/Equipment | Equipment |
| 左下 | TradingHouse | TradingHouse |
| 右下 | Explore | 进入现有 map.tscn |

弹窗内容均位于 `SystemOverlay/Center/Panel/Margin/Stack/PanelContent`。按钮通过 `system` metadata 对应同名内容节点；`title` metadata 控制弹窗标题。每个系统的内容节点单独保留，方便接入后续场景或数据。

任务、成就、图鉴、技能树、背包、装备和交易行目前是入口及空状态，不包含任务发奖、成长、物品或交易逻辑。背包保留 12 个槽位，装备保留 6 个槽位。设置里的音量使用现有 GameSession 音量与本地设置保存逻辑。

关闭按钮、点击遮罩或 Esc 关闭弹窗并恢复入口焦点；弹窗打开时底层按钮不可操作。Tab / Shift+Tab 切换焦点，Enter / Space 激活按钮。

中央使用原生绘制的角色占位节点，无新美术图片；以后替换 `Navigation/Character/Placeholder` 即可，保留 `Equipment` 点击区域。地图提供「返回营地」按钮及 Esc 返回入口。
