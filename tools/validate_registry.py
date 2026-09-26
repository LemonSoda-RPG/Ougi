#!/usr/bin/env python3
"""校验 Ougi 插件仓库的 registry.json 是否符合 LANraragi 的 registry 规范。

零第三方依赖。实现规则等价于 LANraragi 的
lib/LANraragi/Utils/Registry.pm::validate_registry_index()，并额外校验：

  1. 运行时不变式：制品里 plugin_info 的 namespace 必须等于仓库键名。
     LRR 安装时按【键名】记账（LRR_PLUGIN_<NAMESPACE>），运行时却按插件
     声明的 namespace 查找；两者不一致会产生"装了但卸载不掉"的孤儿插件。
  2. 磁盘覆盖：每个 artifacts/<ns>/<ver>/*.pm 都要在 registry.json 里有条目，
     且 sha256 与文件实际内容一致（防止改了插件忘了重新生成）。
  3. 包名：制品必须声明 LANraragi::Plugin::Managed::<类型目录>::<文件名>。

用法:
    python3 tools/validate_registry.py [仓库目录]
"""
import hashlib
import json
import os
import re
import sys

SEMVER = re.compile(
    r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
    r'(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)'
    r'(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?'
    r'(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$'
)
# 注意：用 \Z 而不是 \z。\z 是 Perl 写法，Python 直到 3.14 才支持，
# 在 CI 的 Python 3.12 上会直接抛 re.error。
TIMESTAMP = re.compile(r'\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\Z')
NAMESPACE = re.compile(r'\A[a-z0-9_-]+\Z')
SHA256 = re.compile(r'\A[a-f0-9]{64}\Z')
PKG_LINE = re.compile(r'^package\s+(\S+);', re.M)
NS_IN_PLUGIN_INFO = re.compile(r'\bnamespace\s*=>\s*[\'"]([^\'"]+)[\'"]')

TYPE_DIR = {'metadata': 'Metadata', 'download': 'Download', 'login': 'Login', 'script': 'Scripts'}
ALLOWED_ROOT = {'version', 'generated_at', 'plugins'}
ALLOWED_PLUGIN = {'namespace', 'type', 'versions'}
ALLOWED_VERSION = {'version', 'name', 'author', 'description', 'artifact', 'sha256', 'published_at'}
REQUIRED_VERSION = ['name', 'author', 'description', 'artifact', 'sha256', 'published_at']


def validate(root):
    errors = []
    registry_path = os.path.join(root, 'registry.json')

    def err(msg):
        errors.append(msg)

    try:
        with open(registry_path, encoding='utf-8') as fh:
            index = json.load(fh)
    except FileNotFoundError:
        return [f'缺少 {registry_path}']
    except json.JSONDecodeError as exc:
        return [f'registry.json 不是合法 JSON: {exc}']

    if not isinstance(index, dict):
        return ['registry.json 根节点必须是对象']

    for field in index:
        if field not in ALLOWED_ROOT:
            err(f"根节点有未知字段 '{field}'")
    if index.get('version') != 1:
        err('根节点 version 必须为 1')
    if not index.get('generated_at'):
        err("缺少根节点 'generated_at'")
    elif not TIMESTAMP.match(index['generated_at']):
        err("'generated_at' 必须是 UTC RFC3339 时间戳（形如 2026-01-01T00:00:00Z）")
    if not isinstance(index.get('plugins'), dict):
        return errors + ["根节点 'plugins' 必须是对象"]

    seen_on_disk = set()

    for key, plugin in sorted(index['plugins'].items()):
        where = f"插件 '{key}'"
        if not isinstance(plugin, dict):
            err(f'{where} 必须是对象')
            continue
        for field in plugin:
            if field not in ALLOWED_PLUGIN:
                err(f"{where} 有未知字段 '{field}'")
        if plugin.get('namespace') != key:
            err(f"{where} 的键名必须等于内层 namespace（当前为 '{plugin.get('namespace')}'）"
                f' —— LRR 的安装记账与运行时查找都依赖这一点')
        if not NAMESPACE.match(key):
            err(f"{where} 的键名必须匹配 ^[a-z0-9_-]+$（只允许小写）")
        plugin_type = plugin.get('type')
        if plugin_type not in TYPE_DIR:
            err(f"{where} 的 type '{plugin_type}' 无效（应为 metadata/download/login/script）")
            continue
        if not isinstance(plugin.get('versions'), dict) or not plugin['versions']:
            err(f"{where} 的 'versions' 必须是非空对象")
            continue

        type_dir = TYPE_DIR[plugin_type]

        for ver_key, meta in sorted(plugin['versions'].items()):
            vwhere = f"{where} 版本 '{ver_key}'"
            if ver_key.startswith('v'):
                err(f'{vwhere} 版本号不能有 v 前缀')
            elif not SEMVER.match(ver_key):
                err(f'{vwhere} 不是合法的 SemVer 2.0.0 字符串')
            if not isinstance(meta, dict):
                err(f'{vwhere} 必须是对象')
                continue
            for field in meta:
                if field not in ALLOWED_VERSION:
                    err(f"{vwhere} 有未知字段 '{field}'")
            if meta.get('version') != ver_key:
                err(f'{vwhere} 的 version 字段必须等于版本键名')
            for field in REQUIRED_VERSION:
                if not meta.get(field):
                    err(f"{vwhere} 缺少必填字段 '{field}'")
            sha = meta.get('sha256', '')
            if not SHA256.match(str(sha)):
                err(f'{vwhere} 的 sha256 必须是 64 位小写十六进制')

            artifact = meta.get('artifact', '')
            if '\0' in artifact:
                err(f'{vwhere} artifact 路径含空字节')
                continue
            if artifact.startswith('/') or os.path.isabs(artifact):
                err(f'{vwhere} artifact 路径必须是相对路径')
                continue
            if any(seg in ('.', '..') for seg in artifact.split('/')):
                err(f"{vwhere} artifact 路径不能包含 '.' 或 '..' 段")
                continue

            published = meta.get('published_at', '')
            if published and not TIMESTAMP.match(published):
                err(f'{vwhere} 的 published_at 必须是 UTC RFC3339 时间戳')

            disk_path = os.path.join(root, artifact)
            if not os.path.exists(disk_path):
                err(f'{vwhere} 找不到制品文件 {artifact}')
                continue
            seen_on_disk.add(os.path.normpath(artifact))

            with open(disk_path, 'rb') as fh:
                content = fh.read()
            actual = hashlib.sha256(content).hexdigest()
            if SHA256.match(str(sha)) and actual != sha:
                err(f'{vwhere} 的 sha256 与文件内容不符（文件为 {actual}）')

            text = content.decode('utf-8', errors='replace')
            stem = os.path.basename(artifact)[:-3]
            expected_pkg = f'LANraragi::Plugin::Managed::{type_dir}::{stem}'
            found = PKG_LINE.search(text)
            if not found:
                err(f'{vwhere} 制品没有 package 声明')
            elif found.group(1) != expected_pkg:
                err(f'{vwhere} 包名必须是 {expected_pkg}（当前为 {found.group(1)}）')

            inner_ns = NS_IN_PLUGIN_INFO.search(text)
            if not inner_ns:
                err(f'{vwhere} 制品的 plugin_info 里没有 namespace')
            elif inner_ns.group(1) != key:
                err(f"{vwhere} 制品声明的 namespace '{inner_ns.group(1)}' 必须等于键名 '{key}'"
                    f' —— 否则安装后无法卸载/升级')

    # 磁盘覆盖：有制品但 registry.json 里没有对应条目
    art_root = os.path.join(root, 'artifacts')
    if os.path.isdir(art_root):
        for ns in sorted(os.listdir(art_root)):
            ns_path = os.path.join(art_root, ns)
            if not os.path.isdir(ns_path):
                continue
            for ver in sorted(os.listdir(ns_path)):
                ver_path = os.path.join(ns_path, ver)
                if not os.path.isdir(ver_path):
                    continue
                for fname in sorted(os.listdir(ver_path)):
                    if not fname.endswith('.pm'):
                        continue
                    rel = os.path.normpath(os.path.join('artifacts', ns, ver, fname))
                    if rel not in seen_on_disk:
                        err(f'磁盘上的 {rel} 没有对应的 registry.json 条目'
                            f'（改完插件后请重新生成 registry.json）')

    return errors


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    errors = validate(root)
    if errors:
        print(f'❌ registry 校验失败，共 {len(errors)} 项问题：\n')
        for item in errors:
            print(f'  - {item}')
        return 1
    print('✅ registry.json 校验通过')
    return 0


if __name__ == '__main__':
    sys.exit(main())
