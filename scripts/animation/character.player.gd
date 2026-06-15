class_name CharacterFramePlayer
extends FramePlayer

# CharacterFramePlayer 是角色专用播放器.
# 它只处理角色配置, 武器动作参数和角色显示入口, 逐帧播放和绘制复用 FramePlayer.
# 角色和宠物的配置维度不同: 角色播放 key 包含 direction, weapon, action.
# 因此角色入口单独放在这里, 避免底层 FramePlayer 继续知道武器类型或角色动作枚举.

# 按角色 ID 直接播放一个动作.
# target_anchor_position 使用父节点或窗口内容坐标系, 表示角色锚点要落到的位置.
func play_character(character_id: int, weapon: int, direction: int, action: int, target_anchor_position: Vector2) -> bool:
    # 角色显示必须同时具备方向, 武器和动作. 任意 Unknown 都表示调用方边界转换失败.
    if direction == Constants.Direction.Unknown:
        push_error("角色动画显示方向未知: character=%d direction=%d" % [character_id, direction])
        return false
    if weapon == Constants.WeaponType.Unknown:
        push_error("角色武器类型未知: character=%d weapon=%d" % [character_id, weapon])
        return false
    if action == Constants.CharacterAction.Unknown:
        push_error("角色动画动作未知: character=%d action=%d" % [character_id, action])
        return false

    # ConfigCharacter.Entry 保存角色级共享 atlas/frame_by_id 和结构化动作帧表.
    # get_by_id() 负责按需懒加载图集, 播放器只消费已经组装好的 Entry.
    var entry := GameData.character_config.get_by_id(character_id)
    if entry == null:
        push_error("角色配置不存在: character=%d" % character_id)
        return false

    # 配置加载阶段已经保证合法角色具备完整动作帧表; 角色帧表 key 是 direction + weapon + action.
    var play_info := entry.get_play_info(direction, weapon, action)

    # FramePlayer 的局部原点就是动画锚点, 战斗站位可以直接写到节点 position.
    play(
        entry.atlas,
        entry.frame_by_id,
        play_info.ids,
        Constants.ANIMATION_DEFAULT_SPEED,
        Constants.ANIMATION_DEFAULT_LOOP
    )
    position = target_anchor_position
    # 角色资源同样是像素图集, 最近邻过滤能保持边缘清晰.
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    disable_guides()
    return true
