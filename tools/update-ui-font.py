#!/usr/bin/env python3
"""用法：python3 tools/update-ui-font.py /path/to/NotoSansSC[wght].ttf

依赖 fonttools。字体来源：https://github.com/google/fonts/tree/main/ofl/notosanssc
完整源字体保留在仓库外，仓库内附带 OFL 许可证。
"""

import argparse
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    text = "".join(chr(i) for i in range(32, 127)) + "←→↑↓◇—·"
    for folder, extension in [("scenes", "*.tscn"), ("scripts", "*.gd")]:
        for path in sorted((root / folder).rglob(extension)):
            text += path.read_text(encoding="utf-8")
    font = TTFont(args.source)
    if "fvar" in font:
        font = instantiateVariableFont(font, {"wght": 400}, inplace=True)
    # 忽略空白控制字符，确保字体覆盖所有可见字符。
    required = {ord(c) for c in text if not c.isspace()}
    missing = required - set(font.getBestCmap())
    if missing:
        raise SystemExit(f"源字体缺少字符：{''.join(chr(c) for c in sorted(missing))}")
    subsetter = subset.Subsetter()
    subsetter.populate(text=text)
    subsetter.subset(font)
    output = root / "assets/fonts/ui_chinese.ttf"
    font.save(output)
    print(f"已保存 {output.name}：{len(required)} 个字符，{output.stat().st_size} 字节")


if __name__ == "__main__":
    main()
