class_name TexturePackerFrame
extends RefCounted

# TexturePacker 单帧播放数据.
# AssetManager 在启动扫描 `.tpsheet` 时把 region, margin 和 offsets 合成为播放器可直接使用的数据.
var region: Rect2
var draw_position: Vector2

