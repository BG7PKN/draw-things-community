# Fork 发版手册

本仓库是 [drawthingsai/draw-things-community](https://github.com/drawthingsai/draw-things-community)
的 fork，**唯一目的**是让 `draw-things-cli` 支持 MiniMax H3 Ref2VA 的**多条参考音频**
（官方只支持 1 条）。本文件说明这条 fork 发布线怎么发版。

## 分支模型

| 分支 | 内容 | 规则 |
|---|---|---|
| `main` | 上游镜像 | **零自有提交**，只做 fast-forward |
| `release` | 上游 main 尖端 + fork 补丁 | 唯一发版来源；上游更新后 rebase 过来 |
| `feat/*` | 临时开发分支 | 做完合进 `release` |

`main` 必须和上游保持一致，这样 `git fetch` + `--ff-only` 永远能过，不用解冲突。

## 版本号

```
v26.0925-fork.1
└───┬──┘ └─┬─┘
发版日期   第 N 次发版
```

日期用**你发版那天**，沿用上游的日期风格。同一天重发就是 `.2`、`.3`。

> **为什么 tag 里不写上游版本号**：上游的正式 tag 和社区仓库的源码对不上。
> 例如 `v26.0910.1` 里根本没有 `AudioConditioning.swift` / `LongCatAvatar.swift`，
> 这两个文件是 tag 之后 14 个提交（`d5234173 "Sync missing files."`）才补进社区仓库的，
> 也就是说补丁**无法落在任何现有正式 tag 上**。实际对应的上游 commit 记在 Release 说明里。

## 发版流程

### 1. 同步上游

```bash
git fetch https://github.com/drawthingsai/draw-things-community.git main
git merge --ff-only FETCH_HEAD    # main 快进
git rebase main release           # 把补丁挪到新上游上
```

### 2. 构建 + 实跑验证

```bash
Scripts/build_local_cli.sh
```

### 3. 发布

```bash
Scripts/publish_release.sh
```

脚本依次做：前置检查 → 算 tag 序号 → 构建 → 打 tag → 推分支和 tag → 建 GitHub Release
（附二进制，说明里自动写好上游基线、补丁清单、安装步骤）。

- `--dry-run`：只打印将要做什么，不落任何东西
- `--skip-build`：复用已有的 `.build/release/draw-things-cli`，不重新构建

## 产物

只发 `draw-things-cli`（macOS arm64，约 250MB），和上游 Release 里的同名，方便直接替换。

## 已知风险

- **二进制未签名** —— 下载者首次运行会被 macOS Gatekeeper 拦下，需要
  `xattr -d com.apple.quarantine`。Release 说明里已写好这一步。
- **SDK 标记未在旧系统验证** —— 构建必须带 `-Xlinker -platform_version ... 26.0`
  （原因见 `Scripts/build_local_cli.sh` 里的注释），这个标记在比本机旧的 macOS 上
  行为如何**没有实测过**。发布前最好找台别人的机器跑一次。
- **rebase 可能冲突** —— 上游改过 `Apps/DrawThingsCLI/DrawThingsCLI.swift` 的话，
  补丁里那部分会撞车，需要手工解。
