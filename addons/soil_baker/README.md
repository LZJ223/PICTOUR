# Soil Baker

Godot 编辑器内的 Ground 贴图烘焙工具。生成过程只在编辑阶段运行；游戏使用保存好的 PNG 和 `LayerObject` 场景。

## 使用

1. 在 Godot 的场景树中选中一个使用 `Layer_Object.gd` 的 `StaticBody2D` Ground。它必须有 `CollisionBox : CollisionPolygon2D` 和 `VisualRoot : Node2D`。
2. 打开右侧 **Soil Baker** 面板，调整颜色、圆角、描边、草地波点和输出参数。
3. 点击**预览**查看缩小预览，点击**生成并保存 Soil** 烘焙贴图分块。
4. 在 `res://Generated/Soil/` 找到 `Soil_001.tscn`、`Soil_001_000_000.png` 等分块、对应的参数 `.tres` 和生成记录 `.recipe.json`。把新场景拖到目标 `DepthLayer` 下，并按原 Ground 的位置摆放。

工具不会修改或替换被选中的 Ground。每次生成寻找下一个空闲的 `Soil_编号`，避免覆盖已有结果。

## 参数说明

- **Outer / Inner corner radius**：外角使用大半径，内角使用小半径；窄边会自动缩小半径。
- **Outline width**：默认 2 像素。`Outline wobble` 和 `Wobble wavelength` 控制平滑的手绘抖动，碰撞边缘不参与抖动。
- **Grass depth**：从所有朝上的地面边缘向内计算草地区域；波点半径随深度减小。
- **Dot spacing / radius ratio**：圆点呈六边形错位排列，半径比例决定顶部的绿色覆盖率。
- **Seed**：固定圆点相位和描边抖动，使重复烘焙的结果稳定。
- **Pixels per unit / Supersampling**：贴图密度与烘焙时的抗锯齿倍率。
- **Tile size px**：每块最大有效边长，默认 1024 像素；保存时还会裁掉透明区域，并保留接缝采样边距。

输入必须是没有自交的单个闭合多边形。工具先将纯棕色底色保存为场景中的 `Polygon2D`，再只为草地波点和描边生成透明 PNG。大块纯色内部会直接跳过，不产生空白纹理；边缘分块也会裁掉多余透明像素。分块逐张渲染和写入，不再受整块 Ground 的 8192 像素边长限制。单块超出 SVG 渲染上限时仍会提示调整分块尺寸或超采样倍率。生成场景在游戏中直接使用已保存的 PNG 和多边形，无需运行插件或再次生成。旧版单张 PNG 的 Soil 场景不受影响；如需节省内存，可重新烘焙。

## 验证

在项目目录运行：

```powershell
& "C:\Program Files\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path . --script res://addons/soil_baker/tests/smoke_test.gd
```

测试检查现有 Ground 尺寸下的预览、透明边距、凹角圆滑、分块接缝、大型 Ground、空白分块跳过和场景打包，并把预览图写入忽略的 `.godot/` 目录。
