extends Node

# GMainWindow 是真实主窗口实例的全局入口.
# Autoload 节点会早于主场景创建, 因此这里只保存引用, 不执行任何窗口初始化逻辑.
var main_window: MainWindow = null
