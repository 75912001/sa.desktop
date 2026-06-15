class_name PetFramePlayer
extends FramePlayer

# PetFramePlayer 是宠物专用播放器.
# 它只处理宠物配置, 宠物动作参数和宠物显示入口, 逐帧播放和绘制复用 FramePlayer.
# 这个类是桌宠主流程和宠物偏移测试页应该直接使用的播放器类型.
# 它继承 FramePlayer, 但只暴露宠物语义的方法, 避免调用方把角色武器或角色动作传入宠物播放链路.

# 按宠物 ID 直接显示并播放一个动作.
# target_anchor_position 使用父节点或窗口内容坐标系, 表示宠物锚点要落到的位置.
func display_pet(pet_id: int, direction: int, action: int, target_anchor_position: Vector2) -> bool:
    # 高层显示入口通常由战斗场景调用, 传入的是已经转换好的运行期枚举值.
    # 这里统一转 int, 可以兼容 Dictionary 或 Variant 中取出的数值.
    var pet_id_value := int(pet_id)
    var direction_value := int(direction)
    var action_value := int(action)

    # 宠物播放器只接受宠物动作枚举. Unknown 表示调用方传入了未解析或不支持的动作.
    if direction_value == Constants.Direction.Unknown:
        push_error("宠物动画显示方向未知: pet=%d direction=%d" % [pet_id_value, direction_value])
        return false
    if action_value == Constants.PetAction.Unknown:
        push_error("宠物动画动作未知: pet=%d action=%d" % [pet_id_value, action_value])
        return false

    # GameData.pet_config 已在主场景前由 ConfigManager 初始化.
    # get_by_id() 会按需懒加载 atlas, 播放器拿到 Entry 后不再关心资源路径.
    var pet_entry := GameData.pet_config.get_by_id(pet_id_value)
    if pet_entry == null:
        push_error("宠物配置不存在: pet=%d" % pet_id_value)
        return false

    # 配置加载阶段已经保证合法宠物具备完整动作帧表, 播放器直接取出当前方向和动作的帧序列.
    var play_info := pet_entry.get_play_info(direction_value, action_value)

    # display_pet 面向战斗等普通显示场景. FramePlayer 的局部原点就是动画锚点,
    # 所以节点 position 直接等于父坐标中的目标锚点.
    play_frame_sequence(pet_entry.atlas, pet_entry.frame_by_id, play_info.ids, _pet_animation_speed(action_value), Constants.ANIMATION_DEFAULT_LOOP)
    position = target_anchor_position
    # 像素风图集使用最近邻过滤, 避免缩放或窗口合成时边缘发虚.
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    set_guides_visible(false)
    return true

func _pet_animation_speed(action: int) -> float:
    # 行走动作需要比普通站立或攻击更快, 才能和窗口移动速度形成自然的步频.
    if action == Constants.PetAction.Walk:
        return Constants.ANIMATION_WALK_SPEED
    # 其它宠物动作先使用统一默认速度, 后续如果需要动作级速度, 应在宠物播放器边界扩展.
    return Constants.ANIMATION_DEFAULT_SPEED
