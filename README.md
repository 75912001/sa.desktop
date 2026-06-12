# sa.desktop
sa 桌面版

## 项目定位

`sa.desktop` 是 Windows-only Godot 4.6 桌面宠物客户端. 第一版目标是实现类似 QQ 宠物的桌面挂机体验: 宠物平时以小透明窗口在桌面上播放动作, 可拖拽移动, 可停靠屏幕边缘, 并通过系统托盘管理窗口行为.

## Windows Godot 桌面宠物 MVP

### MVP 范围

- 启动时优先恢复 `user://settings.json` 中保存的宠物 ID, 保存值无效时从 `config/pet.yaml` 中资源完整的宠物随机选择.
- 主运行场景为 `scenes/desktop.tscn`, 同一场景内通过 `PetModule` 和 `BattleModule` 切换桌宠挂机和挂机战斗内容.
- 窗口模型采用小透明窗口移动, 不是全屏透明覆盖层.
- 宠物按原始资源大小显示, 默认播放待机动画, 并支持随机挂机动作.
- 支持桌面拖拽, 释放后靠近屏幕边缘时自动吸附.
- 支持系统托盘常驻, 托盘菜单由 `config/tray_menu.yaml` 配置显示项, 顺序, 文案, 层级关系, 字体大小, 颜色主题, 缩放, 透明度选项以及桌宠动作和方向白名单; 宠物 ID 选项经 `ConfigPet` 来自当前 `config/pet.yaml` 资源配置, 动作和方向由托盘配置白名单和当前宠物实际资源共同决定; `选项...` 会打开账号和关于标签窗口.
- 支持通过托盘 `开始挂机战斗/返回桌宠` 在同一个透明无边框置顶窗口内切换桌宠内容和战斗内容.
- 默认支持缩放预设: `10%`, `20%`, `30%`, `40%`, `50%`, `60%`, `70%`, `80%`, `90%`, `100%`.
- 默认支持透明度预设: `10%`, `20%`, `30%`, `40%`, `50%`, `60%`, `70%`, `80%`, `90%`, `100%`.
- 支持开关式鼠标穿透, 开启后通过托盘菜单恢复可点击.

第一版不实现背包, 技能, 战斗数值, 多宠物同时管理和外部游戏自动化. MVP 的重点是先跑通桌宠核心体验.

### 资源管线

现有资源继续作为源数据使用, 不重新生成或复制 PNG.

- `assets/pet/4000101.png`: 宠物图集.
- `assets/pet/4000101.tpsheet`: TexturePacker 图集切帧数据.
- `assets/pet/offsets.json`: 可选的每帧原始绘制偏移总表, 使用根级 pet id 到 frame id, 再到 `[x, y]` 的 JSON 映射, 由导出工具的 `偏移信息{petid}.txt` 转换生成, JSON 内不保存来源元数据; 没有 offset 的帧表示不需要额外偏移.
- `config/pet.yaml`: 宠物配置, 包含动作、方向和帧 ID.
- `config/tray_menu.yaml`: 托盘右键菜单配置, 包含菜单项, 层级关系, 文案, `font_size`, `colors`, 缩放和透明度选项, 以及桌宠动作和方向白名单; 不配置菜单宽度和宠物 ID.
- `addons/codeandweb.texturepacker`: 项目保留的 TexturePacker 插件; 第一版不要启用它批量导入全部 `.tpsheet`, 否则会生成大量 `.tres` 并拖慢编辑器.
- `addons/miniyaml`: 项目启用的 YAML 插件, 通过 `YAML` autoload 为运行时配置读取提供解析能力; 运行时启动顺序为 `YAML` Autoload -> `GameData` Autoload -> 主场景, `GameData` 会在主场景运行前触发 `ConfigManager` 初始化; `ConfigManager` 先通过 `AssetManager` 以 PNG 为主导扫描宠物和角色资源, 再绑定同 ID `.tpsheet` 和可选 offsets, 然后读取 YAML, 最后按 `asset load -> config load -> config check -> assemble` 初始化资源和 `ConfigPet`、`ConfigCharacter`、`ConfigEnemyGroup`; 托盘菜单配置仍保留项目内轻量读取逻辑. 配置 YAML 源文件必须使用标准空格缩进和 LF 换行, 读取阶段不修正 tab 缩进.
- `.codex/skills/export-pet-offsets`: 项目本地 Codex skill, 可把素材导出工具的 `偏移信息{petid}.txt` 合并导出到 `assets/pet/offsets.json`; 宠物 offsets JSON 使用根级 pet id 到 frame id, 再到 `[x, y]` 的 JSON 映射, 不在 JSON 内保存来源元数据.
- `.codex/skills/export-character-offsets`: 项目本地 Codex skill, 可把素材导出工具的 `偏移信息{characterid}.txt` 合并导出到 `assets/character/offsets.json`; 角色 offsets JSON 使用根级 character id 到 frame id, 再到 `[x, y]` 的 JSON 映射, 不在 JSON 内保存来源元数据.

当前第一版新增 `GameData`, `AssetManager`, `ConfigPet` 和 `AnimationPetBuilder`. `GameData` 是 Godot Autoload 全局入口, 在主场景之前触发共享资产和配置初始化, 后续业务代码通过 `GameData.pet_config`, `GameData.character_config`, `GameData.enemy_group_config` 和 `GameData.asset_manager` 读取已准备好的数据. `ConfigManager` 启动时先让 `AssetManager` 加载宠物和角色资源索引, 宠物和角色都以 PNG 文件名中的 ID 为主导创建资源条目, 每个 PNG 必须具备同 ID `.tpsheet`; offsets JSON 只作为可选绘制偏移输入, 会先转换为 `FrameOffsets`, 再和 `.tpsheet` 合成为 `frame_id -> TexturePackerFrame`; 没有 offset 的帧表示不需要额外偏移, 使用零偏移. 随后通过 MiniYAML 解析标准空格缩进的 `config/pet.yaml`, 再让 `ConfigPet` 同时加载 `skill:`, 默认 `attribute:` 和 `pet:` 段, 以 `pet_id -> ConfigPet.Entry` 形式缓存名称、稀有度、元素、属性范围、成长范围、技能槽位、描述和结构化 `action_frame_entries` 动作帧表; elemental 会在 load 阶段校验整数范围、总和 10、单元素或相邻双元素规则; YAML 源结构仍是 `direction -> action -> frame ids`, 加载进内存后会转换为 `ConfigPet.Entry.action_frame_entries[Vector2i(direction, action)] -> ConfigPet.ActionFrameEntry`, 方向和动作使用 `Constants.Direction` 和 `Constants.PetAction` 枚举值, 每个宠物动作帧表必须具备项目规定的全部方向和宠物动作, 缺失会在 load 阶段 assert 暴露; check 阶段会检查宠物配置引用的帧是否存在于已合成帧表中, 读取阶段不兼容 tab 缩进, 配置格式错误会直接暴露. assemble 阶段会把 `ConfigPet.Entry.asset` 指向同 ID `AssetPetMgr.Entry`, 这里只保存引用, 不复制 PNG 路径或 `sheet_frames`. `AnimationPetBuilder` 按 ID 消费 `ConfigPet` 解析出的当前宠物 `action_frame_entries`, 再通过 `ConfigPet.Entry.asset` 读取已合成的同 ID 帧播放数据和 PNG 路径, 运行时只保留 `frame_id -> {region, draw_position}` 和动画 `frame_ids` 顺序供 `FramePlayer` 播放. 桌宠主流程会从 `ConfigPet` 的 ID 查询派生资源完整的宠物选项, 没有有效持久化选择时随机选择初始宠物, 并按 `config/tray_menu.yaml` 的 `pet_actions` 和 `pet_directions` 白名单从当前宠物 `action_frame_entries` 中派生托盘动作菜单和方向; 宠物偏移测试场景会从 `ConfigPet` 的 ID 查询筛选所有资源完整的宠物, 当前可切换 `4000101` 到 `4000106`, 并生成测试页指定且资源内实际存在的全部动作. 该流程仍然引用现有 PNG, 不复制图集.

角色偏移测试使用 `ConfigCharacter` 和 `AnimationCharacterBuilder`. `ConfigManager` 先通过 `AssetManager` 加载角色资源索引, 再通过 MiniYAML 解析标准空格缩进的 `config/character.yaml`, 让 `ConfigCharacter` 只消费其中的 `character:` 段, 以 `character_id -> ConfigCharacter.Entry` 形式缓存基础字段和结构化 `action_frame_entries` 动作帧表; YAML 源结构仍是 `weapon -> direction -> action -> frame ids`, 加载进内存后会转换为 `ConfigCharacter.Entry.action_frame_entries[Vector3i(direction, weapon, action)] -> ConfigCharacter.ActionFrameEntry`, entry 内保存 `frame_ids`, 让构建器能用方向, 武器类型和动作直接定位帧号表. YAML 中的武器类型, 方向和动作仍使用字符串 key, 加载进内存后会转换为 `Constants.WeaponType`, `Constants.Direction` 和 `Constants.CharacterAction` 枚举值, 每个角色动作帧表必须具备项目规定的全部武器类型, 方向和角色动作, 缺失会在 load 阶段 assert 暴露; 角色资源加载以 `assets/character` 下 PNG 为主导, 每个 PNG 必须具备同 ID `.tpsheet`, 缺失会在 `AssetManager.load()` 阶段 assert 暴露; check 阶段会检查角色配置引用的帧是否存在于已合成帧表中, 读取阶段不兼容 tab 缩进, 配置格式错误会直接暴露. assemble 阶段会把 `ConfigCharacter.Entry.asset` 指向同 ID `AssetCharacterMgr.Entry`, 这里只保存引用, 不复制 PNG 路径或 `sheet_frames`. `AnimationCharacterBuilder` 按 ID 消费解析后的角色 `action_frame_entries`, 再通过 `ConfigCharacter.Entry.asset` 读取已合成的同 ID 帧播放数据和 PNG 路径, 在加载阶段生成播放器输入需要的帧表和动画序列. 测试场景按 `character_id / 10` 聚合为四角色颜色组, 例如 `1000011/1000012/1000013/1000014`. 当前可切换 11 个资源完整的角色组, 武器类型下拉框固定使用 `Constants.CHARACTER_WEAPON_TYPES`.

战斗内容由 `BattleModule` 嵌入 `scenes/desktop.tscn`, 主流程不切换根场景. 第一版只做站位和待机动画: 左侧敌方、右侧己方, 每边最多 10 个单位, 两排且每排最多 5 个. 阵型按石器时代的两排五点斜向站位展示. 敌方经 `ConfigManager` 加载的 `ConfigEnemyGroup` 读取 `config/enemy.group.yaml` 的 `enemyGroups`, 并转换为 `EnemyGroupEntry` 和 `EnemyEntry`, 默认使用 `enemyGroupId = 1`; 己方出场数据暂时写死在 `BattleScene` 代码中模拟, 第一排为宠物, 第二排为角色. 战斗单位仍复用 `.png + .tpsheet + 可选 offsets JSON + yaml` 的偏移播放器, 不复制图集, 不生成 `.sprites` 或 `.tres`.

偏移播放使用同一宠物 ID 对应的 PNG、`.tpsheet`、`pet.yaml` 和可选 `assets/pet/offsets.json` 偏移表. offsets 只作为加载阶段输入, 没有 offset 的帧使用零偏移; 播放器直接绘制图集 region, 并按每帧已合并的 `draw_position` 固定脚底原点, 用于修正走路脚步漂移问题.

导出新的偏移 JSON 时, 先把素材导出工具输出的 `偏移信息{petid}.txt` 放在 `D:/软件/素材导出工具/导出素材`, 再从项目根目录运行:

```powershell
python .codex/skills/export-pet-offsets/scripts/export_pet_offsets.py --dry-run
python .codex/skills/export-pet-offsets/scripts/export_pet_offsets.py
python .codex/skills/export-character-offsets/scripts/export_character_offsets.py --dry-run
python .codex/skills/export-character-offsets/scripts/export_character_offsets.py
```

脚本会按 `{petid}.tpsheet` 中 numeric frame id 升序匹配 offset 行, 行数不一致时跳过该宠物并报错. 已存在的 offsets JSON 默认不会覆盖, 需要重导时显式加 `--overwrite`. 宠物 offsets JSON 只保留根级 pet id 到 frame id, 再到 `[x, y]` 的 JSON 映射, 来源追溯依赖 `偏移信息{petid}.txt` 文件名和导出脚本日志. 如果某个资源或某一帧不需要额外绘制偏移, 可以不写入 offsets 总表.
角色偏移导出使用同样规则, 输出到 `assets/character/offsets.json`, 当前缺少导出偏移源文件的角色会被跳过并报告. 如果导出目录里存在 `偏移信息(代表..., 是 {characterid} 的一部分).txt` 这类补充偏移文件, 脚本会按文件名中的 frame id 把它和主偏移文件组合后写入 offsets 总表. 角色 offsets JSON 只保留根级 character id 到 frame id, 再到 `[x, y]` 的 JSON 映射, 来源追溯依赖 `偏移信息{characterid}.txt` 文件名和导出脚本日志. 没有 offset 的角色或帧会按零偏移播放; offsets 继续使用 JSON 而不是 YAML, 因为数组值格式体积接近 YAML, 并且可继续使用 Godot 内置 JSON 解析.

`project.godot` 默认禁用编辑器插件自动导入. 如果需要调试 TexturePacker 插件, 只针对少量资源临时启用, 不要让编辑器导入整个 `assets/character` 和 `assets/pet` 目录.

### 窗口与桌面行为

- 技术上仍然是一个 Windows 原生窗口, 但目标表现是无边框、透明背景、只看到宠物本体.
- 使用 Godot `DisplayServer` 管理窗口透明、无边框、置顶、大小和位置.
- 真实点击穿透依赖 `native/windows_click_through_helper.exe` 设置 Win32 扩展窗口样式; Godot 鼠标穿透 flag 只作为 helper 缺失时的 fallback.
- 导出运行时需要让 `native/windows_click_through_helper.exe` 跟随 `sa.exe` 一起发布, 保持 `native/` 相对路径不变.
- 启用 per-pixel transparency, 并让 root viewport 使用透明背景.
- 拖拽时移动整个小窗口, 而不是只移动窗口内部节点.
- 窗口位置限制在当前屏幕可用区域内, 避免宠物移出屏幕.
- 位置, 缩放, 透明度, 穿透状态, 当前宠物 ID 和账号占位登录状态保存到 `user://settings.json`.
- 托盘菜单的显示/隐藏使用显式窗口可见状态; 隐藏时会隐藏宠物节点, 最小化并隐藏主窗口, 同时临时启用鼠标穿透, 避免透明空窗口挡住桌面点击; 显示时恢复窗口和用户原本的穿透设置.
- 系统托盘右键菜单使用强制 native 的 Godot 自绘菜单窗口, 不设置 `StatusIndicator.menu` 或原生托盘 popup 属性, 避免菜单打开期间阻塞主循环, 并让菜单项点击直接触发窗口控制逻辑; 菜单显示项, 顺序, 文案, 层级关系, 字体大小, 颜色主题, 缩放, 透明度选项以及桌宠动作和方向白名单由 `config/tray_menu.yaml` 参数化配置, 宠物 ID 经 `ConfigPet` 从 `config/pet.yaml` 派生, 动作和方向由托盘配置白名单与当前宠物资源共同决定; 菜单宽度按当前层级实际文本和字体大小完全自适应, 高度按屏幕可用区域动态限高并在选项过多时滚动; 菜单项支持鼠标悬停高亮, 缩放, 透明度和宠物通过 "宠物 -> ID" 选择, 动作通过 "宠物 -> 动作 -> 动作名 -> 方向" 多级菜单立即播放, `选项...` 打开 Godot 非阻塞标签窗口, 鼠标进入子菜单时对应入口保持高亮, 菜单层级之间保留过渡热区避免移入子菜单时误关闭, 菜单组失去焦点后会自动关闭.
- 选项标签窗口包含 `账号` 和 `关于`. `账号` 当前只做邮箱注册/登录的本地占位逻辑, 不联网, 不保存密码, 不调用后端接口; `关于` 使用极简项目信息.
- 挂机战斗模式不改变窗口实例, 仍保持透明、无边框、置顶. 进入战斗时扩大窗口并隐藏 `PetModule`, 暂停单宠物随机移动, 显示透明背景的 `BattleModule`; 返回桌宠时清空战斗单位, 恢复桌宠窗口尺寸和位置.
- Godot-only 优先. 如果纯 Godot 无法稳定隐藏 Windows 任务栏按钮, 先记录为已知限制, 后续再评估 Win32/GDExtension.

## 项目目录

- `addons/`: Godot 插件, 包含 TexturePacker、MiniYAML、protobuf、YATI 等.
- `assets/`: 图片、图集、动画帧、音效、字体等资源.
- `config/`: 游戏配置, 包含宠物和角色配置.
- `config/tray_menu.yaml`: 托盘右键菜单结构和样式配置, `font_size`, `colors`, `pet_actions` 和 `pet_directions` 在 `menu` 下配置, 缩放和透明度选项在对应菜单项下内联配置.
- `config/enemy.group.yaml`: 战斗展示用敌人组配置.
- `protocols/`: 协议定义或本地数据协议.
- `scenes/`: Godot `.tscn` 场景.
- `scenes/desktop.tscn`: 主运行场景, 包含 `PetModule`、`BattleModule`、窗口控制和托盘控制.
- `scripts/`: Godot `.gd` 脚本.
- `tests/`: 测试脚本、验证说明或后续自动化测试.

## 核心模块

- `PetController`: 控制宠物动作播放, 随机挂机动作, 方向切换, 运行时宠物资源切换, 并缓存当前宠物可用动作菜单数据.
- `WindowController`: 控制透明窗口、拖拽、边缘吸附、缩放、透明度、鼠标穿透和位置保存.
- `TrayController`: 控制系统托盘图标和配置化菜单.
- `OptionsDialogController`: 控制托盘 `选项...` 打开的账号/关于标签窗口.
- `TrayMenuConfig`: 读取和整理 `config/tray_menu.yaml` 的菜单结构, 字体大小, 颜色主题, 数值选项以及宠物动作/方向白名单, 配置缺失或错误时回退内置默认值.
- `SettingsStore`: 读写 `user://settings.json`, 将设置 JSON 转换为 `SettingsData`, 保存窗口状态、宠物 ID 和账号占位登录状态.
- `Constants`: 集中定义项目配置文件路径、宠物 ID、稀有度和元素 key 校验范围、宠物资源目录、偏移总表路径、动画画布 padding、8 方向、宠物动作、角色动作和角色武器类型的字符串顺序、枚举值及双向映射, 让配置解析、资源检查、动画构建和测试页共用同一份常量定义.
- `GameData`: Godot Autoload 全局入口, 位于 `YAML` Autoload 后启动, 在主场景前触发 `ConfigManager` 初始化, 并暴露 `asset_manager`, `pet_config`, `character_config` 和 `enemy_group_config`.
- `AssetManager`: 启动时先于配置表加载, 统一扫描宠物和角色 PNG、`.tpsheet`、可选 offsets, 将 offsets JSON 转换为 `FrameOffsets`, 并建立资源完整性和 `frame_id -> TexturePackerFrame` 帧表, 供配置表 check 和动画构建器复用.
- `AssetParse`: 宠物和角色资源管理器共用的轻量解析工具, 负责从 `{id}.png` / `{id}.tpsheet` 文件名提取数字 ID, 并把 TexturePacker 的 x/y/w/h 字段转换成 Godot `Rect2`.
- `ConfigManager`: 统一加载 `AssetManager` 和 `scripts/config` 下的配置管理器, 集中提供 YAML 读取, `asset load -> config load -> config check -> assemble` 流程和共享配置实例.
- `ConfigPet`: 缓存 `config/pet.yaml` 的宠物配置, 提供技能 ID 查询、默认属性查询、宠物 ID 查询和 `get_by_id(id) -> ConfigPet.Entry`, 让业务代码可以按 ID 读取名称、稀有度、属性范围、成长范围、技能槽位和结构化 `action_frame_entries`; assemble 阶段会让 `ConfigPet.Entry.asset` 引用同 ID `AssetPetMgr.Entry`.
- `AnimationPetBuilder`: 位于 `scripts/animation/pet.builder.gd`, 基于 `ConfigPet`、`ConfigPet.Entry.action_frame_entries` 直接定位出的 `frame_ids`、`ConfigPet.Entry.asset` 引用的已合成帧表和 PNG 在内存中生成 `frame_id -> {region, draw_position}` 和动画 `frame_ids`.
- `ConfigCharacter`: 缓存 `config/character.yaml` 的角色配置, 提供 ID 查询和 `get_by_id(id) -> ConfigCharacter.Entry`; load 阶段强制校验每个角色具备全部规定武器类型, 方向和动作, 并把每个 `(direction, weapon, action)` 收敛为 `ConfigCharacter.ActionFrameEntry`; assemble 阶段会让 `ConfigCharacter.Entry.asset` 引用同 ID `AssetCharacterMgr.Entry`.
- `AnimationCharacterBuilder`: 位于 `scripts/animation/character.builder.gd`, 基于 `ConfigCharacter`、`ConfigCharacter.Entry.action_frame_entries` 直接定位出的 `frame_ids`、`ConfigCharacter.Entry.asset` 引用的已合成帧表和 PNG 在内存中生成角色帧表和动画帧序列.
- `FramePlayer`: 通用图集帧播放器, 位于 `scripts/animation/frame.player.gd`, 按动画 `frame_ids` 查资源级帧表, 直接按 region 和 `draw_position` 绘制帧, 用来保持脚底原点稳定.
- `WindowsClickThroughHelper`: 调用 Windows native helper, 对主窗口切换真实点击穿透.
- `Desktop`: 主运行场景脚本, 管理 `PetModule` 和 `BattleModule` 的内容模式切换.
- `ConfigEnemyGroup`: 缓存 `config/enemy.group.yaml` 的敌人组配置, 提供 ID 查询和 `get_enemy_group(id) -> EnemyGroupEntry` 给战斗场景复用.
- `BattleScene`: 战斗内容模块, 加载敌人组并使用代码内置模拟己方出战数据, 通过 `desktop.tscn` 内置的 `BattleModule` 运行.
- `BattleFormation`: 计算左右双方石器时代两排五点斜向站位和绘制层级.
- `AnimationUnit`: 位于 `scripts/animation/unit.gd`, 包装 `FramePlayer`, 加载宠物或角色待机动画并对齐脚底原点.

## 测试场景

- `tests/test_pet_offsets.tscn`: 独立同类宠物偏移播放测试页, 不是桌宠运行主流程场景; 调试时可通过运行当前场景、`--scene` 参数或临时设为 `project.godot` 的 `run/main_scene` 启动.
- 运行方式: 在 Godot 中打开该场景后运行当前场景, 或使用 `--scene res://tests/test_pet_offsets.tscn` 启动, 默认选择 `40001` 同类组, 同屏显示 `4000101` 到 `4000106`.
- 该测试场景启动时会临时恢复普通可调整窗口, 关闭桌宠透明、无边框和置顶标志, 避免沿用主项目的小透明桌宠窗口.
- 控制项: 同类组选择、`attack/faint/hurt/defense/stand/walk/attackShort` 动作、8 个方向、播放/暂停、上一帧/下一帧、动作上/下、方向左/右、循环、辅助线和 frame/draw_position/region 信息; 键盘方向键左右切方向, 上下切动作.
- 验证重点: 同类宠物同屏同步播放时, 每个宠物的脚底基线应稳定, 用于对比相似宠物的每帧 `draw_position` 是否能修正脚步漂移.
- `tests/test_character_offsets.tscn`: 独立角色偏移播放测试页, 不作为默认启动场景.
- 运行方式: 在 Godot 中打开该场景后运行当前场景, 或使用 `--scene res://tests/test_character_offsets.tscn` 启动, 默认选择 `100001` 角色组, 同时显示 `1000011/1000012/1000013/1000014` 四个颜色变体.
- 控制项: 角色组选择、武器类型选择、`attack/wave/faint/hurt/defense/sad/angry/sit/stand/throw/nod/walk/happy` 动作、8 个方向、播放/暂停、上一帧/下一帧、循环和辅助线; 方向键左右切换方向, 上下切换动作.
- 验证重点: 2x2 四角色同步播放时, 同组不同颜色的脚底基线应稳定且动作节奏一致, 用于观察合并后的角色 `draw_position` 是否能修正动作漂移.
- 站位规则: 敌方在左、己方在右; 每边最多两排, 每排最多 5 个; 位置编号按石器时代顺序映射, `0/5` 为中间, `1/6` 为中间左手, `2/7` 为中间右手, `3/8` 为最左边, `4/9` 为最右边; 第一排靠近战场中线, 第二排略高并向己方外侧错位, 单排按斜向五点展开.

## 测试清单

- 打开 Godot 4.6 项目, 确认 MiniYAML 编辑器插件已启用, TexturePacker 编辑器插件未启用.
- 确认运行后不会生成 `*.sprites/`、`*.tres` 或 `*.tpsheet.import` 批量导入产物.
- 确认 `project.godot` 中 Autoload 顺序为 `YAML` 在前, `GameData` 在后; 运行主场景和测试场景时, 业务脚本通过 `GameData` 读取已初始化的资产和配置.
- 确认 `GameData` 启动时触发 `ConfigManager`, `ConfigManager` 先加载 `AssetManager`, 再通过 MiniYAML 读取标准空格缩进的 `config/pet.yaml`、`config/character.yaml` 和 `config/enemy.group.yaml`, 并按 `asset load -> config load -> config check -> assemble` 初始化资源和配置管理器.
- 确认 `ConfigPet` 能按 ID 返回结构化 `ConfigPet.Entry`, 包含名称、稀有度、属性范围、成长范围、技能槽位和结构化 `action_frame_entries`; YAML 字符串方向和动作在加载后应转换为 `Direction` 和 `PetAction` 枚举 key, 且每个宠物必须补齐全部规定方向和宠物动作; `AnimationPetBuilder` 能继续按 ID 消费所选宠物 `action_frame_entries`, 并通过 `ConfigPet.Entry.asset` 引用读取已合成的同 ID 帧表, 在内存中生成动画.
- 确认 `AnimationCharacterBuilder` 能按 ID 消费 `ConfigCharacter.Entry` 和结构化 `action_frame_entries`; YAML 字符串武器类型, 方向和动作在加载后应转换为 `WeaponType`, `Direction` 和 `CharacterAction` 枚举 key, 且每个角色必须补齐全部规定武器类型, 方向和角色动作; 构建器应通过 `(direction, weapon, action)` 直接定位帧号表, 并通过 `ConfigCharacter.Entry.asset` 引用读取 AssetManager 已合成的同 ID 帧表, 在内存中生成动画.
- 确认 `BattleScene` 能按 ID 消费 `ConfigEnemyGroup` 的 `EnemyGroupEntry` 和 `EnemyEntry` 配置, 并按默认敌人组生成敌方单位.
- 打开 `tests/test_pet_offsets.tscn`, 验证 `4000101` 到 `4000106` 同类宠物同屏显示; 切换 `attack/faint/hurt/defense/stand/walk/attackShort` 和 8 个方向, 使用按钮或键盘左右切方向、上下切动作, 验证全部宠物同步更新且脚底原点稳定.
- 打开 `tests/test_character_offsets.tscn`, 切换角色组、武器类型、`attack/wave/faint/hurt/defense/sad/angry/sit/stand/throw/nod/walk/happy` 和 8 个方向, 验证四个颜色变体同步播放且脚底原点稳定; 使用键盘右键按 `upleft -> up -> upright -> right -> downright -> down -> downleft -> left` 循环切方向, 左键反向循环, 上下切动作, 验证按钮状态和动画同步更新.
- 在宠物偏移测试页开启辅助线, 验证当前 frame id、draw_position 和脚底基线显示正常; 在角色偏移测试页开启辅助线, 验证原点线、脚底基线和当前帧矩形显示正常.
- 需要补充宠物绘制偏移时, 运行 `python .codex/skills/export-pet-offsets/scripts/export_pet_offsets.py --dry-run`, 确认素材导出偏移行数和 `.tpsheet` frame 数一致.
- 需要补充角色绘制偏移时, 运行 `python .codex/skills/export-character-offsets/scripts/export_character_offsets.py --dry-run`, 确认角色素材导出偏移行数和 `.tpsheet` frame 数一致.
- 运行主场景, 确认窗口透明、无边框、置顶, 宠物可见且播放待机动画.
- 验证拖拽窗口、释放后边缘吸附、重启后位置恢复.
- 验证托盘菜单的显示/隐藏, 缩放, 透明度, "宠物 -> ID" 宠物切换, "宠物 -> 动作 -> 动作名 -> 方向", `开始挂机战斗/返回桌宠`, 重置位置, `选项...`, 退出.
- 点击托盘 `开始挂机战斗`, 验证同一个透明无边框置顶窗口内隐藏 `PetModule` 并显示 `BattleModule`, 背景透明, 敌我单位显示完整, 且单宠物随机移动停止; 再点击 `返回桌宠`, 验证战斗单位清空, 桌宠尺寸和位置恢复.
- 点击托盘 `选项...`, 验证账号/关于标签窗口打开且宠物动画不冻结; 在账号页验证无效邮箱和空密码提示, 有效邮箱登录/注册后保存本地占位状态, 退出登录后清空状态.
- 修改 `config/tray_menu.yaml` 隐藏菜单项, 调整顺序, 调整 `pet.items` 层级, 修改 `font_size/colors`, `pet_actions/pet_directions` 或修改 `scale/opacity` 菜单项下的 `options` 后重启, 验证菜单按配置生效且宽度自动适配.
- 通过托盘菜单切换宠物 ID, 验证动画重新加载, 窗口尺寸更新, 当前位置仍被限制在屏幕可用区域内, 且重启后恢复上次选择.
- 通过托盘菜单的 "宠物 -> 动作 -> 动作名 -> 方向" 触发 `stand/walk/attack` 等白名单和当前宠物配置共同存在的动作, 验证方向正确, 缺失动画时回退到 `stand_down` 并输出警告.
- 验证开启鼠标穿透后底层窗口可点击, 并能通过托盘关闭穿透.
- 验证随机挂机动作不会把窗口移出当前屏幕可用区域.

## 待改进项

- `1000021/1000022/1000023/1000024` 角色组的 `unarmed attack` 需要后续单独适配. 当前四个颜色变体的空手攻击帧数量和帧序列不同, 在四角色同步测试页中不能直接按同一动作节奏判断偏移稳定性. 后续可在测试页支持按角色组屏蔽特定动作, 或为该组增加动作别名/专用播放规则.
- 后续新增角色资源时, 需要同步补齐 `config/character.yaml` 的角色配置表和动作帧映射; 需要额外修正绘制位置时再补充 offsets 导出数据, 并通过角色偏移测试场景校验后再纳入可选角色组.
