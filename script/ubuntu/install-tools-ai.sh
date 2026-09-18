#!/bin/bash
set -euo pipefail

GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
DRY_RUN="${DRY_RUN:-0}"; INPUT_SRC="${INPUT_SRC:-/dev/tty}"
TOOLS=(claude codex opencode document-media ai-document-media)
LABELS=('Claude Code' 'Codex' 'OpenCode' '文件／影音解析' 'AI 文件／影音解析')
DOC_MEDIA_PACKAGES=(ffmpeg mupdf-tools pandoc python3-venv)
ai_media_venv() { local d="${AI_DOCUMENT_MEDIA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/ai-document-media}"; printf '%s\n' "${AI_DOCUMENT_MEDIA_VENV:-$d/venv}"; }
installed() { case "$1" in claude|codex|opencode) command -v "$1" &>/dev/null;; document-media) for p in "${DOC_MEDIA_PACKAGES[@]}"; do dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' || return 1; done;; ai-document-media) [ -x "$(ai_media_venv)/bin/python" ] && "$(ai_media_venv)/bin/python" -c 'import docling, faster_whisper' &>/dev/null;; *) return 1;; esac; }
install_claude() { installed claude && { echo '✅ Claude Code 已安裝。'; return; }; curl -fsSL https://claude.ai/install.sh | bash; }
install_codex() { installed codex && { echo '✅ Codex 已安裝。'; return; }; curl -fsSL https://chatgpt.com/codex/install.sh | bash; }
install_opencode() { installed opencode && { echo '✅ OpenCode 已安裝。'; return; }; curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path; }
install_document_media() { local missing=() p; for p in "${DOC_MEDIA_PACKAGES[@]}"; do dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' || missing+=("$p"); done; [ "${#missing[@]}" -eq 0 ] || { sudo apt update; sudo apt install -y "${missing[@]}"; }; }
install_ai_document_media() {
  local venv_dir="$(ai_media_venv)" python packages=() backend="${AI_DOCUMENT_MEDIA_BACKEND:-venv}"; command -v python3 &>/dev/null || { echo '⚠️ 找不到 python3。' >&2; return 1; }
  [ "$backend" = venv ] || [ "$backend" = uv ] || { echo '⚠️ AI_DOCUMENT_MEDIA_BACKEND 只能是 venv 或 uv。' >&2; return 1; }
  if [ "$backend" = uv ]; then command -v uv &>/dev/null || { echo '⚠️ 找不到 uv。' >&2; return 1; }; [ -x "$venv_dir/bin/python" ] || { mkdir -p "$(dirname "$venv_dir")"; uv venv --python python3 "$venv_dir"; }; else
    python3 -c 'import venv' &>/dev/null || { sudo apt update; sudo apt install -y python3-venv; }; [ -x "$venv_dir/bin/python" ] || { mkdir -p "$(dirname "$venv_dir")"; python3 -m venv "$venv_dir"; }; fi
  python="$venv_dir/bin/python"; "$python" -c 'import docling' &>/dev/null || packages+=(docling); "$python" -c 'import faster_whisper' &>/dev/null || packages+=(faster-whisper)
  [ "${#packages[@]}" -eq 0 ] || { [ "$backend" = uv ] && uv pip install --python "$python" "${packages[@]}" || "$python" -m pip install "${packages[@]}"; }
  echo "AI 解析 venv：$venv_dir（不下載或初始化 model）"
}
echo '請選擇 AI／文件工具（空格分隔多選，直接 Enter = 全部）：'; for i in "${!TOOLS[@]}"; do installed "${TOOLS[$i]}" && mark=' ✅' || mark=''; printf '  %d) %s%s\n' "$((i+1))" "${LABELS[$i]}" "$mark"; done
printf '> '; picks=(); read -a picks <"$INPUT_SRC" || true; selected=(); if [ "${#picks[@]}" -eq 0 ]; then selected=("${TOOLS[@]}"); else for n in "${picks[@]}"; do [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#TOOLS[@]}" ] && selected+=("${TOOLS[$((n-1))]}"); done; fi
[ "${#selected[@]}" -gt 0 ] || { echo '未選擇任何工具，結束。'; exit 0; }; echo "將安裝：${selected[*]}"; [ "$DRY_RUN" = 1 ] && { echo 'DRY_RUN: 不實際安裝。'; exit 0; }; for tool in "${selected[@]}"; do "install_${tool//-/_}"; done
