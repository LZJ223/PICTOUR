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

## 边缘起跳宽限

`Player_Controller.gd` 的 `jump_grace_time` 默认 `0.10` 秒，可在 Player 检查器中调整，设为 `0` 可关闭。角色离开真实地面后照常下落，仅在短时间内保留一次按键起跳许可；宽限起跳使用原来的起跳速度和动画。成功跳跃立即消耗许可，只有真实落地才能重新补充。没有增加跳跃输入缓冲、自动连跳或空中二段跳。

宽限按物理帧的 `delta` 计时，暂停时随物理冻结。观察目标、对话、通关、进入无人机、回收和改变碰撞图层会清除旧许可。换层只清除新增的宽限状态，原有落地检测、碰撞层切换和无人机进入条件保持不变。物体/角色碰撞箱、贴地与斜坡参数、重力和普通跳跃轨迹均未修改。

复用上面的隔离运行器：

```powershell
./tests/run_destination_view_test.ps1 -Godot 'D:/EpicGames/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe' -Suite jump_grace
./tests/run_destination_view_test.ps1 -Godot 'D:/EpicGames/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe' -Suite jump_grace -WithRendering
```

测试使用真实 Game/Player，将 `CloudBox_01.tscn` 的碰撞轮廓原样复制到静态测试平台，不修改原资源。逐物理帧验证：离地后起跳、超时与关闭宽限、起跳速度、普通跳跃/无输入下落轨迹对比、重复按键与长按、落地补充、暂停、观察/对话/通关、真实无人机进入和回收、真实换层、空中出生、顶头碰撞，以及 30/60/120 Hz 下按秒计时。成功标记为 `JUMP_GRACE_TEST checks=62 failures=0`。旧实现能复现离开圆角两帧后按键不起跳。
