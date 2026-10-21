# 第 11、12 关平地行走补充素材

- 两段 MP4，分别为第 11、12 关，每段 1920×1080、60fps、120 帧、精确 2 秒。
- 全程无 UI、无字幕、无音轨，无附加转场；保留原始关卡、视差、景深、雾效、夜间照明和角色动画。
- 使用真实玩家控制与物理碰撞，以 260px/s 向右行走。先预热 15 帧，再录制 120 帧，每一录制帧均检查着地、水平速度与脚底高度。
- `Walking_Levels_11_12.zip` 包含两个视频；`Preview.jpg` 为中间时刻预览，`Frames_Review.jpg` 为成片首、中、尾帧检查图，编号仅在预览图显示。
- `Shot_Plan.json`、`Capture.json`、`Verification.json` 分别记录路线、实际录制检查与最终视频验证。
- 原生源帧位于 `.godot/promo_walk_11_12_20261021/Shot_11` 与 `Shot_12`，前十段视频不变。

## 重新渲染

在项目根目录运行，按本机安装位置替换 `godot`：

```powershell
godot --headless --path . --fixed-fps 60 --audio-driver Dummy res://Promo_Renders/20261021_Level_Walk_11_12_2x2s_1080p60/Source/Walk_Capture.tscn -- --probe
godot --path . --audio-driver Dummy --rendering-method mobile --rendering-driver d3d12 --resolution 1920x1080 --fixed-fps 60 --disable-vsync res://Promo_Renders/20261021_Level_Walk_11_12_2x2s_1080p60/Source/Walk_Capture.tscn
python Promo_Renders/20261021_Level_Walk_11_12_2x2s_1080p60/Source/Encode_Verify.py
```

捕获场景复用前十段的工具，通过场景参数只生成第 11、12 关；仅宣传渲染进程关闭界面、对话、收集和过关触发器，不改动正常游戏逻辑、关卡或存档。
