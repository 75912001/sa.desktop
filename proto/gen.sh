#!/usr/bin/env bash
# 使用严格模式执行生成脚本:
# -e 让任意命令失败时立即退出, 避免继续使用不完整的生成结果。
# -u 让未定义变量直接报错, 避免路径或参数拼写错误被静默忽略。
# pipefail 让管道中任意命令失败时整体失败, 便于尽早暴露真实错误。
set -euo pipefail
# 让 ERR trap 覆盖函数内部未显式处理的失败, 统一输出带行号的诊断信息。
set -E

# 定位脚本所在目录的上一级, 并把它作为项目根目录。
# 这样无论用户从哪个目录调用 proto/gen.sh, 后续相对路径都以项目根目录为准。
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Godot 控制台程序路径。
# 外部可以通过 GODOT_BIN 环境变量覆盖默认值, 便于不同机器使用自己的 Godot 安装位置。
GODOT_BIN="${GODOT_BIN:-}"
# 协议入口文件。Godobuf 会从这个 proto 文件开始解析并生成 GDScript 协议代码。
PROTO_ENTRY="proto/sa.proto"
# 生成代码输出目录。这里要求目录已存在, 脚本不会自动创建, 以便暴露目录结构问题。
OUTPUT_DIR="proto"
# 最终生成的 GDScript 协议文件。
OUTPUT_FILE="$OUTPUT_DIR/sa.pb.gd"
# Godobuf 的命令行脚本。Godot 会通过 --script 运行它来执行 proto 到 gd 的转换。
GODOBUF_CMD="addons/godobuf/godobuf_cmdln.gd"

print_error() {
	printf '\033[91m%s\033[0m\n' "$1" >&2
}

print_success() {
	printf '\033[92m%s\033[0m\n' "$1"
}

print_info() {
	printf '%s\n' "$1"
}

# 统一错误出口。错误信息输出到 stderr, 并用非 0 状态码结束脚本。
error() {
	print_error "错误: $*"
	exit 1
}

handle_unexpected_error() {
	local line_no="$1"
	local exit_code="$2"
	print_error "错误: 协议生成脚本在第 ${line_no} 行失败, 退出码: ${exit_code}"
	exit "$exit_code"
}

trap 'handle_unexpected_error "$LINENO" "$?"' ERR

# 检查指定路径是否为普通文件。缺少输入文件或工具脚本时立即失败。
require_file() {
	[ -f "$1" ] || error "文件不存在: $1"
}

# 检查指定路径是否为目录。输出目录缺失时不自动创建, 避免掩盖项目结构异常。
require_dir() {
	[ -d "$1" ] || error "目录不存在: $1"
}

# 输出当前 shell 能看到的 PATH 诊断信息。
# Git Bash 只会继承启动时的 Windows 环境变量, 如果修改系统 PATH 后没有重开终端,
# 这里通常看不到新加入的 Godot 目录; 直接打印相关片段能避免把环境问题误判为脚本路径问题。
show_godot_path_hint() {
	printf '%s\n' "未在当前 Git Bash PATH 中找到 Godot, 当前相关 PATH 条目:" >&2
	local path_entry
	local found_related_path=0
	while IFS= read -r path_entry; do
		case "$path_entry" in
			*Godot*|*godot*|*软件*)
				printf '  %s\n' "$path_entry" >&2
				found_related_path=1
				;;
		esac
	done < <(printf '%s' "$PATH" | tr ':' '\n')

	if [ "$found_related_path" -eq 0 ]; then
		printf '%s\n' "  未发现包含 Godot 或 软件 的 PATH 条目" >&2
	fi
}

resolve_existing_file_path() {
	local input_path="$1"
	local normalized_path
	if [ -f "$input_path" ]; then
		printf '%s\n' "$input_path"
		return 0
	fi
	if command -v cygpath >/dev/null 2>&1; then
		if normalized_path="$(cygpath -u "$input_path" 2>/dev/null)" && [ -f "$normalized_path" ]; then
			printf '%s\n' "$normalized_path"
			return 0
		fi
	fi
	return 1
}

# 未显式传入 GODOT_BIN 时, 从 PATH 中查找常见的 Godot 可执行文件名。
# 优先使用 console 版本, 因为生成脚本运行在命令行环境, 控制台版能直接输出错误信息。
resolve_godot_bin() {
	local resolved_path
	if [ -n "$GODOT_BIN" ]; then
		if resolved_path="$(resolve_existing_file_path "$GODOT_BIN")"; then
			GODOT_BIN="$resolved_path"
			return
		fi
		if command -v "$GODOT_BIN" >/dev/null 2>&1; then
			GODOT_BIN="$(command -v "$GODOT_BIN")"
			return
		fi
		show_godot_path_hint
		error "Godot 不存在: $GODOT_BIN. 请确认路径存在, 或在 Git Bash 中执行 command -v \"$GODOT_BIN\" 能找到命令."
	fi

	local candidate
	for candidate in \
		Godot_v4.6.3-stable_win64_console.exe \
		Godot_v4.6.3-stable_win64.exe \
		Godot.exe \
		Godot
	do
		if command -v "$candidate" >/dev/null 2>&1; then
			GODOT_BIN="$(command -v "$candidate")"
			return
		fi
	done

	show_godot_path_hint
	error "Godot 不存在. 请确认 Godot 所在目录已加入 Git Bash 的 PATH, 或使用 GODOT_BIN=/path/to/Godot_console.exe ./proto/gen.sh."
}

to_godot_abs_path() {
	local absolute_path
	absolute_path="$(realpath "$1")"
	if command -v cygpath >/dev/null 2>&1; then
		cygpath -m "$absolute_path"
		return
	fi
	printf '%s\n' "$absolute_path"
}

# 在生成前校验所有必要输入:
# 1. proto 入口文件存在。
# 2. Godobuf 命令行脚本存在。
# 3. 输出目录存在。
# 4. Godot 可执行程序可用, 可以是具体文件路径, 也可以是 PATH 中的命令名。
validate_inputs() {
	require_file "$PROTO_ENTRY"
	require_file "$GODOBUF_CMD"
	require_dir "$OUTPUT_DIR"
	resolve_godot_bin
}

# 调用 Godot 的 headless 模式运行 Godobuf。
# proto 输入使用绝对路径, 避免 Godobuf 内部工作目录变化导致找不到入口文件。
# 输出使用 res:// 路径, 确保生成文件落在当前 Godot 项目的资源树内。
run_godobuf() {
	local proto_entry_abs
	proto_entry_abs="$(to_godot_abs_path "$PROTO_ENTRY")"

	print_info "使用 Godobuf 生成: $PROTO_ENTRY -> $OUTPUT_FILE"
	"$GODOT_BIN" --headless --path . --script "res://$GODOBUF_CMD" \
		--input="$proto_entry_abs" \
		--output="res://$OUTPUT_FILE"
}

# Godobuf 生成的协议脚本默认没有项目约定的 PB 全局脚本类型.
# 项目业务通过 GPB 全局入口访问协议类型, 所以生成后给文件头补上合法的 Godot 顶层脚本声明.
ensure_autoload_base() {
	require_file "$OUTPUT_FILE"
	local first_line
	first_line="$(sed -n '1p' "$OUTPUT_FILE")"
	if [ "$first_line" = "class_name PB" ]; then
		return
	fi

	local output_tmp
	output_tmp="$(mktemp)"
	{
		printf '%s\n%s\n\n' "class_name PB" "extends RefCounted"
		cat "$OUTPUT_FILE"
	} > "$output_tmp"
	mv "$output_tmp" "$OUTPUT_FILE"
}

# 检查生成结果是否真实存在, 并清理 Godot 可能为生成脚本产物创建的 .uid 文件。
# 协议生成结果只需要提交 sa.pb.gd, 不需要把资源 UID 缓存作为协议产物维护。
check_output() {
	require_file "$OUTPUT_FILE"
	[ -s "$OUTPUT_FILE" ] || error "生成文件为空: $OUTPUT_FILE"
	ensure_autoload_base
	rm -f "$OUTPUT_FILE.uid"
}

# 主流程保持为 load/check/run/verify 的顺序:
# 先输出当前项目目录方便排查, 再校验输入, 执行生成, 最后检查生成结果。
main() {
	print_info "项目目录: $PROJECT_ROOT"
	validate_inputs
	print_info "Godot: $GODOT_BIN"
	run_godobuf
	check_output
	print_success "协议生成完成: $OUTPUT_FILE"
}

# 保留 "$@" 透传写法, 方便未来给 main 增加命令行参数而不改调用入口。
main "$@"
