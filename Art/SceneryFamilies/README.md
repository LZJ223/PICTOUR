# 景物父素材与衍生库

三张父图、十二种独立形态。每片通过 `AtlasTexture` 引用原图中的完整景物，不复制 PNG，也不把同一轮廓仅换色或缩放当作新变体。生成图片及提示词、来源由 `Generated/` 保存；本目录只记录引擎裁切和人工审查后的玩法轮廓。

## 使用

`SceneryFamilyLibrary.create_piece("oldwood_bridge")` 返回可直接放入 `DepthLayer` 的 `SceneryFamilyObject`。可选第二个参数覆盖展示尺寸；或在 Inspector 设置 `piece` 为 `Pieces/` 中的资源，再调整 `dimensions`。根原点在裁切图底边中央。`mirror_x` 同步反转贴图、实体和点选；勿单独翻转 Sprite。

资源继承现有 `PaperStageObject` / `NaturalObject`，继续遵循目标玩家景别的实体占用检查与非玩家景别的自然叠景规则。没有新增加“只能看不能搬”的完整树或建筑。

| 父族 | 子素材 ID | 结构用途 |
|---|---|---|
| 古木 | `oldwood_stump` | 长锯面、侧根与裂心 |
| 古木 | `oldwood_bridge` | 左高右低三肩、下方根孔 |
| 古木 | `oldwood_fork` | 三向断枝与三个不同高度的断面 |
| 古木 | `oldwood_hollow` | 空心根门与左右宽肩 |
| 层岩 | `strata_wedge` | 长高顶与低侧斜坡 |
| 层岩 | `strata_shelf` | 三段浅落差岩檐 |
| 层岩 | `strata_spire` | 高顶、中部悬肩与底座 |
| 层岩 | `strata_hollow` | 石窗下路与左侧侵蚀高路 |
| 残廊 | `arcade_base` | 多段塌墙断面、小券口 |
| 残廊 | `arcade_lintel` | 厚基连接细长悬檐 |
| 残廊 | `arcade_half` | 半券、墙冠与塌砖断口 |
| 残廊 | `arcade_double` | 两道可穿券门与上方长路 |

## 轮廓与裁切

原图实际为 1254×1254，四种形态没有严格限制在四个等分象限中。裁切使用四个主要 alpha 连通块的完整外框，避免按正中线裁断长根或檐口。

`Build_Pieces.py` 保存人工核对后的原图像素坐标，生成十二份 `.tres`。它只序列化资源文本，不改原始图像。每份资源记录父图、裁切范围、默认尺寸、归一化实体、自然可踏边、造型与玩法说明。`Inspect_Atlas.py` 仅用于读取 alpha 边界，不能代替实体设计。

实体包含树干、岩体与砌体，剔除细植物装饰；纸纹缺墨不变成大量微小物理孔洞。宽的根孔、券门和石窗保持可穿。点选由完整裁切图的透明轮廓得到；封闭孔洞若出现在未来素材中，应使用资源的 `picks` 分片描述，避免填满洞口。

可踏边是实体轮廓上既存的断口、切面或侵蚀平肩的标注。`get_footholds()` 仅返回局部坐标线段供摆放/检查，**不生成额外平台**。局部踏面能成立不代表整关路线成立，关卡仍需真实跳跃与往返验证。

## 观察与验证

打开 `Component/SceneryFamilies/Scenery_Family_Catalog.tscn` 按 F6：1/2/3 切素材族，左键与 W/S 换景，4 切两/四景，H 显示自然踏面。观察场不写存档。

`Scenery_Family_Check.tscn` 检查十二片在两层、四层中的往返、视觉位置/尺度连续、固定 layer_id 对应碰撞、真实形状注册、主要洞口及正反镜像下每条标注踏面的真实角色落脚。当前 headless 与实际 D3D12 窗口各 428 项通过。它不声明每片从平地都能直接登顶，不代替美术人工判断。

`Scenery_Family_Capture.tscn` 通过真实 GPU 渲染导出中景、背景与四景目录图到忽略目录 `Exports/SceneryFamilies/`，检查未裁断、洞口通透、层次配色与文字布局。
