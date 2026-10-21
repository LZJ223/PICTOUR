# 关卡平地行走素材：10 段 × 2 秒

- `Walk_01_Level_01_2s_1080p60.mp4` 至 `Walk_10_Level_10_2s_1080p60.mp4`：分别来自关卡 1～10，十个不同场景。
- 每段 1920×1080、60fps、120 帧、恰好 2 秒，H.264 High，全部无 UI、无字幕、无音轨，不附加渐入渐出，方便直接剪辑。
- `All_10_Walking_Clips.zip` 打包十个视频；`Preview.jpg` 是十段成片在第 1 秒的编号预览，编号只存在于预览图。

使用原始 `Game.tscn` 和各关卡场景，保留视差、景深、雾、夜间照明、角色动效与跟随相机。角色通过原 PlayerController 注入正常向右输入，以 260px/s 行走，不是假移动背景或后期贴入角色。

在真实碰撞空间中筛选连续平地并检查头顶、前方净空。先预热 15 帧，确保角色已落地并开始运动，再录制 120 帧；每一录制帧都验证着地状态、速度和脚底高度，拒绝跳跃、跌落、阻挡和起步停顿。关卡地形未修改。

`Shot_Plan.json` 记录路线；`Capture.json` 记录实际起止坐标和着地检查；`Verification.json` 记录逐个 MP4 的尺寸、帧率、帧数和时长核对结果。原生源帧保存在 `.godot/promo_walk_20261021/Shot_01`～`Shot_10`。

## 重新渲染

`Source` 是仅供宣传素材使用的捕获工具，没有修改正常游戏脚本、关卡或项目配置。仅在本次进程中关闭对话、界面、收集和过关触发器，避免写入存档。

项目根目录先创建 `.godot/promo_walk_20261021`，再运行（替换 Godot 可执行路径）：

```powershell
godot --headless --path . --fixed-fps 60 res://Promo_Renders/20261021_Level_Walk_10x2s_1080p60/Source/Walk_Capture.tscn -- --probe
godot --path . --audio-driver Dummy --rendering-method mobile --rendering-driver d3d12 --resolution 1920x1080 --fixed-fps 60 --disable-vsync res://Promo_Renders/20261021_Level_Walk_10x2s_1080p60/Source/Walk_Capture.tscn
```

使用 `Source/Encode_Verify.py` 编码、验证并生成预览，需要 Pillow 和本机 Krita 附带的 FFmpeg。文件路径以项目根目录为工作目录，避免 FFmpeg 对中文绝对路径的兼容问题；已有视频不会被覆盖。
