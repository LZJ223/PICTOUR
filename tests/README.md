# 目标观察回归

在项目根目录运行（PowerShell）：

```powershell
./tests/run_destination_view_test.ps1 -Godot 'D:/EpicGames/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe'
./tests/run_destination_view_test.ps1 -Godot 'D:/EpicGames/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe' -WithRendering
```

脚本在临时目录创建测试工程配置，以目录联接复用工程资源，存档固定隔离在 `PICTOUR_destination_view_qa` 用户目录。正常游戏配置、键位和进度不变。测试场景拒绝在正常存档目录运行；日志路径会打印到控制台。测试会改写隔离存档的键位，不应同时运行多个实例。

测试实例化真实 Game，注入 `InputEventKey`，检查观察状态、相机坐标、音效通道和相邻玩法。包括正常长按/松开、重复键、动画中快速连按、缺少物理键码的松键、左右 Shift、失焦/返回、暂停、设置拦截输入、对话、改键、重开、菜单重入、进入下一关、日间和黑夜关卡，以及观察时屏蔽移动/换层/UAV、松键后恢复移动。

故障复现：左 Shift 按下事件包含物理/逻辑键码和左侧位置，松开事件只包含逻辑键码。Godot 4.7.2 的动作缓存与物理键缓存均仍为 true，原实现会持续观察目标，并在重新创建 Game 后再次触发。修复为观察操作增加真实按键事件记录，松开可回退到按下时的逻辑键码进行匹配；失焦和改键清除记录，缓存残留不能独自启动观察。原有镜头 Tween 和其他玩法保持不变。

此用例证明了可导致所述现象的输入路径；尚未采集故障设备的原生键盘事件，不能据此断言其驱动或输入法就是触发来源。失焦测试发送窗口信号，键盘测试使用引擎事件注入，不替代故障设备上的人工复测。

成功标记为 `DESTINATION_VIEW_TEST failures=0`，退出码为 0。原工程在退出时已有 ObjectDB/资源回收警告，本次旧代码与修复版均可复现；详见 `Opening/README.md`，不属于本次输入修复范围。
