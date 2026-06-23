# sa.desktop 项目规则

本项目继承用户级 `AGENTS.md`, 下列规则仅描述 `sa.desktop` 特有约束.

# 配置管理约定

- 配置管理必须遵循 `load -> check -> assemble` 分层: `load()` 负责单表内部结构、字段合法性、枚举转换、重复项、必填项和同一配置文件内引用校验; `check()` 只负责跨配置表、跨管理器或配置到资源索引的关系校验, 不做单表字段补救、默认兜底或表内合法性修正; `assemble()` 只负责挂载已校验过的引用和派生运行期缓存. 共享初始化入口使用 `ConfigManager.get_shared()`, 顺序为 `assets.load() -> 各配置 load() -> 各配置 check() -> 各配置 assemble()`.

# 文档同步约定

- 修改本项目代码、配置、场景、插件、资源管线或启动流程时, 必须同步检查 `README.md` 是否需要更新.
- `README.md` 至少应覆盖项目定位、MVP 范围、架构、资源管线、核心模块、目录说明、测试清单和待改进项.
- 修改窗口行为、托盘行为、鼠标穿透、透明窗口、资源生成、动画播放或设置持久化时, 必须同步更新相关设计说明.
- 如果相关文档需要更新, 必须在同一轮改动中一起更新.
- 如果确认无需更新文档, 最终回复中必须说明已检查哪些文档以及为什么无需修改.

# Godot 开发约定

- 项目目标版本为 Godot 4.6, 第一版优先支持 Windows.
- 优先使用 GDScript 和 Godot 原生能力, 避免过早引入 Win32/GDExtension.
- 不手工修改 `.godot/` 目录内容, `.godot/` 视为 Godot 编辑器生成缓存.
- 修改 `project.godot` 前必须说明原因, 并确认是否影响窗口、插件、主场景、渲染或导出行为.
- 主窗口行为优先通过 Godot `DisplayServer` 实现, 包括透明、无边框、置顶、窗口位置、窗口大小和鼠标穿透.
- 桌宠移动采用小窗口移动模型, 不默认使用全屏透明覆盖层.
- 新增场景放入 `scenes/`, 新增脚本放入 `scripts/`, 新增配置放入 `config/`, 新增协议放入 `proto/`; 修改 `proto/*.proto` 后运行 `./proto/gen.sh`, 输出 `proto/sa.pb.gd`.
- 主运行场景为 `scenes/main.window.tscn`, 业务内容通过 `MainWindow/ContentRoot` 在 `scenes/character.create.tscn`、`scenes/game.tscn`、`scenes/combat.tscn` 间切换, 不额外创建新窗口.
- `project.godot` 的 Autoload 顺序保持为 `YAML -> GPB -> GCfgMgr -> GRecord -> GTray`.
- Windows 真实鼠标穿透依赖 `native/windows_click_through_helper.exe`; 调试或导出穿透相关功能时, 保持其与 `sa.exe` 的 `native/` 相对路径不变.

# 资源管线约定

- 优先复用现有 `addons`, 尤其是 `addons/codeandweb.texturepacker` 和 `addons/miniyaml`.
- 现有 PNG、`.tpsheet`、YAML 配置是源数据, 不要为了生成动画资源而复制一套 PNG.
- TexturePacker 生成的帧资源必须能追溯到原始 `.tpsheet` 和 PNG.
- 动画资源生成逻辑必须能追溯到 `config/pet.yaml` 中的宠物 ID、方向、动作和帧编号.
- 第一版主角资源固定为 `assets/pet/4000101`, 扩展多宠物前先完成单宠物桌宠闭环.
- 修改资源配置时, 注意 `config/pet.yaml` 和 `config/character.yaml` 使用 UTF-8.
- 宠物和角色每帧偏移统一写在对应 `.tpsheet` 的 sprite `offset: [x, y]` 字段, 不再维护独立 offsets JSON; 无 offset 的帧按零偏移处理.
- 不要手工编辑 Godot 导入缓存来规避真实导入问题.

# 注释规则

- Godot 相关代码的注释要尽量详尽, 不只说明“做了什么”, 还要说明节点职责、生命周期回调、信号连接、窗口/DisplayServer 行为、资源加载、动画播放和坐标/尺寸计算等关键原因, 使代码可作为学习 Godot 的参考.
- 代码注释要有助于理解思路和逻辑, 优先说明职责边界、设计原因、流程顺序、状态变化、数据约束和失败处理; 避免只重复代码表面语句.

# 测试约定

- 修改 Godot 场景、脚本、插件或项目配置后, 需要说明已执行或无法执行的验证方式.
- 桌宠窗口相关改动至少验证透明窗口、无边框、置顶、拖拽、吸附、托盘、鼠标穿透和设置持久化.
- 资源管线相关改动至少验证 `.tpsheet` 导入、YAML 读取、帧映射和动画播放.
- 如果当前环境没有可用 Godot CLI 或无法打开编辑器, 最终回复必须明确说明未能本地运行 Godot 验证.
- 调整 `.tpsheet` 或帧锚点后, 至少运行 `tests/test_pet_offsets.tscn` 或 `tests/test_character_offsets.tscn` 验证锚点稳定和动作同步.
