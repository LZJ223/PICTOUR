# CloudBox Rounder

独立的 Godot 编辑器插件，为多边形 ShadowedGeometry 生成外角大、内角小的相切圆角，保存完整的 ShadowedGeometry 场景。

## 使用

1. 在场景树中选择使用 `Component/Shadowed_Geometry/Shadowed_Geometry.gd`（或其派生脚本）的节点。
2. 打开右侧 **CloudBox Rounder** 面板。面板列出将同步的节点路径。
3. 调整 **Outer Radius**（外角半径）、**Inner Radius**（内角半径）和 **Max Chord Error**（采样最大弦误差）。半径与误差都以 `CollisionBox` 的本地单位计；物体缩放后圆角也一起缩放。默认值分别为 32、8、0.5。
4. 点击 **预览圆角**，在 2D 编辑器中查看黄色原轮廓和青色圆角轮廓。原节点仍可编辑；修改源多边形后旧预览自动清除。
5. 填写 **素材名称** 与 **输出父目录**，点击 **生成并保存**。
6. 将输出的 `.tscn` 作为物件放到目标 `DepthLayer` 下。生成过程保留选中源节点，源文件不会被覆盖。

可用 **加载圆角参数** 读取之前保存的 `CloudRoundProfile .tres`。插件可在 **项目设置 → 插件** 中单独启用或关闭。

## 节点与外观

以根节点的 `CollisionBox.polygon` 为唯一输入；必需结构：

```text
ShadowedGeometry : PhysicsBody2D（沿用源节点实际类型，例如 RigidBody2D）
├── CollisionBox : CollisionPolygon2D
├── VisualRoot : Node2D
│   ├── Shape : Polygon2D
│   ├── Outline : Line2D / Polygon2D（可选）
│   └── Area2D
│       └── CollisionBox : CollisionPolygon2D
└── Shadow : Polygon2D
```

插件复制当前选中实例的完整节点树，再更新轮廓。保留根物理类型、脚本、导出参数、碰撞设置、分组和内部连接，以及 Shape 的材质、贴图、纹理缩放/旋转、重复方式、颜色等外观设置。选中实例上的实时覆盖也会保存；当前模板中贴图缩放为 `Vector2(2, 2)` 时，生成结果同样保留该值。

**保存时按圆角后多边形的面积质心居中，并将根节点的 Transform 重置为单位变换**（位置、旋转、斜切归零，缩放归一）。关卡实例的放置变换不会被保存进素材。碰撞、Shape、点击区域、描边与 Shadow 都使用减去相同质心偏移后的轮廓。CollisionBox 自身的缩放保持原值。

居中时会补偿 Polygon2D 的 `texture_offset`，保持波点在轮廓上的相位；其 `texture_scale` 和 `texture_rotation` 不变。独立装饰节点相对轮廓的位置也会补偿。自动质心模式继续使用自动模式；已有自定义物理质心会按实际碰撞缩放后的居中位移换算，保留它相对轮廓的偏移。

这是坐标修正，生成器保留原有重力与旋转自由度。居中可解决偏心引发的本次倾倒；不规则物体是否稳定仍由实际支撑面与质心位置决定。

根碰撞、Shape、点击碰撞与 Shadow 母本使用完全相同的圆角多边形。已有名称以 `Outline` 开头的描边节点，以及其余轮廓与输入一致的 Polygon2D、CollisionPolygon2D、Line2D，也会自动列入同步列表；轮廓比较支持顶点起点变化与逆序。闭合 Line2D 使用圆角顶点；原本通过首尾重复点闭合的 Line2D 仍使用该方式。

现有 `Shadowed_Geometry.gd` 会从 Shadow 母本复制运行时影子，生成的圆角因此自动用于投影。运行时直接使用保存的顶点，不依赖本插件计算圆角。

## 几何约定

- 支持顺时针、逆时针的简单凸/凹多边形；相邻重复点、重复闭合点和直线上的中间点会清理。
- 圆角采用相切圆弧，按最大弦误差采样，至少保持足够的角度细分。短边两端各最多占边长的 49%，防止邻接圆角重叠。
- 圆角后的轮廓会检查自交和三角化。狭窄凹槽发生冲突时最多尝试八次缩小整体半径，并显示有效半径调整提示。仍然无效时拒绝保存。
- 默认最多 1024 个输出顶点。超限时提高弦误差，或根据需要调整 **Max Vertices**；顶点越多，碰撞分解和投影的成本越高。
- 遵循原有 LayerObject 坐标约定：CollisionBox 的位置/旋转/斜切为零，可使用正数缩放；VisualRoot 保持默认变换或同样的缩放。其余共享轮廓节点需要在相应根坐标架中对齐。遇到额外偏移会明确拒绝，避免视觉、碰撞与投影错位。
- 支持项目现有的自动纹理坐标映射。若 Polygon2D 已有手工 UV、逐顶点颜色、骨骼、内部顶点或自定义三角形索引，会提示先处理这些与顶点数量绑定的数据，避免静默破坏外观。

## 文件输出

沿用三个纹理插件的命名和冲突规则，共享 `addons/texture_baker_common/` 的输出控件与目录分配逻辑。圆角实现不依赖 Soil、Leaf 或 Trunk 插件。

默认父目录为 `res://Generated/CloudBox`，名称自动选择可用的 `CloudBox_001` 等编号；也可填写自定义名称和项目内父目录：

```text
指定父目录/CloudBox_001/
  CloudBox_001.tscn
  CloudBox_001.tres
  CloudBox_001.recipe.json
```

已有同名文件或文件夹（包括空文件夹）时直接拒绝输出。参数与生成记录保存在同一素材文件夹中；记录包含输入、居中前后的输出轮廓、质心偏移、同步路径以及各角的实际半径。已有素材需要重新生成才能采用新的居中规则。

## 验证

```powershell
& "C:\Program Files\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path . res://addons/cloud_box_rounder/tests/test_cloud_rounder.tscn
```

覆盖顺逆绕序、圆弧形状和弦误差、凸/凹半径、短边约束、非法输入、顶点限制、面积质心、根变换清理、描边和共享多边形同步、装饰补偿、自定义物理质心、源节点保护、材质与实时贴图参数保存、冲突拒绝，以及放入 DepthLayer 后的选择轮廓、投影副本和实际物理碰撞。

落地回归在物理模拟实际启用、重力开启且旋转自由的条件下，使用本次倾倒的偏移轮廓进行对照：旧轮廓必须复现倾倒，新导出的居中轮廓应落地稳定。

测试资源保存在忽略的 `.godot/cloud_rounder_tests/`。
