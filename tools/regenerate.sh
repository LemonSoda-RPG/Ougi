#!/usr/bin/env bash
# 重新生成 registry.json。
#
# 索引由上游的 generate_registry.pl 生成（只依赖 Perl 核心模块）。它不在本仓库里，
# 所以这里按固定 commit 下载后执行——固定 commit 是为了让生成结果稳定，
# 不受上游后续改动影响（CI 用的是同一个 commit）。
#
# 用法:
#   tools/regenerate.sh
set -euo pipefail

# 与 .github/workflows/validate-registry.yml 中的 GENERATOR_REF 保持一致
GENERATOR_REF=db3106900d90e07f5723da9ed933cc0399a5670d
GENERATOR_URL="https://raw.githubusercontent.com/Difegue/LANraragi/${GENERATOR_REF}/tools/generate_registry.pl"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

echo "下载生成器（commit ${GENERATOR_REF:0:7}）..."
curl -fsSL -o "$TMP" "$GENERATOR_URL"

perl "$TMP" .

echo
echo "接着跑一遍校验（只读，不会改文件）:"
echo "  python3 tools/validate_registry.py"
