# 绘本箱庭母素材

本轮围绕项目已认可的 `Art/Concepts/Paper_Garden_01.png`，增加两张连贯的大形母图。与 GRIS 参考图的关系是构图和结构分析；没有把参考截图中的像素作为游戏素材。

生成方式：内置 `image_gen`；工具没有报告可确认的模型名称。原 PNG 像素与透明通道完整保留，碰撞、裁区、镜像及衍生在 Godot 中实现。

| 母图最终保存位置 | 功能轮廓 | 最终完整提示词与来源 |
| --- | --- | --- |
| [Page_Spine_Tower.png](Generated/Page_Spine_Tower.png) | 页脊塔：连贯基座、中空拱腔、左侧断肩与不对称冠檐；断肩承担上升，拱腔承担穿行 | [提示词](Generated/Page_Spine_Tower.prompt.txt)、[来源](Generated/Page_Spine_Tower.source.json) |
| [Fallen_Page_Bridge.png](Generated/Fallen_Page_Bridge.png) | 断页根桥：根结承托缓升页背，右檐卷起形成空腔；桥上和桥下的通行由同一轮廓决定 | [提示词](Generated/Fallen_Page_Bridge.prompt.txt)、[来源](Generated/Fallen_Page_Bridge.source.json) |
| [Page_Strata_Surface.png](Generated/Page_Strata_Surface.png) | 地貌内墨纹：弯曲页层、细裂纹与压印化石，属于连续岸体的材质；没有另做不可搬的景物 | [提示词](Generated/Page_Strata_Surface.prompt.txt)、[来源](Generated/Page_Strata_Surface.source.json) |

页脊塔与根桥尺寸分别为1347×1168和1999×786，RGBA；地貌内墨纹为1672×941，RGB。碰撞依据粗根/石的真实实体轮廓，花梢、细叶和毛边不填作厚实体。拱腔与卷檐空白必须同时保留在图像、实体和点选中。不要用图像矩形代替碰撞，不新增图像没有的隐形踏面。

断片裁区、源根点、形状及使用位置由 `Component/IllustratedGarden/` 资源记录。父素材可以派生不同断帽、侧肩和断根，但重复摆放完整母图、仅改变色调不算有效丰富度。每个派生体跟随所属图层搬运，不能以同图的不可搬版本伪造背景丰富度。

地图应表现结构的因果关系：基座连地、枝/页脊连接主体、断片围绕对应断口、上下路线出自同一岸体。允许有叙事理由和构图节奏的悬浮断片，不能让任意小平台均匀撒满画面。固定地貌与抽象纸面封装不计入可搬景物；可辨认的树、岩、拱门和植物遵循统一换层规则。
