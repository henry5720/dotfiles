#!/bin/bash
set -euo pipefail

BLUE='\033[0;34m'; NC='\033[0m'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN="${DRY_RUN:-0}"
INPUT_SRC="${INPUT_SRC:-/dev/tty}"
SCRIPTS=(install-base.sh install-tools.sh install-tools-ai.sh)
LABELS=('基底環境' '一般工具' 'AI／文件工具')

echo -e "${BLUE}=== 開發環境安裝 (WSL Ubuntu) ===${NC}"
echo '請選擇要執行的安裝腳本（空格分隔多選，直接 Enter 不執行）：'
for i in "${!SCRIPTS[@]}"; do printf '  %d) %s (%s)\n' "$((i+1))" "${LABELS[$i]}" "${SCRIPTS[$i]}"; done
printf '> '; picks=(); read -a picks <"$INPUT_SRC" || true
selected=(); for n in "${picks[@]}"; do [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#SCRIPTS[@]}" ] && selected+=("${SCRIPTS[$((n-1))]}"); done
[ "${#selected[@]}" -gt 0 ] || { echo '未選擇任何腳本，結束。'; exit 0; }
echo "將執行：${selected[*]}"
if [ "$DRY_RUN" = 1 ]; then echo 'DRY_RUN: 不實際執行。'; exit 0; fi
for script in "${selected[@]}"; do INPUT_SRC="$INPUT_SRC" bash "$SCRIPT_DIR/$script"; done
echo -e "${BLUE}=== 完成！重開終端機或執行 'zsh' 生效 ===${NC}"
