# 完整场景物体换层素材：12 段 × 0.5 秒

- 每关一段，1920×1080、60fps、30 帧，精确 0.5 秒。
- 使用正常游戏跟随相机，缩放固定为 1，不使用物体特写或后期裁切。
- 保留人物、全部图层和正常视差、雾效、景深、阴影、夜间光照。白天关卡为原始 3 层，夜间为原始 4 层；未隐藏任何前景或背景层。
- 人物保持可见、站立于真实地面，物理处理及动画正常运行。
- 仅隐藏游戏 UI、跳过对话，并禁止收集/过关触发器，以免宣传录制改动存档。保留物体的原生选中描边。
- 不含音乐；保留原始物体换层音效，按第 6 帧（0.1 秒）的实际触发时刻同步。较长音效随片长截取，最后 12ms 极短淡出以避免截断杂音。

## 文件

- `Transfer_Full_01_...mp4` 至 `Transfer_Full_12_...mp4`：十二个独立视频，H.264 High + 48kHz 双声道 AAC。
- `All_12_FullScene_Transfer_Clips.zip`：十二个视频的打包文件。
- `Preview.jpg`：十二段成片的编号预览；编号不在视频中出现。
- `Frames_Review.jpg`：每段换层前、动画中、换层后的画面。
- `Shot_Plan.json`：人物站位、被选择物体、方向及真实碰撞/动画预检。
- `Capture.json`：实际逐帧检查、音效资源、人物与图层可见状态。
- `Verification.json`：视频尺寸、帧率、帧数、时长与原始音效相关性检查。

所有换层均调用原始 `LayerControllerSystem.transfer()`，不伪造换层动画、不改地形或普通项目代码。逐帧验证人物可见且着地、所有图层有效且可见、普通跟随相机及缩放，以及换层目标和动画最终复位。

## 修改和重新渲染

中间原生源帧位于 `.godot/promo_transfer_full_scene_20261021/Shot_01` 至 `Shot_12`。捕获脚本复用之前行走素材的场景初始化/清理工具，以及已验证的各关卡地面站位。

项目根目录执行，按本机位置替换 `godot`：

```powershell
godot --headless --path . --resolution 1920x1080 --fixed-fps 60 --audio-driver Dummy res://Promo_Renders/20261021_Object_Transfer_FullScene_12x05s_1080p60/Source/Transfer_Capture.tscn -- --probe
godot --path . --audio-driver Dummy --rendering-method mobile --rendering-driver d3d12 --resolution 1920x1080 --fixed-fps 60 --disable-vsync res://Promo_Renders/20261021_Object_Transfer_FullScene_12x05s_1080p60/Source/Transfer_Capture.tscn
python Promo_Renders/20261021_Object_Transfer_FullScene_12x05s_1080p60/Source/Encode_Verify.py
```

编码使用本机 Krita 附带的 FFmpeg，Python 需 NumPy 和 Pillow。已有 MP4 不会被覆盖；调整后需要重新编码时，请先保留旧版或更换输出目录。
