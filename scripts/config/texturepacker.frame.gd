class_name TexturePackerFrame
extends RefCounted

# TexturePacker 单帧播放数据.
# ConfigAssets 在 assets 加载阶段扫描 `.tpsheet`, 并把 region, margin 和 offsets 合成为播放器可直接使用的数据.
var region: Rect2
var draw_position: Vector2
