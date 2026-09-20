# Web UI 字体

`ui_chinese.ttf` 来自 Google Fonts 的 Noto Sans SC，使用 SIL Open Font License 1.1（见 `OFL.txt`）。

来源：https://github.com/google/fonts/tree/main/ofl/notosanssc

当前文件固定为 400 字重，使用 FontTools 保留当前 `scenes/*.tscn`、`scripts/*.gd` 中的字符、ASCII 和四个方向箭头。这样 Web 无需依赖系统字体即可显示中文，并减少下载大小。新增中文界面文字时，需要更新字体子集或换为完整字体。

下载上述来源的 `NotoSansSC[wght].ttf`，安装 `fonttools` 后执行：

```sh
python3 tools/update-ui-font.py '/path/to/NotoSansSC[wght].ttf'
```

脚本会扫描当前场景、脚本文字，验证源字体包含全部字符，并重新生成子集。登录页的中文和装饰符号也在此范围内。

`ui_theme.tres` 作为项目默认主题，使动态创建的按钮标签与场景标签使用相同字体。
