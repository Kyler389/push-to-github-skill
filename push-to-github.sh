#!/bin/bash
# push-to-github.sh — GitHub 推送 Skill
# 用法: ./push-to-github.sh [选项] [远程仓库URL]
#   --dry-run    只检查环境，不执行推送
#   --yes        自动确认所有提示（适合自动化/CI）

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DRY_RUN=false
AUTO_YES=false
REMOTE_ARG=""

# 解析参数
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --yes) AUTO_YES=true ;;
        --help|-h)
            echo "GitHub 推送 Skill"
            echo "用法: $0 [--dry-run] [--yes] [远程仓库URL]"
            echo "  --dry-run   只检查环境，不执行推送"
            echo "  --yes       自动确认所有提示"
            exit 0
            ;;
        *) REMOTE_ARG="$arg" ;;
    esac
done

# 获取当前目录名作为默认仓库名
DEFAULT_REPO_NAME=$(basename "$(pwd)")

echo -e "${BLUE}=== GitHub 推送 Skill ===${NC}"
echo "当前目录: $(pwd)"

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[ Dry Run 模式 — 仅检查，不执行 ]${NC}"
fi
echo ""

# 辅助函数：确认提示
confirm() {
    local prompt="$1"
    if [ "$AUTO_YES" = true ]; then
        return 0
    fi
    read -rp "$prompt [Y/n]: " ans
    [[ ! "$ans" =~ ^[Nn]$ ]]
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

# 2. 配置用户信息（如果未设置）
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
                if [ "$DRY_RUN" = true ]; then
                    echo -e "${YELLOW}→ 待执行: 更换远程仓库为 ${NEW_REMOTE}${NC}"
                else
                    git remote remove origin 2>/dev/null || true
                    git remote add origin "$NEW_REMOTE"
                    REMOTE_URL="$NEW_REMOTE"
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
        REMOTE_URL="https://github.com/${GITHUB_USER}/${REPO_NAME}.git"
        echo -e "${BLUE}将推送到: ${REMOTE_URL}${NC}"
    fi

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}→ 待执行: git remote add origin ${REMOTE_URL}${NC}"
    else
        git remote add origin "$REMOTE_URL"
        echo -e "${GREEN}✓ 远程仓库已添加${NC}"
    fi
fi

# 4. 保存远程地址到本地配置
if [ "$DRY_RUN" = false ]; then
    git config --local github.remote-url "$REMOTE_URL"
fi

# Dry Run 到此结束
if [ "$DRY_RUN" = true ]; then
    echo ""
    echo -e "${BLUE}=== Dry Run 检查完成 ===${NC}"
    echo -e "远程仓库: ${REMOTE_URL:-(待设置)}"
    echo -e "运行时不加 --dry-run 即可实际执行推送"
    exit 0
fi

# 5. 检查是否有变更需要提交
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

# 6. 推送到远程
echo ""
echo -e "${BLUE}→ 正在推送到 GitHub...${NC}"

CURRENT_BRANCH=$(git branch --show-current)

if ! git rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2>/dev/null >/dev/null; then
    git push -u origin "$CURRENT_BRANCH"
else
    git push
fi

echo ""
echo -e "${GREEN}=== 推送成功! ===${NC}"
echo -e "远程仓库: ${REMOTE_URL}"
echo -e "分支: ${CURRENT_BRANCH}"
