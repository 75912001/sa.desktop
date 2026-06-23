class_name MainWindowGuideDrawer
extends Node

# MainWindowGuideDrawer 只负责主窗口调试辅助图形的纯绘制.
# 它不创建节点、不读取输入状态, 调用方把 CanvasItem 传进来后, 这里直接使用 draw_* API
# 把窗口对角辅助线、双方固定站位点和坐标标签画在同一个调试绘制层上.

# 绘制两组窗口对角辅助线, 并标注战斗双方固定站位坐标.
# 辅助线使用真实 OS 窗口尺寸裁剪, 因此主窗口缩放后仍覆盖当前可见窗口范围.
func draw_guides(target: CanvasItem, window_size: Vector2) -> void:
    var down_right_lines := _window_parallel_line_segments(Vector2(window_size.y, -window_size.x).normalized(), window_size)
    var down_left_lines := _window_parallel_line_segments(Vector2(window_size.y, window_size.x).normalized(), window_size)

    for line in down_right_lines:
        target.draw_line(line["from"], line["to"], Constants.WINDOW_GUIDE_LINE_COLOR, Constants.WINDOW_GUIDE_LINE_WIDTH)
    for line in down_left_lines:
        target.draw_line(line["from"], line["to"], Constants.WINDOW_GUIDE_LINE_COLOR, Constants.WINDOW_GUIDE_LINE_WIDTH)

    _draw_window_camp_guide_labels(target, window_size)

# 通过法线方向上的 1/18 到 17/18 等距位置生成 17 条平行线.
# 第 9 条线经过窗口中心, 对应当前方向的主对角线; 其它 16 条线把窗口分成 18 条对角带.
func _window_parallel_line_segments(normal: Vector2, window_size: Vector2) -> Array[Dictionary]:
    var corners := [
        Vector2.ZERO,
        Vector2(window_size.x, 0.0),
        window_size,
        Vector2(0.0, window_size.y),
    ]
    var min_projection := normal.dot(corners[0])
    var max_projection := min_projection
    for corner in corners:
        var projection := normal.dot(corner)
        min_projection = minf(min_projection, projection)
        max_projection = maxf(max_projection, projection)

    var segments: Array[Dictionary] = []
    for index in range(1, 18):
        var offset := lerpf(min_projection, max_projection, float(index) / 18.0)
        var endpoints := _line_window_intersections(normal, offset, window_size)
        if endpoints.size() >= 2:
            segments.append({
                "normal": normal,
                "offset": offset,
                "from": endpoints[0],
                "to": endpoints[1],
            })
    return segments

# 把无限长直线 `normal.dot(point) = offset` 裁剪到窗口矩形边界.
# 只返回窗口内的两个端点; 边界重合导致的重复点会先去重.
func _line_window_intersections(normal: Vector2, offset: float, window_size: Vector2) -> Array[Vector2]:
    var points: Array[Vector2] = []
    if absf(normal.y) > 0.0001:
        _append_unique_point(points, Vector2(0.0, offset / normal.y), window_size)
        _append_unique_point(points, Vector2(window_size.x, (offset - normal.x * window_size.x) / normal.y), window_size)
    if absf(normal.x) > 0.0001:
        _append_unique_point(points, Vector2(offset / normal.x, 0.0), window_size)
        _append_unique_point(points, Vector2((offset - normal.y * window_size.y) / normal.x, window_size.y), window_size)
    return points

func _append_unique_point(points: Array[Vector2], point: Vector2, window_size: Vector2) -> void:
    if not _point_in_window(point, window_size):
        return
    if _has_close_point(points, point):
        return
    points.append(point)

func _point_in_window(point: Vector2, window_size: Vector2) -> bool:
    return (
        point.x >= -0.001
        and point.y >= -0.001
        and point.x <= window_size.x + 0.001
        and point.y <= window_size.y + 0.001
    )

func _has_close_point(points: Array[Vector2], point: Vector2) -> bool:
    for existing_point in points:
        if existing_point.distance_squared_to(point) <= 0.01:
            return true
    return false

func _draw_window_camp_guide_labels(target: CanvasItem, window_size: Vector2) -> void:
    var font := ThemeDB.fallback_font
    var font_size := Constants.WINDOW_GUIDE_TEXT_FONT_SIZE
    _draw_window_camp_points(target, font, font_size, _window_initiator_guide_points(), window_size)
    _draw_window_camp_points(target, font, font_size, _window_receiver_guide_points(), window_size)

func _window_initiator_guide_points() -> Array[Vector2]:
    return [
        Vector2(560.0, 420.0),
        Vector2(480.0, 480.0),
        Vector2(640.0, 360.0),
        Vector2(400.0, 540.0),
        Vector2(720.0, 300.0),
        Vector2(480.0, 360.0),
        Vector2(400.0, 420.0),
        Vector2(560.0, 300.0),
        Vector2(320.0, 480.0),
        Vector2(640.0, 240.0),
    ]

func _window_receiver_guide_points() -> Array[Vector2]:
    return [
        Vector2(240.0, 180.0),
        Vector2(160.0, 240.0),
        Vector2(320.0, 120.0),
        Vector2(80.0, 300.0),
        Vector2(400.0, 60.0),
        Vector2(320.0, 240.0),
        Vector2(240.0, 300.0),
        Vector2(400.0, 180.0),
        Vector2(160.0, 360.0),
        Vector2(480.0, 120.0),
    ]

func _draw_window_camp_points(target: CanvasItem, font: Font, font_size: int, points: Array[Vector2], window_size: Vector2) -> void:
    for index in range(points.size()):
        var point := points[index]
        if not _point_in_window(point, window_size):
            continue
        var label := "%d(%d,%d)" % [index + 1, int(roundf(point.x)), int(roundf(point.y))]
        var label_position := _window_guide_label_position(font, font_size, point, label, window_size)
        target.draw_circle(point, Constants.WINDOW_GUIDE_POINT_RADIUS, Constants.WINDOW_GUIDE_POINT_COLOR)
        target.draw_string(font, label_position, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Constants.WINDOW_GUIDE_TEXT_COLOR)

func _window_guide_label_position(font: Font, font_size: int, point: Vector2, label: String, window_size: Vector2) -> Vector2:
    var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
    var padding := Constants.WINDOW_GUIDE_TEXT_EDGE_PADDING
    var position := Vector2(point.x - text_size.x * 0.5, point.y + Constants.WINDOW_GUIDE_TEXT_OFFSET.y)
    if position.y + padding > window_size.y:
        position.y = point.y - Constants.WINDOW_GUIDE_TEXT_OFFSET.y
    position.x = clampf(position.x, padding, maxf(padding, window_size.x - text_size.x - padding))
    position.y = clampf(position.y, padding + text_size.y, maxf(padding + text_size.y, window_size.y - padding))
    return position
