class_name TexturePackerFrame
extends RefCounted

# TexturePacker 单帧播放数据.
# ConfigAssets 在 assets 加载阶段扫描 `.tpsheet`, 并把 region, margin 和 offset 合成为播放器可直接使用的数据.
var region: Rect2
# anchor_position 表示锚点在当前裁剪帧内部的位置.
# region 负责说明从 atlas 取哪块图, anchor_position 负责说明这块图自己的锚点在哪里.
var anchor_position: Vector2
