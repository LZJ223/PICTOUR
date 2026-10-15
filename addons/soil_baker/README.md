# Soil Baker

Godot 编辑器内的 Ground 贴图烘焙工具。生成过程只在编辑阶段运行；游戏使用保存好的 PNG 和 `LayerObject` 场景。

## 使用

1. 在 Godot 的场景树中选中一个使用 `Layer_Object.gd` 的 `StaticBody2D` Ground。它必须有 `CollisionBox : CollisionPolygon2D` 和 `VisualRoot : Node2D`。
2. 打开右侧 **Soil Baker** 面板，调整颜色、圆角、描边、草地波点和输出参数。
3. 点击**预览**查看缩小预览，点击**生成并保存 Soil** 烘焙完整贴图。
4. 在 `res://Generated/Soil/` 找到 `Soil_001.tscn`、`Soil_001.png`、对应的参数 `.tres` 和生成记录 `.recipe.json`。把新场景拖到目标 `DepthLayer` 下，并按原 Ground 的位置摆放。

工具不会修改或替换被选中的 Ground。每次生成寻找下一个空闲的 `Soil_编号`，避免覆盖已有结果。

## 参数说明

- **Outer / Inner corner radius**：外角使用大半径，内角使用小半径；窄边会自动缩小半径。
- **Outline width**：默认 2 像素。`Outline wobble` 和 `Wobble wavelength` 控制平滑的手绘抖动，碰撞边缘不参与抖动。
- **Grass depth**：从所有朝上的地面边缘向内计算草地区域；波点半径随深度减小。
- **Dot spacing / radius ratio**：圆点呈六边形错位排列，半径比例决定顶部的绿色覆盖率。
- **Seed**：固定圆点相位和描边抖动，使重复烘焙的结果稳定。
- **Pixels per unit / Supersampling**：贴图密度与抗锯齿倍率。现有 4000×400 Ground 在默认值下输出约 4012×412 PNG。

输入必须是没有自交的单个闭合多边形。烘焙期间的最大边长为 8192 像素；超限时会提示降低像素密度或超采样倍率。PNG 与场景是可提交的最终资源，`addons/soil_baker/` 不需要进入游戏运行路径。

## 验证

在项目目录运行：

```powershell
& "C:\Program Files\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path . --script res://addons/soil_baker/tests/smoke_test.gd
```

测试检查现有 Ground 尺寸下的贴图、透明边距、凹角圆滑和场景打包，并把预览图写入忽略的 `.godot/` 目录。
