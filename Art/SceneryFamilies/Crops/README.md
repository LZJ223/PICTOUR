# 局部派生景物

本轮八件从已存在的父图局部提取：粉墨落扇、折叠双扇、折枝肘、余根、断层薄页、倾斜片岩、旧墙冠、悬檐碎片。它们改变了主体结构与用途，不是整树、整拱的缩放副本。

每件保留 `AtlasTexture` 裁框。为避免矩形截断大主体，在 Godot 中按原纹理 UV 绘制自然轮廓掩片：边界沿细颈、木纹、斜岩层和砖缝拆出短而不齐的断缘。**原 PNG 未改变，掩片是人工派生边界，并非声称父图中原有独立碎片。** 原图生成来源见 `../Generated/` 与 `Art/PaperStage/Generated/`。

`DerivedCropLibrary.create_piece(id)` 或 `Derived_Crop_Object.tscn` 的 `piece` 属性用于实例化，资源位于本目录。保持根/`CollisionBox`/`VisualRoot` 的现有约定；`mirror_x` 同步外观、实体、点选与踏面。粉扇和双扇是非实体薄叶，仍可选取和搬运；其他六片的实体与显示掩片吻合。`get_footholds()` 返回局部断面端点，不添加隐藏台阶。

`Build_Crops.py` 只序列化裁框、掩片与玩法轮廓，不读写图像像素。原生纹理透空和描边保持。`Derived_Crop_Check.tscn` 验证两/四景往返、实际点选、薄叶不阻挡及六件实体正反镜像的真实落脚。GPU检查图位于忽略目录 `Exports/DerivedCrops/01_fragments.png`。

局部碎片需要场景依托：粉扇尖端应接枝头或作为沿岸落叶，折枝肘应接地、依靠残根或参与明确的玩家摆位。把它们孤立悬在大块纸面中会像三角路标或贴纸。主图只建议出现一次完整轮廓，再用这些局部碎片改变疏密，避免所有碎片同高度、同朝向成排摆放。

## 新植物

额外植物父图在 `../Botanical/Generated/`，八种完整透明植物资源位于 `../Botanical/Pieces/`。用 `DerivedCropLibrary.create_botanical(id)` 创建：

- `fern_mat` 匍匐扇蕨，150×68；`moon_reeds` 月轮芦苇，90×216。
- `bell_spray` 弯铃荚，100×144；`broken_fan_bough` 缺扇枝，170×174。
- `flower_clump` 星花簇，90×98；`root_sprout` 细根芽，86×101。
- `hanging_seeds` 垂种带，105×122；`twin_leaf` 双叶苗，105×110。

全部可搬、可点选且没有实体阻挡。植物直接用完整透明 AtlasTexture 显示，无额外掩片；裁框取实际 alpha 主连通块，不按四等分硬裁。细茎在自动简化轮廓后会出现矢量自交，生成器沿交点拆成简单多边形，以便 Godot 正确注册点选；它只读取 alpha 和写资源文本，不修改原图片。

`hanging_seeds` 是垂生植物，根颈在上侧。使用 `get_attachment_offset()` 定位附着点，例如将对象位置设为“目标生长点减该偏移”；其余默认底部依托。需考虑目标景别投影，不能把裸露根颈随意悬在纸面上。GPU检查图位于 `Exports/DerivedCrops/02_botanical.png`。
