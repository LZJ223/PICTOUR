# PICTOUR

Godot 4.7.2 制作的 2.5D 平台解谜游戏。玩家改变站位，利用图层视差重新组合路径，再把背景中的物件搬入玩家层。

项目参加 TapTap 2026「聚光灯」21 天游戏创作挑战，主题为「涌现」。[官方公告](https://www.taptap.cn/moment/854692229854265392)

`dev` 是用户从 `main` 起步的大地图与美术实验路线，已跟踪 `origin/dev`。队友另一路探索关卡式设计，尚未上传 GitHub。先做 Windows 原型；开发基线快照为 `8bee01e`。2026-10-10 用户授权清理旧实验并提交、同步 dev；后续提交、推送和合入 main 按明确指令执行。

## 运行与操作

使用 Godot `4.7.2-stable` 导入 `project.godot`，按 **F5** 运行 `Illustrated_Garden_Game.tscn`：新「折页庭园」箱庭与完整V7角色。也可双击 [Play_Illustrated_Garden.cmd](Play_Illustrated_Garden.cmd)。此前的 `Story_Garden_Game.tscn`、`Vertical_Garden_Game.tscn`、`Paper_Stage_Game.tscn`、`Natural_Garden_Game.tscn`、旧白模 `Prologue_Test_Game.tscn` 与四层原型 `Prototype_Game.tscn` 均保留，可打开后按 F6 运行。

Windows 原型默认 **关闭 VSync、渲染上限 240 FPS**，物理保持 60Hz 并开启插值。这组配置已由用户在独立与编辑器内嵌窗口确认顺滑；原同步开启的窗口存在整幅画面抖动，提示问题与此环境开启同步时的帧率／呈现节奏有关。项目配置更新后需停止并重新运行，关闭同步可能出现撕裂。

双击 [Play_Standalone.cmd](Play_Standalone.cmd) 独立试玩；[Play_NoVSync.cmd](Play_NoVSync.cmd) 保留显式关闭同步的入口。需要复查时使用 [Play_VSync.cmd](Play_VSync.cmd)，它在相同关卡、1280×720 与 240 FPS 上限下仅临时开启同步，退出后不改变默认配置。启动器默认读取同级 `Godot/4.7.2` 引擎，其他电脑可设置 `GODOT_EXE` 指向自己的引擎。

| 操作 | 按键 |
|---|---|
| 左右移动 | A / D |
| 短冲刺 | 短按 Shift，在释放时触发 |
| 持续奔跑 | 按下 Shift 立即开始加速，持续按住保持 |
| 轻跳、长跳、跑跳或冲跳 | Space；按住跳得更高，起跳保留横向速度 |
| 选择物件、再次点击取消 | 鼠标左键；空白处也可取消 |
| 将选中物件移近一层 | W |
| 将选中物件移远一层 | S |
| 撤回成功换层，同时恢复全场摆位与当时站位 | Z（新绘本及折页井） |
| 回到本庭园的初始摆位 | R（新绘本及折页井）；旧Story庭园回最近书签 |
| 在附近凝墨书签记录摆位 | E（保留的旧Story等书签样板） |
| 打开书签地图，选择已发现的书签返回 | M；Esc 关闭（保留的书签样板） |
| 隐藏／显示教学，观察美术与交互反馈 | F8 |

0.18 秒只用于判断松开 Shift 时是否触发短冲刺；长按释放不会额外冲刺。

序章只有玩家层和背景层，倍率为 `1.0 / 0.8`，禁止整体轮换、无人机和挪动自己。玩家改变站位后，背景物件相对地形的位置变化；搬入时保留当前可见位置和尺寸，成为固定、可站立的实体。物件不受重力影响。新绘本与折页井在两个景别都检查真实实体占用；保留的旧自然/Story样板显式允许非玩家景别的自然景物遮叠，墙体与角色仍阻挡。两种试验规则分别保留，不混作同一默认规则。

## 当前样板：折页庭园

新地图将根井、页脊塔和天际回廊连接为约4600px宽、1220px高差的上下探索空间。卷根门、垂腹枝和伏根提供不同摆放顺序的高/低路径；页脊塔的断肩进入第二片高区，背景断页根桥接入断口，东侧下降路线可回到前庭。路线必须可以自然返回，Z/R只作操作恢复。它是可玩箱庭与美术迭代，尚非完整序章或第一章成品。本轮整合记录见 [V7与布景台](ProjectLogs/绘本箱庭_V7与布景台_2026-10-09.md)。

主角改用 `Component/Player/V7/Traveler_V7.tscn`。作者化关键姿态驱动收腿、蹬离和舒展；衣页/内衬、长发和红围巾以连续曲线形变绘制，走跑、跳跃、短冲、起停和反向在同一可玩角色中。视觉轮廓优先于固定骨长；实体仍保持原身高、移动/跳跃与12px跨步。打开 `Art/Player/V7/Traveler_V7_Lab.tscn` 按F6观察多种真实动作。来源、接口及艺术审阅边界见 [V7说明](Art/Player/V7/README.md)。不能把功能测试或绘制连续性当作“已达到GRIS水准”的证明。

场景素材增加页脊塔、断页根桥及实际轮廓裁片；根点、图像、实体和可踏边一起保存。大岸体以拱腹、窄脊和断口组织通路，固定内容仅连续地貌与抽象纸墨封装，独立树/岩/拱门/花草都可换层。母图、完整提示词与生成来源见 [绘本素材记录](Art/IllustratedGarden/README.md)。

该样板不读写玩家存档，R恢复初始世界，坠出边界安全返回，记忆收集只在本次运行保留。E/M凝墨书签仍在旧Story样板中；持久化、最近保存点和完整序章节奏尚未迁入此新布局。

## Godot专用布景台

项目已启用 `addons/pictour_garden_editor/`。在左侧「布景台」点击「打开新绘本地图」，编辑 `Level/Illustrated_Garden_Level.tscn`：搜索素材→选中/背景→填根坐标或点击画布放入；也可使用原生视口拖动与Inspector修改尺寸/镜像。Ctrl+Z/重做与Ctrl+S操作实际场景文件。

面板可显示真实实体/踏边及静态换层占用预览，预览Y从Level的同一投影基准读取。修改 `Level.spawn` 会实际改变运行出生点。复制节点后可点击「检查/修复重复身份」，保证换层撤回识别每件物体；修复同样可撤回。面板不另存一套布局，不修改原母素材；原生2D视口、场景树和Inspector继续承担通用编辑功能。鼠标画布点击与辅助线屏幕映射需在用户窗口试玩，自动编辑器验证不代替这一项。详见 [布景台操作及成本](ProjectLogs/专用布景编辑器_2026-10-09.md)。

## 保留样板：未完的庭园

本轮将独立的解谜展示区重组为约2580px的连续路径：树荫出发、缓坡庭院、断页河谷、远岸墨台。三枚凝墨书签分别记录起点、庭院与远岸的全场摆位；使用独立 `user://Story_Garden_Save.json`。它是序章空间研究片段，尚未覆盖完整7–10分钟流程。

两层各自拥有地貌轮廓，背景景物与所属地平线共用视差投影。主岸下沿独立设计，保留厚薄变化和断谷留白；景物按生长、坍塌和依托关系成簇。原三族素材另派生8种局部断片，新植物父图提供8种不同剪影，场景选用其中4种建立高、中、低层次。所有独立树、枝、岩、建筑和植物可搬；固定世界底面与连续纸面色洗保持环境职责。

中央断谷仍能选择残拱高路或页石＋伏根低路，两种解法都能往返。沿途可以先练习缓坡和低岩跳跃，再观察背景景物与断岸关系。未摆物时无法直接冲跳越过河谷。具体站位、素材摆放与验证见 [叙事庭园重构](ProjectLogs/叙事庭园重构_2026-10-09.md)。

**V6角色候选**保持 C 款长发、修长叠页衣与植物印纹，改用同一张透明母图的头发、衣身、衣摆和肢体分件，连续求解动作。轻盈方向采用小幅前倾、低位摆臂、较小重心起伏和坡面缩步；走跑保持同一周期，脚点依据真实地形，近远腿身份固定。红围巾独立响应加减速并保留弧度和下垂。物理帧求姿态，渲染帧插值网格，不改原60Hz物理与240FPS上限。180/320/560px/s速度、30×86碰撞与约108.6px满跳保留。分件连续性仍需人工审阅，不能把骨段或脚锚验证通过当作动作美术定稿。

用户同日提供GRIS跑动实录后，明确认为V6动作差距过大。逐帧复核确认上身与衣形过于僵直，低扫地、短周期步态仍显机械；这版未通过动态美术审阅，作为旧Story样板与技术验证记录保留。新的完整角色见前面的V7入口。

旧 RunStudy 关键姿态对照场已从当前树归档；作者化曲线仍由 V7 使用，位于 `Component/Player/Shared/Authored_Run.gd`。历史对照与实录说明见 [GRIS跑动对照](ProjectLogs/GRIS跑动对照_2026-10-09.md)，旧场景可从 `8bee01e` 恢复。

V6/V7共用 `Component/Player/Shared/Traveler_Step_Controller.gd` 的约12px自然跨步：走、跑、短冲经过低石沿时，先确认全身上方净空和另一侧真实踏面，再越过；13px以上台沿、高根侧壁和空中障碍仍不能自动攀爬。动画起停读取操作意图与实际行程，50ms以内的短暂接地丢失不误插下落/落地，真实起跳立即响应。详见[跨步实现](ProjectLogs/自然跨步实现_2026-10-09.md)、[坡面步态诊断](ProjectLogs/坡面步态修复_2026-10-09.md)。

打开 `Art/Player/V6/Traveler_V6_Lab.tscn` 按F6，对照平地走跑、18°上坡、28°下坡；Space暂停、R重播、1/2切观察倍率。共享分件母图、提示词和来源位于 `Art/Player/Traveler_C/`，V6拼装参数保存在 `Art/Player/V6/`。旧16帧AI动作已归档，制作记录见 [角色动作V5](ProjectLogs/角色动作V5_2026-10-09.md)；裁片与植物用法见 [派生素材说明](Art/SceneryFamilies/Crops/README.md)。旧图集的重复腿姿与衣摆跳变不会因增加图片数量而自然解决。

当前V6动作实录为 `Exports/Traveler_V6_Lab.mp4`，庭园最新截图在忽略目录 `Exports/Story_Garden/`。`Exports/Story_Garden_Playthrough.mp4` 与 `Exports/Traveler_V5_Lab.mp4` 是旧V5版本记录。场景与素材均能直接在编辑器调整；完整序章、最终构图、美术和音效仍待迭代。

旧V5播放顺序和坡面观察场已归档。当前跨步回归 `Tests/Traveler_Step_Regression.tscn` 直接验证V7活体，坡面与动作状态由 `Tests/Traveler_V7_Check.tscn` 覆盖；历史结果不等于原图集已自然流畅。

这一轮已接入V6分件动作，纵向相机、背景真实占用和完整撤回规则在独立「折页井」验证。原庭园保留现有背景遮叠规则和凝墨书签；新试验不写玩家存档。早期方案见[动画制作与可逆空间提案](ProjectLogs/动画制作与可逆空间提案_2026-10-09.md)、[三主体纵向空间提案](ProjectLogs/纵向少元素设计提案_2026-10-09.md)与[空间示意图](ProjectLogs/Designs/Vertical_Garden_Study.svg)，实际布局以后续实现和场景为准。

未采用的 MotionStudy 动作灰稿已归档；方法与否决原因保留在日期日志及 `8bee01e` 历史中。

## 独立纵向试验：折页井

`Vertical_Garden_Game.tscn` 使用卷根门、垂腹枝桥、伏根三个主实体，沿折壁、凹地和上缘展开往返路径。新卷根与枝桥母图依据已认可的纸墨概念图生成，断肩、曲背与根腹同时决定图像和真实可踏轮廓。固定纸岸与背景折壁提供自然依托和有限空腔；两层都检查实体占用，不能通过背景穿插收纳物件。

卷根断肩构成较高的登行路径；送远卷根后，可以借枝桥跨过下方凹地，再利用共同的伏根上升。枝桥在不同站位搬近，会改变桥面高度和下方净空；背景空腔也限制卷根的退入位置。这里用同一组物件测试摆放顺序和路线取舍，尚未穷举所有解法。

选择物件时显示目标实体轮廓：绿色可落入，红色表示阻挡，接触处有少量标记。**Z** 撤回最近一次成功换层，并恢复换层前的全场摆位和角色站位；拒绝的换层不占历史。**R** 回到本试验的初始摆位，坠出边界也会安全返回。这里不使用 E/M 凝墨书签、不读取或写入进度文件。

镜头随纵向攀登移动，解谜投影的纵向基准保持固定；抬升镜头不会额外搬动背景。该场景用于研究少元素的纵向空间与可逆操作，尚不是完整序章或最终地图。新母图和生成提示词见 [折页井素材说明](Art/VerticalGarden/README.md)，撤回规则见 [纵向投影与撤回](ProjectLogs/纵向投影与撤回_2026-10-09.md)。

这一轮角色与场景的集成、实际验证和剩余限制见 [轻盈步态与折页井整合](ProjectLogs/轻盈步态与折页井整合_2026-10-09.md)。

## 旧实验归档与共享素材

2026-10-10 清理了 V4/V5 旧角色图集、MotionStudy/RunStudy 展示场、GardenStudy 旧组合场和一次性调试入口。它们保存在基线提交 `8bee01e`，本机还有被忽略的 `Exports/Archived_Experiments_8bee01e/` 可逆归档；日期日志保留当时事实。清理通过普通新提交完成，不重写历史。

当前角色共享控制器、围巾着色器和作者化曲线放在 `Component/Player/Shared/`；C款母图与来源记录放在 `Art/Player/Traveler_C/`。当前地图、V7、布景台及仍有回归/素材依赖的旧样板保留。母图来源中引用的 V4 选择图属于生成历史，可从基线恢复，不是运行依赖。

`Component/SceneryFamilies/Scenery_Family_Catalog.tscn` 仍可按F6观察十二种父图衍生轮廓：1/2/3切素材族，左键与W/S换景，4切两/四景，H显示踏面；不写存档。衍生素材仍被当前地图和布景台使用，见 [素材说明](Art/SceneryFamilies/README.md)。完整清单与验证见 [工程清理记录](ProjectLogs/工程清理_2026-10-10.md)。

## 保留的上一版画页与动作观察场

「折页之间」先验证一组完整构图与跨岸回路，尚不是完整序章。围绕已认可的 `Art/Concepts/Paper_Garden_01.png`，重做斜生扇树、非对称残拱、露出下沿的断裂纸岸和独立淡墨环境。主树与残拱使用新生成的透明美术；其实体轮廓按图追踪，拱洞保留为空。其他岩石、植物和长窗遗迹也能换层，纸面与连续环境色洗不可搬。

建议先站在初始书签附近，将右侧残拱搬入中景，再用 **Shift 跑跳**登上左侧第一处断口，逐段到拱顶取墨；越过缺口到右岸书签。返程可借右岸斜石跳上右拱檐，再经上方小折口回到拱顶。R 或坠落返回最近书签，墨水仍保留。此场景单独使用 `user://Paper_Stage_Save.json`，不覆盖上一版庭园进度。

V3 角色为原创侧视直身衣装，走／跑各16帧，奔跑有腾空阶段；动画依实际位移推进，红围巾是带长度和弯曲约束的独立哑光布条。主控制器参数不变：30×86碰撞，满跳约108.6px。角色造型与手感还需要人工审阅，自动检查不代表美术定稿。

打开 **`Tests/Traveler_V3_Lab.tscn` 按 F6**，可同时观察待机、步行、奔跑、刹停转身。Space 暂停／继续，R 重播，1／2 切换观察倍率；地面细线用于判断脚底打滑。该观察场的四格演示驱动与正常游戏输入分开，实际玩法另由画页回归验证。

实现、素材来源、可玩路线与限制见 [画页美术与侧视动作迭代](ProjectLogs/画页美术与侧视动作迭代_2026-10-09.md)。本机实录位于 `Exports/Traveler_V3_Lab.mp4`；初始、换层、登顶与返程截图位于 `Exports/Paper_Stage/`（调试产物不提交）。

## 保留的上一版自然庭园

自然地平线固定；树、岩石、拱门、枯枝和小植物全部遵循同一搬运规则。不存在“背景树可搬、同层拱门只是装饰”的例外。远层是浅鼠尾草墨色，玩家层是梅紫实体，鼠标悬停／选中出现墨线；红色用于角色围巾与凝墨书签。

人物约 90px 高，碰撞 30×86，满跳实测约 108.6px（约身高 1.2 倍），轻跳约 41.2px。直身工作服、短手臂和细线双腿，走／跑各 16 帧；围巾由独立的 8 点惯性丝带绘制，跟随奔跑、转身和跳跃。

庭园有约 3000px 的连续探索区域与一处纸岸缺口。可以搬入三折枯枝走较低路线，也可以搬入空心拱门，沿侧面踏阶到拱顶收墨后越过缺口；折枝树与岩石提供其他落点。这里用于验证景物能否自然组合，尚不是完整序章。

拱门洞口真实为空，顶部和侧阶可站立；枝与树的踏面按自身轮廓碰撞。点选跟随景物实体轮廓，不会在拱洞空白处选中建筑。花草只有点选轮廓，不阻挡行走。玩家层允许接触地面，拒绝实体互相穿入；非玩家景别允许景物遮叠，换站位、送回背景后可以再尝试。

「纸岸」「折枝庭」两枚凝墨书签记录**全场可搬景物**。R、坠落与地图返回恢复对应书签的摆位；墨水、能力和已发现书签独立保留。进度写入本机 `user://Natural_Garden_Save.json`，退出重开可接续；恢复点被景物占用时寻找附近安全落点。返回纸岸书签可以重新尝试另一条路线。

四景开发入口为 `Tests/Natural_Layer_Lab.tscn`（F6），只用于检验单物件移入前／中／背／远景，未开启新的序章能力。完整图层轮换仍在旧四层原型中检验。

美术来源、设计取舍、验证与试玩说明见 [自然绘本样板实现](ProjectLogs/自然绘本样板实现_2026-10-09.md)。

## 保留的旧白模

`Prologue_Test_Game.tscn` 保留原 40px 人物与下列测试片段，用于公共机制回归：

| 片段 | 验证目标 |
|---|---|
| 移动与跑跳 | 走过矮台、短冲与长跑、跨越练习沟 |
| 移树与搬箱 | 将挡路树送入背景；搬入背景箱，借它跳上高台触发机关门 |
| 拼桥与画室 | 调整站位后搬入桥段，用跑跳跨越缺口；收集墨水，带回空画卷 |

旧场景保留六组 8 帧图集、矩形物件贴图和朱砂纸签，R 仅恢复本片段三件物品，收集不写磁盘。F1/F2/F3 快速切段、F4 诊断、F7 镜头对照属于这个旧场景；新庭园使用完整书签摆位恢复。

角色、相机和视差投影统一在 60Hz 物理帧更新，并开启物理插值，补足高刷新率下的中间画面；物理频率无需与 240Hz 屏幕相等。F4 显示内嵌／独立状态、实际渲染 FPS、物理 Hz、运行时插值状态、窗口所在屏幕的系统刷新率、VSync、帧 P95、最大帧间隔和绘制画布回拉计数。F7 可固定镜头作对照；F4 关闭、R 和切段会恢复正常跟随。关闭 F4 时将最近最多 600 张绘制画面的逻辑位置写入本机 `user://MotionDiagnostics/`，不做截图读回。屏幕支持的最高刷新率、系统报告值、游戏产出帧率和最终显示节奏需要分别核实，录屏正常也不能直接排除呈现问题。

完整序章的播片、能力失去过程、7–10 分钟节奏、最终美术与音效尚待制作。旧素材与试玩记录见 [美术白模实现](ProjectLogs/美术白模实现_2026-10-08.md)。

## 旧四层原型

Level 默认参数仍为四层，倍率 `1.25 / 1.0 / 0.8 / 0.64`，由 `layer_scale ^ (slot - current_layer_index)` 生成。固定 `layer_id` 决定碰撞身份，可变 `slot` 决定景深显示。

旧原型保留 Q/E：未选中时整体轮换，选中后搬运物件；Page Up 切换无人机，W/S 控制无人机上下飞行。新版 W/S 单物件搬运仅在人物状态执行。影子与 Goal 仍是早期原型，未形成正式关卡流程。

## 验证与结构

在项目根目录运行，其他成员替换引擎路径：

```powershell
$godotExe = 'D:\EpicGames\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path . --editor --import
& $godotExe --headless --path . --quit-after 120 -- --no-save
& $godotExe --headless --path . res://Tests/Traveler_V7_Check.tscn
& $godotExe --headless --path . res://Tests/Illustrated_Garden_Regression.tscn
& $godotExe --headless --path . res://Tests/Illustrated_Garden_Restore_Check.tscn
& $godotExe --headless --path . res://Tests/Garden_Editor_Projection.tscn
& $godotExe --headless --editor --path . -- --garden-editor-test
& $godotExe --headless --path . res://Tests/Story_Garden_Regression.tscn
& $godotExe --headless --path . res://Tests/Traveler_V6_Check.tscn
& $godotExe --headless --path . res://Tests/Vertical_Garden_Regression.tscn
& $godotExe --headless --path . res://Tests/Study_Transfer_Regression.tscn
& $godotExe --headless --path . res://Tests/Study_Transfer_Regression.tscn -- --v6
& $godotExe --headless --path . res://Tests/Study_Transfer_Level_Check.tscn
& $godotExe --headless --path . res://Tests/Study_Transfer_V6_Bookmark.tscn
& $godotExe --headless --path . res://Tests/Traveler_Step_Regression.tscn
& $godotExe --headless --path . res://Component/SceneryFamilies/Derived_Crop_Check.tscn
& $godotExe --headless --path . res://Component/SceneryFamilies/Scenery_Family_Check.tscn
& $godotExe --headless --path . res://Tests/Paper_Stage_Regression.tscn
& $godotExe --headless --path . res://Art/Player/V3/Traveler_V3_Check.tscn
& $godotExe --headless --path . res://Component/PaperStage/Paper_Stage_Component_Check.tscn
& $godotExe --headless --path . res://Prototype_Game.tscn --quit-after 120
& $godotExe --headless --path . res://Tests/Prologue_Regression.tscn
& $godotExe --headless --path . res://Tests/Prologue_Playthrough.tscn
& $godotExe --headless --path . res://Tests/Natural_Regression.tscn
& $godotExe --headless --path . res://Tests/Natural_Playthrough.tscn
& $godotExe --headless --path . res://Tests/Natural_Return_Regression.tscn
& $godotExe --headless --path . res://Tests/Bookmark_Regression.tscn
& $godotExe --headless --path . res://Art/Player/V2/Traveler_Large_Check.tscn
```

必须检查日志与有效断言数量，不能只看退出码。测试与试玩清单见 [序章白模实现记录](ProjectLogs/序章白模实现_2026-10-08.md)。自动回归和画面检查不代替人类手感验收；尚无 Windows 导出预设或投稿包。

- `Component/`：公共图层、玩家与物件；自然景物 `Natural_Object/`、固定地平线 `Terrain/`、凝墨书签 `Bookmark/`。
- `Level/`：关卡参数与场景；`Illustrated_Garden_Level` 为当前静态箱庭，`Story_Garden_Level` 等仍有验证用途的旧样板保留；GardenStudy已归档，`Bookmark_Manager` 管理旧样板摆位和进度。
- `Component/StoryWorld/`：自定义固定岸体和与背景同层投影的世界底面；不包含不可搬的树或建筑。
- `System/`：输入、选中、相机、碰撞检查及换层协调。
- `Tests/`：轻量 Godot 行为回归与实际关卡通路验证。
- `Art/`：概念图、角色图集、场景精灵、原始绘图与来源记录。
- `ProjectLogs/`：设计、协作与实现记录。

## 协作入口

- [Agent 工作约定](AGENTS.md)
- [人机协作与 Git 规范](ProjectLogs/协作与Git规范.md)
- [项目初次审查与赛事基线](ProjectLogs/项目总览_2026-10-08.md)
- [序章白模实现与试玩步骤](ProjectLogs/序章白模实现_2026-10-08.md)
- [绘本世界美术定调提案与概念图](ProjectLogs/美术定调提案_2026-10-08.md)
- [美术白模实现与素材说明](ProjectLogs/美术白模实现_2026-10-08.md)
- [自然绘本样板实现与试玩](ProjectLogs/自然绘本样板实现_2026-10-09.md)
- [背景景物送回修复](ProjectLogs/背景景物送回修复_2026-10-09.md)
- [画页美术与侧视动作迭代](ProjectLogs/画页美术与侧视动作迭代_2026-10-09.md)
- [早期游戏策划案](图层转换平台解谜游戏策划案.md)

带日期的旧文档保留历史状态，当前运行行为以 README 和实际代码为准。
