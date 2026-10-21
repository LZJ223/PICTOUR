# PICTOUR 无 UI 宣传片头

交付视频：`PICTOUR_Opening_NoUI_1920x1080_60fps.mp4`（H.264 High / AAC，1920×1080，60fps）。

- 总长 17.1 秒，共 1026 帧。镜头在第 426 帧（7.1 秒）回正，此后完整保留 600 帧，即 10 秒。
- 保留当前片头：描边、涨水填白、游戏 Logo 显色、背景展开、上移展示 Godot Logo、镜头垂直回落。
- 全程没有菜单按钮或 Back；回落及之后不显示主菜单标题，只保留动态背景和角色。
- 唯一音源为原始 `Audio/SFX/opening_piano.wav`，在第 136 帧（约 2.266667 秒、Logo 圆形蒙版启动时）开始。没有背景音乐、环境音或其他操作音效。
- Godot 4.7.2 Mobile / D3D12 实际逐帧渲染，所有源帧均为原生 1920×1080，没有从 720p 放大。
- `Preview.jpg` 为成片的六帧预览；`Capture.json` 记录动画阶段与帧号；`Verification.json` 记录媒体参数和音频核对结果。

## 重复渲染

`Source` 中的继承场景仅用于本次视频，没有修改正常片头、主菜单、玩法脚本、项目配置或用户存档。`Promo_Renders/.gdignore` 防止视频和工具进入正常资源导入。

在项目根目录创建 `.godot/promo_opening_20261021/Frames1080p` 空目录，然后运行（替换 Godot 的可执行路径）：

```powershell
godot --path . --audio-driver Dummy --rendering-method mobile --rendering-driver d3d12 --resolution 1920x1080 --fixed-fps 60 --disable-vsync res://Promo_Renders/20261021_Opening_NoUI_1080p60/Source/Promo_Capture.tscn
```

使用 `Source/Encode.ps1` 编码，再用 `Source/Verify.py` 核对。编码脚本默认使用本机 Krita 附带的 FFmpeg，可通过 `-Ffmpeg` 指定其他同样支持 OpenH264 的版本；不覆盖已有视频。验证脚本需要 NumPy、Pillow 和 FFmpeg。

无损 PNG 中间帧保留在 `.godot/promo_opening_20261021/Frames1080p`（缓存目录，不是游戏素材）。清理 Godot 缓存会移除中间帧，但不影响本目录中的成片。原项目已有的退出资源回收及沙箱 Shader 缓存提示不会出现在视频画面中。
