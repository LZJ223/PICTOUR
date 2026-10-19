# Cloud Ground Baker

独立 Godot 编辑器插件，为静态 `Shadowed_Ground` 生成可直接用于游戏的圆角云地面。只在编辑时生成资源；运行时沿用项目原有 `Shadowed_Geometry.gd`。

## 使用

1. 项目设置 → 插件，启用 **Cloud Ground Baker**（项目已默认启用）。
2. 在场景树选择 `Shadowed_Ground` 根节点，支持关卡实例当前的多边形和属性覆盖。
3. 在右侧 **Cloud Ground Baker** 面板调整参数，点击“预览”。
4. 填写素材名称和输出父目录，点击“生成并保存 CloudGround”。目录必须在项目内，才能导入 PNG。
5. 将生成的 `.tscn` 拖入关卡图层。生成器不自动替换原节点。

空名称默认 `CloudGround_001` 起递增，空目录默认 `res://Generated/CloudGround`。指定 `CloudGround_02` 时输出：

```text
输出父目录/
└─ CloudGround_02/
   ├─ CloudGround_02.tscn
   ├─ CloudGround_02_001.png
   ├─ CloudGround_02_002.png
   ├─ CloudGround_02.tres
   └─ CloudGround_02.recipe.json
```

`.tres` 可以通过“加载参数”再次使用。Godot 自动添加 PNG 导入文件。名称对应的文件或目录已存在时直接拒绝输出，不覆盖或合并。取消/写入失败时已生成的文件会保留，面板会提示目录；重试时请更换名称或自行清理该目录。

## 节点与影子

源节点需为 `StaticBody2D`，使用 `Shadowed_Geometry.gd` 或其继承脚本，并有以下结构：

```text
CloudGround_编号 (StaticBody2D, 原有脚本与配置)
├─ CollisionBox (CollisionPolygon2D, 圆角轮廓)
├─ VisualRoot
│  ├─ Polygon2D (纯色底面，圆角轮廓)
│  ├─ CloudDots
│  │  └─ CloudDots_001… (Sprite2D, 外部 PNG 分块)
│  └─ Outline (Line2D, 闭合抖动描边)
└─ Shadow (Polygon2D, 相同圆角轮廓，隐藏母本)
```

生成结果固定 `can_leave_shadow=true`、`can_be_shadowed=false`。不创建 Area2D 或点选碰撞。原运行时代码要求 `Shadow` 为 `Polygon2D`，运行时会由其创建 `ShadowBox_N` 和 `ShadowVisual_N`，因此保留此类型。实体碰撞使用 `CollisionBox`。

外角与内角分别采用大、小圆角。底面、实体碰撞、Shadow 同步轮廓，描边沿其法线叠加周期连续的微小抖动。源节点中与原轮廓一致的额外 Polygon2D/CollisionPolygon2D 也会同步；其他装饰随居中偏移。

圆角后按面积质心居中，清空导出根节点的位移、旋转、缩放与斜切，保留 `CollisionBox.scale`，并对齐编辑器中的 `VisualRoot.scale`。源节点和关卡不会被修改。居中后需重新放置新实例；`.recipe.json` 的 `suggested_placement_transform` 按 `[xx,xy,yx,yy,origin_x,origin_y]` 记录保持源轮廓位置所需的根变换。圆角和波点尺寸在碰撞多边形的局部坐标中计算，缩放遵循项目的 LayerObject 约定。

## 参数与内存

| 参数 | 默认值 | 作用 |
|---|---:|---|
| base_color / dot_color | #b8b8b8 / #f2f2f2 | 灰色底面、浅白波点 |
| outer_radius / inner_radius | 26 / 7 | 外角、内角局部半径 |
| outline_width_px | 2 | 按输出纹理像素密度换算的描边宽度 |
| outline_wobble_px / outline_wavelength_px | 0.7 / 18 | 描边抖动幅度与波长 |
| cloud_depth | 85 | 上表面下方波点区域的深度 |
| dot_spacing / dot_radius_ratio | 8 / 0.46 | 六边形错位排布间距、最大半径比例 |
| depth_falloff | 1 | 波点随深度缩小的速度 |
| upward_threshold | 0.65 | 上表面朝上法线分量阈值，过滤陡坡/侧面 |
| seed | 1429 | 可复现的抖动与波点相位 |
| pixels_per_unit / supersampling | 1 / 2 | 输出密度与离线抗锯齿倍率 |
| tile_size_px | 1024 | 分块核心边长，上限 2048 |

底色由 Polygon2D 绘制、描边由 Line2D 绘制，PNG 只包含顶部波点透明层。所有朝上的台阶均可生成波点；波点大小随距上表面距离平滑衰减，轮廓外裁透明。候选采样只扫描顶部条带，空白块不生成，每块裁去无用透明行列。相邻块共享 4px 过滤边距，超采样外侧另设过滤保护区。

例如 20,000×10,000 局部单位的矩形，在默认参数下只有约 20 个顶部波点块，预计 RGBA8 约 5.9 MiB；铺满同尺寸 RGBA8 则约 763 MiB。实际大小取决于轮廓、参数与导入设置。单张 PNG 最大核心 2048px，另加两侧各 4px 边距。

## 验证

普通验证入口：`res://addons/cloud_ground_baker/tests/test_cloud_ground.tscn`，覆盖凹凸圆角、居中、台阶波点、大地面内存、分块接缝、快照、场景结构、碰撞与运行时投影。

编辑器导入与保存验证：

```powershell
& "C:\Program Files\Godot\Godot_v4.7.2-stable_win64.exe" --headless --editor --path . --script res://addons/cloud_ground_baker/tests/test_cloud_ground_editor.gd
```

编辑器测试生成唯一的 `res://Generated/CloudGroundEditorTest_编号` 目录，便于查看结果；测试完成后可删除该目录。该测试验证名称/目录、PNG 导入和外部引用、默认编号、零波点输出、冲突拒绝及源场景不变。
