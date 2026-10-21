# 人物切换图层：12 段 × 0.5 秒

- 每关一段，1920×1080、60fps、30 帧，精确 0.5 秒。
- 完整游戏视角，人物和所有图层保留，相机正常跟随，缩放为 1，不裁切为特写。
- 无 UI、无背景音乐；保留项目原始 `Audio/SFX/layer_cycle.mp3` 换层音效。
- 使用真实 `LayerControllerSystem.cycle(direction, true)`，执行正常碰撞检测与玩家碰撞组切换，播放各层原始轮换 Tween，保留视差、景深、雾、阴影与夜间照明。
- 每段前 6 帧（0.1 秒）为初始画面，随后开始换层，播放完整轮换及收尾。较长音效按片长截取，末尾 12ms 极短淡出避免截断杂音。

## 产物

- `Player_Layer_Cycle_01_...mp4` 至 `Player_Layer_Cycle_12_...mp4`：十二个独立视频，H.264 High + 48kHz 双声道 AAC。
- `All_12_Player_Layer_Cycle_Clips.zip`：所有视频的打包文件。
- `Preview.jpg`：十二个镜头的编号预览；视频本身无编号、字幕或额外转场。
- `Frames_Review.jpg`：各镜头在换层前、换层中、换层后的画面检查图。
- `Shot_Plan.json`：站位、方向、原始/目标物理图层及碰撞预检。
- `Capture.json`：真实捕获的逐帧检查和音效触发信息。
- `Verification.json`：最终视频尺寸、帧率、帧数、时长，以及音轨与原始音效的相关性检查。

## 验证和重渲染

在原有关卡中寻找换层前后均有地面支撑的站位，不修改地形、不绕过换层碰撞判定。逐帧检查人物可见且着地、所有图层仍在场、轮换动画确实运行、跨界层透明过渡和中间深度值出现；结束时检查所有槽位完成轮换、透明度恢复，以及玩家碰撞组属于目标物理层。

原生源帧位于 `.godot/promo_player_cycle_20261021/Shot_01` 至 `Shot_12`。录制工具复用完整场景物体换层工具的初始化和站位方法，进一步复用行走素材的场景生成/清理；所有捕获专用设置仅作用于录制进程，不修改正常游戏逻辑或存档。

项目根目录运行，按本机路径替换 `godot`：

```powershell
godot --headless --path . --resolution 1920x1080 --fixed-fps 60 --audio-driver Dummy res://Promo_Renders/20261021_Player_Layer_Cycle_FullScene_12x05s_1080p60/Source/Cycle_Capture.tscn -- --probe
godot --path . --audio-driver Dummy --rendering-method mobile --rendering-driver d3d12 --resolution 1920x1080 --fixed-fps 60 --disable-vsync res://Promo_Renders/20261021_Player_Layer_Cycle_FullScene_12x05s_1080p60/Source/Cycle_Capture.tscn
python Promo_Renders/20261021_Player_Layer_Cycle_FullScene_12x05s_1080p60/Source/Encode_Verify.py
```

编码使用本机 Krita 附带的 FFmpeg，Python 需 NumPy、Pillow。已有 MP4 不会被覆盖；修改镜头需要重编码时，请先保留旧文件或更换输出目录。
