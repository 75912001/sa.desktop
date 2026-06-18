# 托盘菜单-配置模板
# 首次启动时, 程序会把本文件复制为 config/tray.yaml.
# config/tray.yaml 是本地运行期文件, 后续会被程序整体覆盖写回.
# 需要查看字段说明和默认结构时, 以本模板为准.

window:
  # 主窗口左上角屏幕坐标.
  # 首次启动使用模板值; 拖拽或重置窗口位置后会写回 config/tray.yaml.
  position:
    x: 0
    y: 0
  # 主窗口缩放比例, 0.1 表示 10%, 1.0 表示 100% 即 800x600.
  scale: 1.0
  # 内容透明度, 0.1 表示 10%, 1.0 表示 100%.
  opacity: 1.0
  # 是否启用鼠标穿透; 用户通过托盘勾选后会写回.
  click_through: false
  # 启动时是否默认隐藏主窗口.
  # true 表示程序启动后只保留托盘入口, 主窗口会最小化隐藏.
  hidden: true
  # 调试用红色边框开关.
  # true 表示启动时默认显示 2px 红边, 用来确认透明主窗口的实际范围.
  debug_border: false

menu:
  # 菜单文字字号. 有效范围 8-32; 菜单宽度和高度会按字号和文本内容自动计算.
  font_size: 14
  # 菜单颜色使用 #RRGGBB 或 #RRGGBBAA. AA 为透明度, FF 表示完全不透明.
  colors:
    # 菜单面板背景色.
    panel: "#FAFAFAFF"
    # 菜单窗口边框颜色.
    border: "#858F9FFF"
    # 普通菜单项文字颜色.
    text: "#0D0F14FF"
    # 鼠标悬浮或保持高亮时的文字颜色.
    hover_text: "#FFFFFFFF"
    # 鼠标悬浮或子菜单入口保持高亮时的背景色.
    highlight: "#1A61D1FF"
    # 菜单项按下时的背景色.
    pressed: "#1247A3FF"
    # 禁用菜单项文字颜色.
    disabled_text: "#949BA8FF"
