# 2026-10-09 美术母素材与生成提示词

生成方式：内置 `image_gen` 工具。工具未报告模型名称。本轮没有调用回退 CLI，也没有生成完整逐帧动画。下列 PNG 保留生成工具的原始像素；角色拆分和场景衍生在引擎中实现。完整最终提示词与来源记录按素材分别保存。

| 用途 | 最终保存路径 | 完整最终提示词 | 来源记录 |
| --- | --- | --- | --- |
| C 旅人拆分母图 | [Traveler_C_Rig.png](Player/V6/Generated/Traveler_C_Rig.png) | [Traveler_C_Rig.prompt.txt](Player/V6/Generated/Traveler_C_Rig.prompt.txt) | [Traveler_C_Rig.source.json](Player/V6/Generated/Traveler_C_Rig.source.json) |
| 卷根门场景母图 | [Curled_Root_Gate.png](VerticalGarden/Generated/Curled_Root_Gate.png) | [Curled_Root_Gate.prompt.txt](VerticalGarden/Generated/Curled_Root_Gate.prompt.txt) | [Curled_Root_Gate.source.json](VerticalGarden/Generated/Curled_Root_Gate.source.json) |
| 垂腹枝场景母图 | [Hanging_Bough_Bridge.png](VerticalGarden/Generated/Hanging_Bough_Bridge.png) | [Hanging_Bough_Bridge.prompt.txt](VerticalGarden/Generated/Hanging_Bough_Bridge.prompt.txt) | [Hanging_Bough_Bridge.source.json](VerticalGarden/Generated/Hanging_Bough_Bridge.source.json) |

`Run_Study` 使用第一张母图的已有像素，关键姿态、衣物形变和围巾运动由引擎脚本驱动；它是动画制作方法的候选验证，还未达到角色最终美术标准。

## 本轮绘本箱庭新增

仍使用内置 `image_gen`，未使用回退 CLI。两张场景母图为透明RGBA，第三张为不透明RGB地貌内材质；原像素未改。V7主体衣发与围巾由引擎原生曲线编绘，保留原母图头部像素，不是生成的完整逐帧精灵图集。

| 用途 | 最终保存路径 | 完整最终提示词 | 来源记录 |
| --- | --- | --- | --- |
| 页脊塔 | [Page_Spine_Tower.png](IllustratedGarden/Generated/Page_Spine_Tower.png) | [Page_Spine_Tower.prompt.txt](IllustratedGarden/Generated/Page_Spine_Tower.prompt.txt) | [Page_Spine_Tower.source.json](IllustratedGarden/Generated/Page_Spine_Tower.source.json) |
| 断页根桥 | [Fallen_Page_Bridge.png](IllustratedGarden/Generated/Fallen_Page_Bridge.png) | [Fallen_Page_Bridge.prompt.txt](IllustratedGarden/Generated/Fallen_Page_Bridge.prompt.txt) | [Fallen_Page_Bridge.source.json](IllustratedGarden/Generated/Fallen_Page_Bridge.source.json) |
| 地貌内页层材质 | [Page_Strata_Surface.png](IllustratedGarden/Generated/Page_Strata_Surface.png) | [Page_Strata_Surface.prompt.txt](IllustratedGarden/Generated/Page_Strata_Surface.prompt.txt) | [Page_Strata_Surface.source.json](IllustratedGarden/Generated/Page_Strata_Surface.source.json) |
