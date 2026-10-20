# 开屏与字母收集音效

- `opening_piano.wav`：6.40 秒，C 大调、C4–G4–C5–E5–G5–C6 依次落键，比初版整体提高一个八度。音符间隔放宽至 220–320 毫秒，保留每个音的自然长延音。采用真实钢琴的轻力度录音，柔化击弦、增加少量房间反射，峰值为 -7 dBFS。对 `mainscene.ogg` 起始独奏的分析得到约 785.33 Hz（G5，相对 A440 高约 2.95 音分），钢琴按此微调，保持相同 C 大调和声并靠近菜单旋律的音区。
- `collection_triangle.wav`：2.30 秒，单次清脆钢击，比初版提高五个半音，主要共振约 3520 Hz。减弱低音共振，提高上部金属泛音，起音更快、反射更少，尾音仍自然结束；峰值为 -8 dBFS。

两份成品均为 44.1 kHz、16 bit 立体声 WAV，并以无损 PCM 导入 Godot。三角铁为自主合成。钢琴使用下方署名的真实录音单音重新编排；原始单音随 `Audio/Tools/PianoSamples/` 保存，目录中的 `.gdignore` 避免将制作源素材导入游戏。运行游戏不依赖 Python；离线复现脚本为 `Audio/Tools/Generate_Update_SFX.py`，依赖 NumPy、SoundFile。

## 钢琴采样署名

**Salamander Grand Piano V3 — Alexander Holm — CC BY 3.0.**

来源：[Salamander Grand Piano](https://github.com/sfzinstruments/SalamanderGrandPiano)，固定版本 `3382bf9496bba2486f5ab0de55a264d1dfc38404`。许可：[Creative Commons Attribution 3.0 Unported](https://creativecommons.org/licenses/by/3.0/)，完整许可随 `Salamander_LICENSE.txt` 保存。

使用六个轻力度（v4）单音，进行了移调、校音、重采样、柔化处理、立体声混音和房间反射，重新编排为本项目的开屏分解和弦；原作者不为本项目背书。发布该音效时保留以上署名、来源和许可。

开屏在首个圆形蒙版开始扩散时通过 `SoundPlayer.play("opening_piano")` 播放一次；加载期间直接跳过不会补播。主菜单背景音乐仍在镜头回正后开始。

三角铁在有效玩家开始拾取、物件进入 `COLLECTING` 状态时播放一次；重复碰撞、已收集字母、其他图层或无人机不会触发。声音由持久化的 SoundPlayer 播放，收集动画结束并停用物件不会截断余音。两者共用现有 SFX 总线，遵循主音量和音效音量。
