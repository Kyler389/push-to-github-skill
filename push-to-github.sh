#!/bin/bash
# push-to-github.sh — GitHub 推送 Skill v2
# 用法: ./push-to-github.sh [选项] [远程仓库URL]
#   --dry-run    只检查环境，不执行推送
#   --yes        自动确认所有提示（适合自动化/CI）
#   --ssh        优先使用 SSH 方式（需提前配置好 SSH key）

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DRY_RUN=false
AUTO_YES=false
USE_SSH=false
REMOTE_ARG=""

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --yes) AUTO_YES=true ;;
        --ssh) USE_SSH=true ;;
        --help|-h)
            echo "GitHub 推送 Skill"
            echo "用法: $0 [--dry-run] [--yes] [--ssh] [远程仓库URL]"
            echo "  --dry-run   只检查环境，不执行推送"
            echo "  --yes       自动确认所有提示"
            echo "  --ssh       优先使用 SSH 方式推送"
            exit 0
            ;;
        *) REMOTE_ARG="$arg" ;;
    esac
done

DEFAULT_REPO_NAME=$(basename "$(pwd)")

echo -e "${BLUE}=== GitHub 推送 Skill ===${NC}"
echo "当前目录: $(pwd)"
[ "$DRY_RUN" = true ] && echo -e "${YELLOW}[ Dry Run 模式 — 仅检查，不执行 ]${NC}"
echo ""

confirm() {
    local prompt="$1"
    [ "$AUTO_YES" = true ] && return 0
    read -rp "$prompt [Y/n]: " ans
    [[ ! "$ans" =~ ^[Nn]$ ]]
}

# ── 网络诊断 ──
check_network() {
    if command -v curl >/dev/null 2>&1; then
        curl -sI https://github.com --connect-timeout 8 >/dev/null 2>&1
    elif command -v wget >/dev/null 2>&1; then
        wget -q --spider --timeout=8 https://github.com >/dev/null 2>&1
    else
        return 0
    fi
}

# ── 远程仓库可达性检查 ──
check_remote_exists() {
    local url="$1"
    git ls-remote --heads "$url" >/dev/null 2>&1
}

# ── SSH key 检测 ──
has_ssh_key() {
    [ -f "$HOME/.ssh/id_ed25519.pub" ] || [ -f "$HOME/.ssh/id_rsa.pub" ]
}

# ── 将 HTTPS 转为 SSH ──
https_to_ssh() {
    local url="$1"
    echo "$url" | sed -E 's#https://github\.com/([^/]+)/(.+)\.git#git@github.com:\1/\2.git#'
}

# ── 凭证助手修复 ──
fix_credential_helper() {
    local helper
    helper=$(git config --global credential.helper 2>/dev/null || echo "")
    if [ "$helper" = "manager-core" ]; then
        git config --global credential.helper manager
        echo -e "${YELLOW}→ 已更新凭证助手: manager-core → manager${NC}"
    fi
}

# 1. 检查/初始化本地 Git 仓库
if [ -d ".git" ]; then
    echo -e "${GREEN}✓ 本地 Git 仓库已存在${NC}"
else
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}→ 待执行: git init${NC}"
    else
        echo -e "${YELLOW}→ 正在初始化本地 Git 仓库...${NC}"
        git init
        echo -e "${GREEN}✓ 本地仓库初始化完成${NC}"
    fi
fi

# 2. 配置用户信息
if [ -z "$(git config user.name)" ]; then
    if [ "$AUTO_YES" = true ]; then
        echo -e "${RED}✗ 未设置 Git 用户名，且 --yes 模式下无法交互输入${NC}"
        exit 1
    fi
    echo -e "${YELLOW}⚠ 未检测到 Git 用户名配置${NC}"
    read -rp "请输入你的 Git 用户名: " GIT_USER_NAME
    git config user.name "$GIT_USER_NAME"
fi

if [ -z "$(git config user.email)" ]; then
    if [ "$AUTO_YES" = true ]; then
        echo -e "${RED}✗ 未设置 Git 邮箱，且 --yes 模式下无法交互输入${NC}"
        exit 1
    fi
    echo -e "${YELLOW}⚠ 未检测到 Git 邮箱配置${NC}"
    read -rp "请输入你的 Git 邮箱: " GIT_USER_EMAIL
    git config user.email "$GIT_USER_EMAIL"
fi

# 3. 检查远程仓库
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")

if [ -n "$REMOTE_URL" ]; then
    echo ""
    echo -e "${GREEN}✓ 已配置远程仓库: ${REMOTE_URL}${NC}"
    if ! confirm "是否推送到此远程仓库"; then
        if [ "$AUTO_YES" = true ]; then
            echo -e "${YELLOW}--yes 模式下跳过更换远程仓库${NC}"
        else
            read -rp "请输入新的远程仓库地址 (或留空跳过): " NEW_REMOTE
            if [ -n "$NEW_REMOTE" ]; then
                REMOTE_URL="$NEW_REMOTE"
                if [ "$DRY_RUN" = false ]; then
                    git remote remove origin 2>/dev/null || true
                    git remote add origin "$REMOTE_URL"
                    echo -e "${GREEN}✓ 远程仓库已更新${NC}"
                fi
            else
                echo -e "${YELLOW}取消推送${NC}"
                exit 0
            fi
        fi
    fi
else
    echo ""
    echo -e "${YELLOW}→ 未配置远程仓库${NC}"

    if [ -n "$REMOTE_ARG" ]; then
        REMOTE_URL="$REMOTE_ARG"
        echo -e "${BLUE}使用提供的仓库地址: ${REMOTE_URL}${NC}"
    else
        if [ "$AUTO_YES" = true ]; then
            echo -e "${RED}✗ 未提供远程仓库地址，且 --yes 模式下无法交互输入${NC}"
            exit 1
        fi
        read -rp "请输入你的 GitHub 用户名: " GITHUB_USER
        read -rp "请输入仓库名称 (默认: ${DEFAULT_REPO_NAME}): " REPO_NAME
        REPO_NAME=${REPO_NAME:-$DEFAULT_REPO_NAME}

        if [ "$USE_SSH" = true ] && has_ssh_key; then
            REMOTE_URL="git@github.com:${GITHUB_USER}/${REPO_NAME}.git"
        else
            REMOTE_URL="https://github.com/${GITHUB_USER}/${REPO_NAME}.git"
        fi
        echo -e "${BLUE}将推送到: ${REMOTE_URL}${NC}"
    fi

    if [ "$DRY_RUN" = false ]; then
        git remote add origin "$REMOTE_URL"
        echo -e "${GREEN}✓ 远程仓库已添加${NC}"
    fi
fi

# 4. 保存远程地址
if [ "$DRY_RUN" = false ]; then
    git config --local github.remote-url "$REMOTE_URL"
    fix_credential_helper
fi

# Dry Run 结束
if [ "$DRY_RUN" = true ]; then
    echo ""
    echo -e "${BLUE}=== Dry Run 检查完成 ===${NC}"
    echo -e "远程仓库: ${REMOTE_URL:-(待设置)}"
    has_ssh_key && echo -e "SSH key: ${GREEN}已检测到${NC}（可用 --ssh 优先使用）"
    exit 0
fi

# 5. 网络检查
echo ""
if ! check_network; then
    echo -e "${RED}✗ 无法连接到 GitHub (https://github.com)${NC}"
    echo -e "${YELLOW}可能原因:${NC}"
    echo "  • 网络未连接或防火墙阻止"
    echo "  • DNS 解析异常"
    echo "  • 若在国内，GitHub 可能间歇性不可达，建议稍后重试或配置代理"
    echo ""
    echo "配置代理示例:"
    echo "  git config --global http.proxy  http://127.0.0.1:7890"
    echo "  git config --global https.proxy http://127.0.0.1:7890"
    exit 1
fi
echo -e "${GREEN}✓ GitHub 网络连通正常${NC}"

# 6. 检查远程仓库是否存在
if ! check_remote_exists "$REMOTE_URL"; then
    echo ""
    echo -e "${RED}✗ 远程仓库不可访问: ${REMOTE_URL}${NC}"

    # 分析原因
    if echo "$REMOTE_URL" | grep -q "^https://github.com/"; then
        if curl -sI "${REMOTE_URL%.git}" --connect-timeout 8 2>/dev/null | grep -q "404"; then
            echo -e "${YELLOW}原因: 仓库不存在。请先在 GitHub 创建:${NC}"
            echo "  https://github.com/new"
            echo "  仓库名: $(basename "${REMOTE_URL%.git}")"
            echo "  不要勾选 README / .gitignore / License"
        else
            echo -e "${YELLOW}原因: 网络或认证问题${NC}"
        fi
    elif echo "$REMOTE_URL" | grep -q "^git@github.com:" && ! has_ssh_key; then
        echo -e "${YELLOW}原因: 使用 SSH 但未配置 SSH key${NC}"
        echo "生成命令: ssh-keygen -t ed25519 -C '你的邮箱'"
        echo "然后将 ~/.ssh/id_ed25519.pub 内容添加到 GitHub → Settings → SSH and GPG keys"
    fi
    exit 1
fi
echo -e "${GREEN}✓ 远程仓库可访问${NC}"

# 7. 检查是否有变更需要提交
echo ""
echo -e "${BLUE}→ 检查文件变更...${NC}"

if git diff --cached --quiet && git diff --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    echo -e "${YELLOW}⚠ 没有检测到新的变更${NC}"
    if ! confirm "是否强制推送当前分支"; then
        echo -e "${YELLOW}取消推送${NC}"
        exit 0
    fi
else
    echo ""
    echo -e "${BLUE}变更摘要:${NC}"
    git status -sb
    echo ""

    echo -e "${BLUE}→ 正在暂存所有变更...${NC}"
    git add -A

    COMMIT_MSG="update"
    if [ "$AUTO_YES" = false ]; then
        read -rp "请输入提交信息 (默认: 'update'): " input_msg
        [ -n "$input_msg" ] && COMMIT_MSG="$input_msg"
    fi

    git commit -m "$COMMIT_MSG"
    echo -e "${GREEN}✓ 提交完成 [${COMMIT_MSG}]${NC}"
fi

# 8. 推送到远程
echo ""
echo -e "${BLUE}→ 正在推送到 GitHub...${NC}"

CURRENT_BRANCH=$(git branch --show-current)

set +e
PUSH_OUTPUT=$(git push -u origin "$CURRENT_BRANCH" 2>&1)
PUSH_EXIT=$?
set -e

if [ $PUSH_EXIT -ne 0 ]; then
    echo ""
    echo -e "${RED}✗ 推送失败${NC}"
    echo "$PUSH_OUTPUT"
    echo ""

    if echo "$PUSH_OUTPUT" | grep -qi "repository not found"; then
        echo -e "${YELLOW}提示: 仓库不存在，请先创建${NC}"
    elif echo "$PUSH_OUTPUT" | grep -qi "authentication failed\|permission denied\|403"; then
        echo -e "${YELLOW}提示: 认证失败，检查凭据或仓库权限${NC}"
    elif echo "$PUSH_OUTPUT" | grep -qi "could not resolve\|connection refused\|timeout\|failed to connect"; then
        echo -e "${YELLOW}提示: 网络问题，稍后重试或配置代理${NC}"
    fi
    exit 1
fi

echo "$PUSH_OUTPUT"
echo ""
echo -e "${GREEN}=== 推送成功! ===${NC}"
echo -e "远程仓库: ${REMOTE_URL}"
echo -e "分支: ${CURRENT_BRANCH}"
