# Ougi

LANraragi 插件仓库（plugin registry）。LANraragi 可以把本仓库配置为插件源，
从中安装 / 升级 / 卸载插件。

> 本仓库是 [Difegue/Ougi](https://github.com/Difegue/Ougi) 的 fork，已修正原仓库中
> 与 LANraragi 校验器不符的部分（详见下方"与原仓库的差异"）。

## 目录结构

**目录名必须等于插件的 namespace**，这一点是硬性要求，不是命名习惯：

```text
registry.json
artifacts/
└── <namespace>/            ← 必须等于插件 plugin_info 里的 namespace
    └── <semver>/           ← 必须等于插件 plugin_info 里的 version
        └── <Plugin>.pm     ← 文件名决定包名，见下
```

例如：

```text
artifacts/
├── ehplugin/2.6.0/EHentai.pm
├── nhsrcconv/1.0.0/nHentaiSourceConverter.pm
└── trabant/2.4.0/Chaika.pm
```

## 插件文件要求

以 `artifacts/ehplugin/2.6.0/EHentai.pm` 为例，必须满足：

1. **包名**必须是
   `LANraragi::Plugin::Managed::<类型目录>::<文件名不含 .pm>`
   → `package LANraragi::Plugin::Managed::Metadata::EHentai;`

   类型目录映射：`metadata`→`Metadata`、`download`→`Download`、
   `login`→`Login`、`script`→`Scripts`。

2. **`plugin_info` 里的 `namespace`** 必须等于目录名（`ehplugin`）。
   这条最关键：LANraragi 安装时按**目录名/仓库键名**记账，运行时却按插件声明的
   namespace 查找。两者不一致会装出一个卸载不掉、升级不了的孤儿插件。

3. **`plugin_info` 里的 `version`** 必须等于版本目录名，且是合法
   [SemVer 2.0.0](https://semver.org/)（`2.6` ✗，`2.6.0` ✓，不允许前导零）。

4. **`parameters` 必须是 hash 式**，不能是数组式：

   ```perl
   # ✓ 正确
   parameters => { lang => { type => "string", desc => "..." } },
   # ✗ 错误（生成器会拒绝）
   parameters => [ { type => "string", desc => "..." } ],
   ```

## 生成 / 更新 registry.json

`registry.json` 由脚本生成，**不要手写**：

```bash
curl -fsSLO https://raw.githubusercontent.com/Difegue/LANraragi/dev/tools/generate_registry.pl
perl generate_registry.pl .
```

生成器会遍历 `artifacts/`、读取每个插件的 `plugin_info`、计算 sha256，
并写入 `registry.json`。

## 本地校验

提交前跑一遍（零依赖，只需要 python3）：

```bash
python3 tools/validate_registry.py
```

CI（`.github/workflows/validate-registry.yml`）会在每次 push / PR 时自动执行：
先跑上面的校验器，再用上游生成器重新生成一次并比对，防止改了插件忘了更新
`registry.json`。

## 发布新版本

1. 新建 `artifacts/<namespace>/<新版本号>/<Plugin>.pm`（旧版本目录保留）
2. 更新该文件 `plugin_info` 里的 `version`
3. 重新生成 `registry.json`
4. 跑一遍本地校验

## 已知限制：与内置插件的 namespace 冲突

LANraragi 安装插件时会扫描整个 `lib/LANraragi/Plugin/` 目录（**包含随镜像内置的
插件**），若 namespace 已存在则拒绝安装：

```
Namespace 'ehplugin' already exists in .../Plugin/Metadata/EHentai.pm
```

本仓库中绝大多数插件（如 `ehplugin`、`nhplugin`、`hitomiplugin`、`trabant` 等）
对应的同名插件都**已经内置在 LANraragi 镜像里**，因此在标准安装上会安装失败。
这属于上游的设计问题，不是仓库数据错误。

要用起来这些插件，需要先让镜像不再内置它们（改为完全由本仓库分发）。

## 与原仓库（Difegue/Ougi）的差异

原仓库的 `registry.json` 无法通过 LANraragi 的校验，原因是：

| 问题 | 原仓库 | 本仓库 |
|---|---|---|
| 目录名 = namespace | ✗（用 `metadata-chaika` 这类描述性目录名） | ✓（改为 `trabant` 等真实 namespace） |
| 包名 | `LANraragi::Plugin::Metadata::Chaika` | `LANraragi::Plugin::Managed::Metadata::Chaika` |
| namespace 大小写 | `DateAddedPlugin`、`Hdoujinplugin` | `dateaddedplugin`、`hdoujinplugin` |
| 版本号 SemVer | `0.004.1`（前导零非法） | `0.4.1` |

（上游生成器里那条"目录名必须等于 namespace"的检查目前是被注释掉的，
所以它不会报错，会直接产出不合规的 `registry.json`。本仓库的 CI 补上了这道校验。）

## License

MIT，见 [LICENSE](LICENSE)。
