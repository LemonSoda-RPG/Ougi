# Ougi

本 fork 的 LANraragi 插件仓库（plugin registry）。LANraragi 可以把本仓库配置为插件源，
从中安装 / 升级 / 卸载插件。

只收录**本 fork 自己的插件**；原先从上游 Ougi 收录的那批已全部移除，
原因见[本仓库收录哪些插件](#本仓库收录哪些插件)。

> 本仓库最初是 [Difegue/Ougi](https://github.com/Difegue/Ougi) 的 fork，
> 修好了它 `registry.json` 通不过 LANraragi 校验的问题（详见"与原仓库的差异"）。

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

## CI 会替你做什么

`.github/workflows/validate-registry.yml` 在每次 push / PR 时：

1. 用上游生成器**重新生成** `registry.json`——所以你**不需要**在本地跑生成
2. 跑上面的校验器
3. 如果 `plugins` 部分和仓库里的不一致（即你改了插件但没更新索引），
   就把生成结果**提交回 main**，不需要你手动补

也就是说：**发布/更新插件只需要改 `artifacts/` 下的源码**，索引由 CI 负责。

唯一 CI 替不了你的是**版本号**（见下）。如果改动了已发布版本里的制品，生成器会拒绝，
CI 会失败并提示你用 `tools/new-version.sh` 开新版本目录。

## 发布新版本

已发布的版本**不可变**（生成器拒绝同版本目录里 sha256 变化的制品），所以更新要开新版本目录。
用仓库自带的脚本做这一步，它会同时保证目录名 / `version` 字段 / 包名三者一致：

```bash
tools/new-version.sh <namespace> <新版本号>
#  例: tools/new-version.sh etagcn 2.6.1
#  -> artifacts/etagcn/2.6.1/ETagCN.pm（从当前最新版本复制，version 已改好）

$EDITOR artifacts/<namespace>/<新版本号>/<Plugin>.pm    # 在这里做你的改动
git add -A && git commit -m "<namespace> <新版本号>: ..." && git push
# registry.json 由 CI 生成并提交
```

如果要先自检一遍（可选）：

```bash
tools/regenerate.sh              # 生成索引
python3 tools/validate_registry.py   # 校验
```

> 为什么不能原地改：索引里按版本记录了 sha256，而客户端是靠**版本号**判断"有没有更新"的。
> 原地改同版本号的内容，任何自动升级逻辑都不会发现（版本号没变），
> 只有手工强制重装同版本才会生效。版本号该升哪一位是语义决策（修 bug→patch、
> 加功能→minor、破坏性→major），所以留给作者定，CI 不猜。

## 更新是怎么被 LANraragi 拿到的

推送后，实例端的两个环节：

| 环节 | 上游默认行为 | 本 fork 的行为 |
|---|---|---|
| 索引 `registry.json` | ✅ 服务启动时自动刷新所有已配置仓库 | 同左 |
| 插件文件本身 | ❌ 不自动更新，必须调 `POST /api/plugins/install` | ✅ **服务启动时自动升级**（见下） |

本 fork 在 `LANraragi.pm` 的启动流程里，紧接在"刷新所有仓库索引"之后调用了
`Model::Plugins::upgrade_managed_plugins()`，因此**重启容器就会把 registry 安装的插件
升到最新版**，日志里会有：

```
[LANraragi] [info] Startup plugin upgrade: duplicatearchives 1.1.1 -> 1.1.2
```

它的边界（都有测试覆盖）：

- 只动**通过 registry 安装**的插件；内置（builtin）和手动放置（sideloaded）的一律不碰
- 只从**安装它时用的那个 registry**取新版
- **绝不降级**：索引陈旧（raw.githubusercontent.com 有 ~5 分钟缓存）或本地版本更新时都跳过
- 单个插件升级失败只记日志，不影响服务启动

不想自动升级就设 `LRR_AUTO_UPDATE_PLUGINS=0`（docker-compose 的 `environment` 里加一行即可）。
不重启想立刻升级，可以手动跑 `LemonSoda-RPG/LANraragi` 的
`lanraragi-deploy/upgrade-plugins.pl`——它调用的是同一个函数，不是另一份实现。

两个实践注意点：

- **raw.githubusercontent.com 有约 5 分钟 CDN 缓存**（`cache-control: max-age=300`）。
  刚 push 完立刻重启，可能仍刷到旧索引、于是这次不升级——过几分钟再重启即可。
- 前端没有插件管理界面。要在**不重启**的情况下立刻升级，用
  `LemonSoda-RPG/LANraragi` 的 `lanraragi-deploy/upgrade-plugins.pl`
  （它调用的是服务端同一个升级函数，不是另一份实现）。

## 本仓库收录哪些插件

只有本 fork 自己的三个插件：

| namespace | 版本 | 类型 |
|---|---|---|
| `etagcn` | 2.6.0 | metadata |
| `addehentaimetatdata` | 1.3.0 | script |
| `duplicatearchives` | 1.1.0 / 1.1.1 / 1.1.2 | script |

它们已从 LANraragi 镜像里**去掉内置**、改由本仓库分发，
所以安装时不会撞上"namespace 已存在"的冲突检查（该检查会扫描整个 `Plugin/` 目录）。

原先从上游 Ougi 收录的那 21 个插件（`ehplugin`、`nhplugin`、`trabant` 等）已全部移除，原因：

- 它们的同名插件**已经内置在 LANraragi 镜像里**，安装会被拒绝
  （`Namespace 'ehplugin' already exists in .../Plugin/Metadata/EHentai.pm`），
  在本 fork 上根本装不上；
- 而且它们是**合并前的快照**，落后于镜像里的内置版本
  （例如 `nhplugin` 缺少上游 `db310690` 的单引号搜索修复）。

留着只会误导。真要让它们也走 registry 分发，应当**以当前内置文件为源重新生成制品**，
而不是启用仓库里那份旧快照。

## 删除插件时要同时改 registry.json

生成器**不会自动剔除已删除的插件**，而是直接报错退出：

```
Manifest references namespace 'xxx' with no artifact directory
```

所以删除一个插件的完整步骤是：

```bash
git rm -r artifacts/<namespace>

# 手动删掉 registry.json 里对应的条目——生成器不做这件事
python3 - <<'PY'
import json
p = 'registry.json'
d = json.load(open(p, encoding='utf-8'))
del d['plugins']['<namespace>']
json.dump(d, open(p, 'w', encoding='utf-8'), indent=2, ensure_ascii=False)
PY

tools/regenerate.sh                  # 规范化并刷新 generated_at
python3 tools/validate_registry.py   # 两边不同步时这里会报"找不到制品文件"
```

## 与原仓库（Difegue/Ougi）的差异

当初为了让 `registry.json` 能通过 LANraragi 的校验，修正了下面这些问题。
涉及的正是后来被移除的那批上游插件，这里保留作为**规范参考**——
新增插件时依然要满足这些约束：

| 问题 | 原仓库 | 本仓库 |
|---|---|---|
| 目录名 = namespace | ✗（用 `metadata-chaika` 这类描述性目录名） | ✓（必须与 `plugin_info` 的 namespace 一致） |
| 包名 | `LANraragi::Plugin::Metadata::Chaika` | `LANraragi::Plugin::Managed::Metadata::Chaika` |
| namespace 大小写 | `DateAddedPlugin`、`Hdoujinplugin` | 只允许小写 `[a-z0-9_-]` |
| 版本号 SemVer | `0.004.1`（前导零非法） | `0.4.1` |

（上游生成器里那条"目录名必须等于 namespace"的检查目前是被注释掉的，
所以它不会报错，会直接产出不合规的 `registry.json`。本仓库的 CI 补上了这道校验。）

## License

MIT，见 [LICENSE](LICENSE)。
