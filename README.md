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

`registry.json` 是**生成出来的产物清单，不要手写**。它记录每个插件的类型、每个版本的
制品路径与 sha256——LANraragi 刷新索引时就是拿它判断"有哪些插件、最新版本是哪个、
下载到的文件对不对"。

用仓库自带的脚本重新生成（它按固定 commit 下载上游的 `generate_registry.pl` 并执行，
只依赖 Perl 核心模块，不需要额外装东西）：

```bash
tools/regenerate.sh
```

它做三件事：遍历 `artifacts/<namespace>/<version>/*.pm`、解析每个文件的 `plugin_info`、
对文件算 sha256，然后**覆盖写** `registry.json`。

两点要知道：

- 只写 `registry.json` 一个文件；已有条目里除 `generated_at` 时间戳外都会保留，
  所以"什么都没改"时 `git diff` 只应看到时间戳变化。
- 失败时不会破坏已有文件，但如果 `registry.json` **不存在**，它会先建一个空清单再报错退出，
  于是留下一个空的 `registry.json`。所以生成完一定要跑校验。

## 本地校验

**只读**，不会生成或修改任何文件；有问题时列出原因并以退出码 1 结束。零依赖，只需要 python3：

```bash
python3 tools/validate_registry.py
```

它检查：根字段与 `version`、每个条目的键名是否等于内层 namespace、namespace 是否全小写、
版本号是否合法 SemVer、必填字段、制品路径是否合法、**sha256 是否与磁盘文件一致**、
包名是否为 `Managed::<类型>::<文件名>`、制品里的 `plugin_info namespace` 是否等于键名，
以及**磁盘上每个制品是否都在索引里有条目**（防止改了插件忘了重新生成）。

CI（`.github/workflows/validate-registry.yml`）在每次 push / PR 时自动跑它，
再用上游生成器重新生成一次并比对 `plugins` 部分，同样是为了抓住"忘了重新生成"。

## 发布新版本

已发布的版本**不可变**（生成器拒绝同版本目录里 sha256 变化的制品），所以更新要开新版本目录。
用仓库自带的脚本做这一步，它会同时保证目录名 / `version` 字段 / 包名三者一致：

```bash
tools/new-version.sh <namespace> <新版本号>
#  例: tools/new-version.sh etagcn 2.6.1
#  -> artifacts/etagcn/2.6.1/ETagCN.pm（从当前最新版本复制，version 已改好）

$EDITOR artifacts/<namespace>/<新版本号>/<Plugin>.pm    # 在这里做你的改动

tools/regenerate.sh                                      # 重新生成 registry.json
python3 tools/validate_registry.py                      # 本地校验
git add -A && git commit -m "<namespace> <新版本号>: ..." && git push
```

> 为什么不能原地改：索引里按版本记录了 sha256，而客户端是靠**版本号**判断"有没有更新"的。
> 原地改同版本号的内容，任何自动升级逻辑都不会发现（版本号没变），
> 只有手工强制重装同版本才会生效。

## 更新是怎么被 LANraragi 拿到的

推送后，实例端分两步，**只有第一步是自动的**：

| 步骤 | 是否自动 | 说明 |
|---|---|---|
| 索引 `registry.json` | ✅ **服务启动时自动刷新**所有已配置仓库 | 重启容器即可；不重启则调 `POST /api/registries/{id}/refresh` |
| 插件文件本身 | ❌ **不会自动更新** | 上游没有自动升级逻辑，必须显式安装：`POST /api/plugins/install {"namespace":"...","registry":"REG_..."}`（不带 `version` 时装 SemVer 最大版本） |

两个实践注意点：

- **raw.githubusercontent.com 有约 5 分钟 CDN 缓存**（`cache-control: max-age=300`）。
  刚 push 完立刻刷新，可能仍返回旧索引——等几分钟或重试。
- LANraragi **前端没有插件管理界面**，所以升级只能走 API 或脚本。
  `LemonSoda-RPG/LANraragi` 的 `lanraragi-deploy/upgrade-plugins.pl` 就是为此写的：
  一次完成「刷新所有仓库索引 + 把每个 managed 插件升到最新版」，
  并在升级前用 SemVer 比较，避免把本地更新的版本降级。

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
