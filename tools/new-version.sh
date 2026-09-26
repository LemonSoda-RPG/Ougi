#!/usr/bin/env bash
# 从某个插件当前的版本复制出一个新版本目录，用于发布更新。
#
# 为什么需要它：已发布的版本不能原地修改（生成器会拒绝 sha256 变化的已发布版本），
# 更新必须落到新的版本目录；而且目录名、plugin_info 里的 version、包名三者必须一致，
# 手工改很容易漏。
#
# 用法:
#   tools/new-version.sh <namespace> <新版本号> [源码文件路径]
#
# 例:
#   tools/new-version.sh etagcn 2.6.1
#     -> artifacts/etagcn/2.6.1/ETagCN.pm（从 2.6.0 复制，version 改成 2.6.1）
#   如果插件源码当前不在仓库里（例如你在别处维护），可以指定源文件：
#   tools/new-version.sh etagcn 2.6.1 /path/to/ETagCN.pm
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [ $# -lt 2 ]; then
    sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 1
fi

NS="$1"
NEWVER="$2"
SRC_OVERRIDE="${3:-}"

if ! printf '%s' "$NS" | grep -Eq '^[a-z0-9_-]+$'; then
    echo "错误：namespace 必须匹配 ^[a-z0-9_-]+$（全小写），当前为 '$NS'" >&2
    exit 1
fi

if ! printf '%s' "$NEWVER" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'; then
    echo "错误：版本号必须是 SemVer 的 X.Y.Z（不允许前导零），当前为 '$NEWVER'" >&2
    exit 1
fi

NS_DIR="artifacts/$NS"
[ -d "$NS_DIR" ] || { echo "错误：$NS_DIR 不存在" >&2; exit 1; }

if [ -d "$NS_DIR/$NEWVER" ]; then
    echo "错误：$NS_DIR/$NEWVER 已存在，不能覆盖已发布的版本" >&2
    exit 1
fi

if [ -n "$SRC_OVERRIDE" ]; then
    [ -f "$SRC_OVERRIDE" ] || { echo "错误：找不到源文件 $SRC_OVERRIDE" >&2; exit 1; }
    SRC="$SRC_OVERRIDE"
    FILE_NAME="$(basename "$SRC_OVERRIDE")"
else
    # 取当前最大版本目录作为模板
    LATEST="$(printf '%s\n' "$NS_DIR"/*/ | xargs -n1 basename | sort -V | tail -1)"
    SRC_DIR="$NS_DIR/$LATEST"
    SRC="$(find "$SRC_DIR" -maxdepth 1 -name '*.pm' | head -1)"
    [ -n "$SRC" ] || { echo "错误：$SRC_DIR 下没有 .pm 文件" >&2; exit 1; }
    FILE_NAME="$(basename "$SRC")"
fi

DEST_DIR="$NS_DIR/$NEWVER"
mkdir -p "$DEST_DIR"
cp "$SRC" "$DEST_DIR/$FILE_NAME"
DEST="$DEST_DIR/$FILE_NAME"

# 目录名必须等于 plugin_info 里的 version，否则生成器会报 Version directory mismatch
perl -0pi -e 's/(\bversion\s*=>\s*")[^"]*(")/${1}'"$NEWVER"'${2}/' "$DEST"

CURRENT_VERSION="$(grep -m1 -oE '\bversion\s*=>\s*"[^"]*"' "$DEST" | sed 's/.*"\(.*\)"/\1/')"
if [ "$CURRENT_VERSION" != "$NEWVER" ]; then
    echo "错误：$DEST 里的 version 仍是 '$CURRENT_VERSION'，请手动确认后重试" >&2
    exit 1
fi

echo "已创建 $DEST_DIR/$FILE_NAME（version -> $NEWVER）"
echo
echo "接下来："
echo "  1. 编辑 $DEST 实现你的改动"
echo "  2. perl /path/to/LANraragi/tools/generate_registry.pl .   # 重新生成 registry.json"
echo "  3. python3 tools/validate_registry.py                      # 本地校验"
echo "  4. git add -A && git commit -m \"$NS $NEWVER: ...\" && git push"
echo "  5. 等约 5 分钟（GitHub raw CDN max-age=300），再在实例上执行升级脚本"
