# 自然景物父素材

这批素材为项目原创程序绘图，源轮廓位于 `Component/Object/Natural_Object/Natural_Form.gd`，透明 PNG 和对应 SVG 由 `Build_Nature.gd` 生成。没有使用第三方贴图；构图色彩参考本项目已接受的 AI 概念图 `Art/Concepts/Paper_Garden_01.png`。

运行材质叠加项目 AI 生成的 `Art/Materials/Dry_Ink_AI.png` 干墨明暗细节，保留 PNG 轮廓和 alpha。其生成与来源由 `Art/Materials` 记录，素材未被脚本裁改。

每族提供两份印刷纹理／局部变体：岩石、矮扇树、空心拱、枯枝、扇叶草。暖纸色微粒、梅紫阴影和灰粉干墨用于近层，背景色由材质淡化为鼠尾草色。图层变化不替换父轮廓。

`Natural_Object.tscn` 根脚坐标为 `(0,0)`，实体向负 Y 生长。`dimensions` 调整父尺寸，`CollisionBox` 仍保持零偏移。拱门的开底凹多边形会自动分解为多块实体，门洞可通行；枝干踏面为真实碰撞，扇叶只参与点选，草为可搬而无实体的景物。草不是障碍。所有家族默认可换层。

PNG 以 2 倍密度生成，四周各 24 个名义像素透明留边；运行时缩小为名义尺寸。实例可以放大缩小、调整宽高和选取变体，不把 PNG 毛边误当做撞墙边界。

在仓库根目录执行：

```powershell
& 'D:\EpicGames\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://Art/Nature/Build_Nature.gd
```

脚本名为构建工具，不会在运行游戏时重绘纹理。场景根据素材与轮廓构建一次碰撞和点选代理；逐帧只更新投影，不重建物理形状。
