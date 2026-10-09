# 纸片旅人首版精灵

原创程序美术：暖纸斗篷、梅紫墨轮廓、朱砂围巾。没有采样或编辑第三方角色素材，也没有调用图像生成模型。来源见 `Traveler.source.json`。

`Traveler_Atlas.png` 是带透明通道的 768×768 PNG 图集，每格 96×128，按从左至右的顺序播放，每行动作均为 **8 张不同的帧**：

| 行号，从 0 起 | 动作 | 播放帧率 |
|---|---|---|
| 0 | idle 待机与围巾轻摆 | 6 |
| 1 | walk 行走 | 12 |
| 2 | run 奔跑 | 16 |
| 3 | rise 起跳上升 | 10 |
| 4 | fall 下落 | 10 |
| 5 | dash 短冲刺 | 28 |

`Traveler_Frames.tres` 是可在 Godot Inspector 中编辑的 SpriteFrames 资源。角色使用 `AnimatedSprite2D`，运行时依据现有运动状态选择动作，通过 `flip_h` 面向左侧；这些动作不修改物理位置、碰撞或运动参数。

纹理含圆角墨线后的地面动作透明边界结束于源坐标 y=115。绘制脚端点为 y=112，脚底锚点采用 (48,115)，游戏内缩放 0.5 并固定节点位置 (0,-25.5)，令纹理足底与角色根节点 y=0 相接。上升动作收脚 1 游戏像素；碰撞仍为 20×40。

保留 `Visual_Body` 的 Polygon2D 类型、旧 polygon 和 `visible` 接口，将原方块绘制色透明，精灵作为其子节点。无人机状态切换仍通过该父节点隐藏角色，旧四层 `Player_Object` 的矩形留体资源未改动。

可编辑的程序几何源为 `Build_Traveler.gd`；`Traveler_Atlas.svg` 为完整矢量图集。运行下列命令会重建 PNG、SVG 与 SpriteFrames，然后需要在编辑器重新导入：

```powershell
& 'D:\EpicGames\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://Art/Player/Build_Traveler.gd
```

本版用于带美术白模的动作与小尺寸可读性验证，角色身份、最终动画表现和手绘细节仍可替换。所有微刻线在源几何中固定，运行时不加入随机颗粒或节点摆动。
