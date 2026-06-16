class_name PetFramePlayer
extends FramePlayer

# PetFramePlayer 是宠物专用播放器.
# 它只处理宠物配置, 宠物动作参数和宠物显示入口, 逐帧播放和绘制复用 FramePlayer.
# 这个类是战斗、宠物偏移测试页等需要显示宠物动画的场景应该直接使用的播放器类型.
# 它继承 FramePlayer, 但只暴露宠物语义的方法, 避免调用方把角色武器或角色动作传入宠物播放链路.

# 按宠物 ID 直接播放一个动作.
# target_anchor_position 使用父节点或窗口内容坐标系, 表示宠物锚点要落到的位置.
func play_pet(pet_id: int, direction: int, action: int, target_anchor_position: Vector2) -> bool:
    # 宠物播放器只接受宠物动作枚举. Unknown 表示调用方传入了未解析或不支持的动作.
    if direction == Constants.Direction.Unknown:
        push_error("宠物动画显示方向未知: pet=%d direction=%d" % [pet_id, direction])
        return false
    if action == Constants.PetAction.Unknown:
        push_error("宠物动画动作未知: pet=%d action=%d" % [pet_id, action])
        return false

    # GGameData.pet_config 已在主场景前由 ConfigManager 初始化.
    # get_by_id() 会按需懒加载 atlas, 播放器拿到 Entry 后不再关心资源路径.
    var entry := GGameData.pet_config.get_by_id(pet_id)
    if entry == null:
        push_error("宠物配置不存在: pet=%d" % pet_id)
        return false

    # 配置加载阶段已经保证合法宠物具备完整动作帧表, 播放器直接取出当前方向和动作的帧序列.
    var play_info := entry.get_play_info(direction, action)

    # play_pet 面向战斗等普通显示场景. FramePlayer 的局部原点就是动画锚点,
    # 所以节点 position 直接等于父坐标中的目标锚点.
    var play_speed := Constants.ANIMATION_DEFAULT_SPEED
    if action == Constants.PetAction.Walk:
        play_speed = Constants.ANIMATION_WALK_SPEED
    play(
        entry.atlas, 
        entry.frame_by_id, 
        play_info.ids, 
        play_speed, 
        Constants.ANIMATION_DEFAULT_LOOP
    )
    position = target_anchor_position
    # 像素风图集使用最近邻过滤, 避免缩放或窗口合成时边缘发虚.
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    disable_guides()
    return true
