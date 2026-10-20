# 字母收集物

将 `Collection.tscn` 直接拖到关卡的 `DepthLayer` 下，在检查器的 **Character** 中选择 P、I、C、T、O、U、R。编辑器会切换到对应的 `Texture/Logo/Collection_字母.png`，贴图缩放固定为场景中的 `0.25`。移动场景根节点调整摆放位置；拾取圆的半径可在 `VisualRoot/Motion/Area2D/CollisionShape2D` 调整。

根节点为 `StaticBody2D`，没有实体碰撞箱。物件不可选取或换层，不投影、不参与影子切割，并在所属图层内前置绘制；Area2D 的 `z_index` 为 999。只接受同图层、正常状态的 `Global.player`，无人机、收回期间的飞行器、留在原处的玩家身体代理以及其他物体均不能触发。玩家已经重叠时收回无人机或切换到对应图层，也会重新检查。

待机时上下浮动、缓慢随机倾斜。有效拾取开始时播放一次清脆三角铁声，然后先下沉 16 像素（0.12 秒），再上升 100 像素并淡出（0.48 秒）；这些参数可在检查器调整。动画只修改 `VisualRoot/Motion`，不会与景深系统争抢变换，暂停时动画也暂停。音效遵循 SFX 音量，物件停用后余音仍会自然结束。

动画结束后调用 `SaveSystem.collect_character(character)`，成功落盘再隐藏并停用。写入失败会恢复物件供玩家重试。已收集的同字母实例在 `_ready()` 中直接停用；重复放置同一字母仍只记录一次。

`user://progress.json` 的 `collected_letters` 保存七个独立布尔值，键为 `P I C T O U R`，初始均为 false。旧存档会补齐此字段，保留关卡、偏好、音量和键位。查询使用 `SaveSystem.is_character_collected(character)`，变化通过 `collection_changed` 通知；Main 的七个 `Logo_字母` 同步显示，Logo_Back 和 Logo_Front 保持原有摆放。

“重置存档”清空关卡和字母收集进度，保留游戏偏好、音量和自定义键位；当前场景内已停用的收集物也会恢复。

回归入口为 `Tests/Collection_Test.tscn`，请使用隔离的用户目录。第二次启动追加 `-- --verify-persisted` 可验证七个字母跨进程恢复。测试截图输出至 `.godot/collection_qa/`。

在项目根目录执行以下 PowerShell 命令；测试会拒绝使用游戏的正常用户目录。写盘失败用例会有预期的“写入存档失败”日志，用来确认物件能恢复、可以重新拾取。

```powershell
$collectionTestData = Join-Path (Get-Location) '.godot/collection_qa/local/AppData'
New-Item -ItemType Directory -Path $collectionTestData -Force | Out-Null
$env:APPDATA = $collectionTestData
$env:LOCALAPPDATA = $collectionTestData
godot --headless --path . res://Component/Collection/Tests/Collection_Test.tscn
godot --headless --path . res://Component/Collection/Tests/Collection_Test.tscn -- --verify-persisted
```
