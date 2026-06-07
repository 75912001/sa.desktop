# sa.desktop
sa 桌面版

## 项目定位

`sa.desktop` 是 Windows-only Godot 4.6 桌面宠物客户端. 第一版目标是实现类似 QQ 宠物的桌面挂机体验: 宠物平时以小透明窗口在桌面上播放动作, 可拖拽移动, 可停靠屏幕边缘, 并通过系统托盘管理窗口行为.

## Windows Godot 桌面宠物 MVP

### MVP 范围

- 主角资源固定为 `assets/pet/4000001`.
- 窗口模型采用小透明窗口移动, 不是全屏透明覆盖层.
- 宠物按原始资源大小显示, 默认播放待机动画, 并支持随机挂机动作.
- 支持桌面拖拽, 释放后靠近屏幕边缘时自动吸附.
- 支持系统托盘常驻, 托盘菜单提供显示/隐藏、重置位置、退出等操作.
- 支持缩放预设: `50%`, `75%`, `100%`, `125%`, `150%`.
- 支持透明度预设: `30%`, `60%`, `100%`.
- 支持开关式鼠标穿透, 开启后通过托盘菜单恢复可点击.

第一版不实现背包、技能、战斗数值、多宠物切换和外部游戏自动化. MVP 的重点是先跑通桌宠核心体验.

### 资源管线

现有资源继续作为源数据使用, 不重新生成或复制 PNG.

- `assets/pet/4000001.png`: 宠物图集.
- `assets/pet/4000001.tpsheet`: TexturePacker 图集切帧数据.
- `assets/pet/4000001.offsets.json`: 每帧原始绘制偏移, 由导出工具的 `偏移信息.txt` 转换生成, `106923` 对应第一条偏移.
- `config/pet.yaml`: 宠物配置, 包含动作、方向和帧编号.
- `addons/codeandweb.texturepacker`: 项目保留的 TexturePacker 插件; 第一版不要启用它批量导入全部 `.tpsheet`, 否则会生成大量 `.tres` 并拖慢编辑器.
- `addons/miniyaml`: 项目保留的 YAML 插件; 第一版动画加载为避免完整解析卡顿, 不依赖它解析整份宠物配置.
- `.codex/skills/export-pet-offsets`: 项目本地 Codex skill, 可把素材导出工具的 `偏移信息{petid}.txt` 转成 `assets/pet/{petid}.offsets.json`.

当前第一版新增 `PetAnimationBuilder`, 定向读取 `pet.yaml` 中宠物的动作帧列表, 再解析同 ID 的 `.tpsheet` 帧区域和 `.offsets.json` 帧偏移, 在运行时内存中生成偏移动画数据供 `AtlasFramePlayer` 播放. 读取配置时会在内存中把 tab 归一为空格, 不修改配置源文件. 桌宠主流程默认只生成 `4000001` 的 `stand/walk` 动作; 偏移测试场景会从 `config/pet.yaml` 读取所有资源完整的宠物, 当前可切换 `4000001` 到 `4000006`, 并生成 `attack/faint/hurt/defense/stand/walk/attackShort` 全部动作. 该流程仍然引用现有 PNG, 不复制图集.

偏移播放使用同一宠物 ID 对应的 PNG、`.tpsheet`、`pet.yaml` 和 `.offsets.json`. 播放器直接绘制图集 region, 并按每帧 offset 固定脚底原点, 用于修正走路脚步漂移问题.

导出新的偏移 JSON 时, 先把素材导出工具输出的 `偏移信息{petid}.txt` 放在 `D:/软件/素材导出工具/导出素材`, 再从项目根目录运行:

```powershell
python .codex/skills/export-pet-offsets/scripts/export_pet_offsets.py --dry-run
python .codex/skills/export-pet-offsets/scripts/export_pet_offsets.py
```

脚本会按 `{petid}.tpsheet` 中 numeric frame id 升序匹配 offset 行, 行数不一致时跳过该宠物并报错. 已存在的 offsets JSON 默认不会覆盖, 需要重导时显式加 `--overwrite`.

`project.godot` 默认禁用编辑器插件自动导入. 如果需要调试 TexturePacker 插件, 只针对少量资源临时启用, 不要让编辑器导入整个 `assets/character` 和 `assets/pet` 目录.

### 窗口与桌面行为

- 技术上仍然是一个 Windows 原生窗口, 但目标表现是无边框、透明背景、只看到宠物本体.
- 使用 Godot `DisplayServer` 管理窗口透明、无边框、置顶、大小和位置.
- 真实点击穿透依赖 `native/windows_click_through_helper.exe` 设置 Win32 扩展窗口样式; Godot 鼠标穿透 flag 只作为 helper 缺失时的 fallback.
- 导出运行时需要让 `native/windows_click_through_helper.exe` 跟随 `sa.exe` 一起发布, 保持 `native/` 相对路径不变.
- 启用 per-pixel transparency, 并让 root viewport 使用透明背景.
- 拖拽时移动整个小窗口, 而不是只移动窗口内部节点.
- 窗口位置限制在当前屏幕可用区域内, 避免宠物移出屏幕.
- 位置、缩放、透明度、穿透状态保存到 `user://settings.json`.
- Godot-only 优先. 如果纯 Godot 无法稳定隐藏 Windows 任务栏按钮, 先记录为已知限制, 后续再评估 Win32/GDExtension.

## 项目目录

- `addons/`: Godot 插件, 包含 TexturePacker、MiniYAML、protobuf、YATI 等.
- `assets/`: 图片、图集、动画帧、音效、字体等资源.
- `config/`: 游戏配置, 包含宠物和角色配置.
- `protocols/`: 协议定义或本地数据协议.
- `scenes/`: Godot `.tscn` 场景.
- `scripts/`: Godot `.gd` 脚本.
- `tests/`: 测试脚本、验证说明或后续自动化测试.

## 核心模块

- `PetController`: 控制宠物动作播放、随机挂机动作和方向切换.
- `WindowController`: 控制透明窗口、拖拽、边缘吸附、缩放、透明度、鼠标穿透和位置保存.
- `TrayController`: 控制系统托盘图标和菜单.
- `SettingsStore`: 读写 `user://settings.json`.
- `PetAnimationBuilder`: 基于现有 `pet.yaml`、`.tpsheet`、offsets JSON 和 PNG 在内存中生成偏移动画数据.
- `AtlasFramePlayer`: 图集帧播放器, 直接按 region 和 offset 绘制帧, 用来保持脚底原点稳定.
- `WindowsClickThroughHelper`: 调用 Windows native helper, 对主窗口切换真实点击穿透.

## 测试场景

- `tests/test_pet_offsets.tscn`: 独立偏移播放测试页, 不作为默认启动场景.
- 运行方式: 在 Godot 中打开该场景后运行当前场景, 或使用 `--scene res://tests/test_pet_offsets.tscn` 启动, 默认选择 `4000001 stand_down`, 可通过宠物下拉框切换 `config/pet.yaml` 中资源完整的宠物.
- 该测试场景启动时会临时恢复普通可调整窗口, 关闭桌宠透明、无边框和置顶标志, 避免沿用主项目的小透明桌宠窗口.
- 控制项: 宠物选择、`attack/faint/hurt/defense/stand/walk/attackShort` 动作、8 个方向、播放/暂停、上一帧/下一帧、循环、辅助线和 frame/offset/region 信息.
- 验证重点: 偏移播放的脚底基线应稳定, 用于观察每帧 offset 是否能修正脚步漂移.

## 测试清单

- 打开 Godot 4.6 项目, 确认 TexturePacker 和 MiniYAML 编辑器插件未启用.
- 确认运行后不会生成 `*.sprites/`、`*.tres` 或 `*.tpsheet.import` 批量导入产物.
- 确认 `PetAnimationBuilder` 能直接读取所选宠物的 `.tpsheet` 和 `.offsets.json`, 并在内存中生成动画.
- 打开 `tests/test_pet_offsets.tscn`, 切换宠物、`attack/faint/hurt/defense/stand/walk/attackShort` 和 8 个方向, 验证偏移播放的脚底原点稳定.
- 在偏移测试页开启辅助线, 验证当前 frame id、offset 和脚底基线显示正常.
- 运行 `python .codex/skills/export-pet-offsets/scripts/export_pet_offsets.py --dry-run`, 确认素材导出偏移行数和 `.tpsheet` frame 数一致.
- 运行主场景, 确认窗口透明、无边框、置顶, 宠物可见且播放待机动画.
- 验证拖拽窗口、释放后边缘吸附、重启后位置恢复.
- 验证托盘菜单的显示/隐藏、缩放、透明度、重置位置、退出.
- 验证开启鼠标穿透后底层窗口可点击, 并能通过托盘关闭穿透.
- 验证随机挂机动作不会把窗口移出当前屏幕可用区域.
