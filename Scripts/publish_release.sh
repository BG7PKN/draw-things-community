#!/usr/bin/env bash
#
# Publish a fork release of draw-things-cli to GitHub Releases.
#
# Run from the `release` branch, after rebasing it onto the upstream commit you
# want to ship -- see RELEASING.md. Tags the current commit as
# v<YY>.<MMDD>-fork.<N>, builds the CLI, and uploads the binary.
#
# Requires: gh (brew install gh, then gh auth login)

set -euo pipefail

GIT_ROOT=$(git rev-parse --show-toplevel)
cd "$GIT_ROOT"

DRY_RUN=0
SKIP_BUILD=0

usage() {
  cat <<'EOF'
用法: Scripts/publish_release.sh [选项]

  --dry-run     只打印将要做什么，不落任何东西
  --skip-build  复用已有的 .build/release/draw-things-cli，不重新构建
  -h, --help    显示本帮助
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --dry-run)    DRY_RUN=1 ;;
    --skip-build) SKIP_BUILD=1 ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "error: 未知参数 '$1'" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

die()  { echo "error: $*" >&2; exit 1; }
note() { echo "==> $*"; }
run()  {
  if (( DRY_RUN )); then
    echo "    [dry-run] $*"
  else
    "$@"
  fi
}

# --- preflight --------------------------------------------------------------

command -v gh >/dev/null 2>&1 || die "gh CLI 没装。装法：brew install gh"
gh auth status >/dev/null 2>&1 || die "gh 未登录。先跑：gh auth login"

BRANCH=$(git rev-parse --abbrev-ref HEAD)
[[ "$BRANCH" == "release" ]] || die "必须在 release 分支上（当前在 '$BRANCH'）"
[[ -z "$(git status --porcelain)" ]] || die "工作区不干净，先提交或 stash"

REMOTE_URL=$(git remote get-url origin 2>/dev/null) || die "没有名为 origin 的 remote"
REMOTE_URL=${REMOTE_URL%.git}
REMOTE_URL=${REMOTE_URL//:/\/}          # git@host:owner/repo -> git@host/owner/repo
SLUG_TAIL=${REMOTE_URL##*/}
SLUG_HEAD=${REMOTE_URL%/*}
SLUG="${SLUG_HEAD##*/}/${SLUG_TAIL}"
[[ "$SLUG" == */* && "$SLUG" != /* ]] || die "无法从 origin 解析 owner/repo，得到：$SLUG"

# main mirrors upstream, so the merge base of main and release is the upstream
# commit the fork patches were rebased onto.
UPSTREAM_BASE=$(git merge-base main release)

BEHIND=$(git rev-list --count "$UPSTREAM_BASE..main")
if (( BEHIND > 0 )); then
  echo "warning: release 基于 ${UPSTREAM_BASE:0:8}，但 main 又多了 $BEHIND 个上游提交。"
  echo "         建议先 'git rebase main release' 再发版。"
  if (( DRY_RUN == 0 )); then
    read -r -p "         仍然继续？[y/N] " reply
    [[ "$reply" == [yY] ]] || die "已取消"
  fi
fi

FORK_COUNT=$(git rev-list --count "$UPSTREAM_BASE..release")
(( FORK_COUNT > 0 )) || die "release 相对上游没有自有提交，没有可发布的内容"

# --- tag --------------------------------------------------------------------

# v<YY>.<MMDD>-fork.<N>: the date is when you cut the release, "-fork" keeps the
# tag distinct from upstream's v<YY>.<MMDD>.<N>, and N counts re-releases cut
# that same day, going back to 1 the next day. Because release branches off
# main, any tag pointing at HEAD is ours.
DATE=$(date +%y.%m%d)
LATEST=$(git tag -l "v${DATE}-fork.*" | sed 's/.*-fork\.//' | sort -n | tail -1)
N=$(( ${LATEST:-0} + 1 ))
TAG="v${DATE}-fork.${N}"

git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "tag $TAG 已存在"

AT_HEAD=$(git tag --points-at HEAD | tr '\n' ' ')
[[ -z "$AT_HEAD" ]] || die "当前 commit 已经打过 tag：${AT_HEAD}——不重复发。要重发请先提交新改动。"

# The tag only identifies *which* release; spell out what the fork changes for
# anyone landing on the Releases page.
RELEASE_TITLE="$TAG · draw-things-cli（H3 多条参考音频）"

# --- build ------------------------------------------------------------------

BINARY=.build/release/draw-things-cli

if (( SKIP_BUILD )); then
  note "跳过构建（--skip-build）"
else
  note "构建 draw-things-cli"
  run Scripts/build_local_cli.sh
fi

if (( DRY_RUN == 0 )); then
  [[ -f "$BINARY" ]] || die "找不到 $BINARY —— 去掉 --skip-build 重跑"
  "$BINARY" --version >/dev/null 2>&1 || die "$BINARY 跑不起来，别发"
  note "二进制 $(ls -lh "$BINARY" | awk '{print $5}')"
fi

# --- release notes ----------------------------------------------------------

BASE_DATE=$(git log -1 --format=%cs "$UPSTREAM_BASE")
NOTES=$(mktemp -t publish-release-notes)
trap 'rm -f "$NOTES"' EXIT

{
  echo "> 这是 **fork 构建**，不是官方版本 —— tag 格式与官方一致，官方并没有同名构建。"
  echo
  echo "基于上游 \`${UPSTREAM_BASE:0:8}\`（${BASE_DATE}）构建。"
  echo
  echo "## 本版相对官方 draw-things-cli 的改动（${FORK_COUNT} 个提交）"
  echo
  git log --no-decorate --format='- %s' "$UPSTREAM_BASE..release"
  echo
  echo "主要差异：**MiniMax H3 Ref2VA 支持多条参考音频** —— 官方只吃 1 条，本版 \`--audio\`"
  echo "可重复传入，用法对齐 \`--image\`。LongCat 与 \`--avc\` 不变，仍要求恰好 1 条音频。"
  echo
  echo "## 安装"
  echo
  echo '```bash'
  echo "curl -L -o draw-things-cli https://github.com/${SLUG}/releases/download/${TAG}/draw-things-cli"
  echo "chmod +x draw-things-cli"
  echo "mkdir -p ~/.local/bin && mv draw-things-cli ~/.local/bin/   # 或 /usr/local/bin"
  echo
  echo "# 二进制未签名，首次运行会被 macOS 拦下，解除隔离标记："
  echo "xattr -d com.apple.quarantine ~/.local/bin/draw-things-cli"
  echo '```'
  echo
  echo "macOS arm64。\`--version\` 输出 \`dev\` 属正常（SwiftPM release 构建不带版本号）。"
} > "$NOTES"

# --- publish ----------------------------------------------------------------

note "tag        $TAG"
note "上游基线   ${UPSTREAM_BASE:0:8}（${BASE_DATE}）"
note "fork 提交  $FORK_COUNT 个"

if (( DRY_RUN )); then
  echo
  echo "    [dry-run] git tag -a $TAG"
  echo "    [dry-run] git push origin release"
  echo "    [dry-run] git push origin $TAG"
  echo "    [dry-run] gh release create $TAG $BINARY --title '$RELEASE_TITLE' --notes-file <下方内容>"
  echo
  echo "---------- Release 说明预览 ----------"
  cat "$NOTES"
  echo "--------------------------------------"
  exit 0
fi

git tag -a "$TAG" -m "$TAG"
git push origin release
git push origin "$TAG"
gh release create "$TAG" "$BINARY" --title "$RELEASE_TITLE" --notes-file "$NOTES"

note "发布完成：https://github.com/${SLUG}/releases/tag/${TAG}"
