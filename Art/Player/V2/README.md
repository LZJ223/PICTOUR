# 绘本旅人 V2

新样板角色场景为 `Component/Player/Traveler_Large.tscn`，旧 `Player.tscn` 保持原尺寸与固定跳高。

原创程序绘制一体工作服、短手臂与约三分之一身高的细线双腿；红色围巾尾部由 `Scarf_Ribbon.gd` 的 8 点惯性丝带独立绘制。步行和奔跑各 16 帧，待机 8 帧，起跳、落地、刹停、转身和空中姿态另有关键帧。步态按实际移动距离推进，动画不锁定操作。

图集单帧 192×256，显示为 0.5 倍，源脚底 y=236 映射至玩家根节点 y=0。站立外观约 90 像素高，实体碰撞为 30×86。

重建素材：Godot `--headless --path . --script res://Art/Player/V2/Build_Traveler_Large.gd`。生成后需要重新导入。来源与用途记录于 `Sources.json`。

验证入口 `res://Art/Player/V2/Traveler_Large_Check.tscn`：2026-10-09 headless 与 Windows D3D12 均为 42 项检查、0 失败；满跳实测 108.574 像素，短跳 41.225 像素，持续匀速跑动围巾尾部波幅约 22.38 像素。PNG 所有 72 帧均为独立姿态，地面动作脚底稳定。检查日志、JSON 与 8 张真实 GPU 截图放在忽略的 `Exports/` 下；人类手感与美术验收待试玩。
