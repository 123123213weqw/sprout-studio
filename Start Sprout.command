#!/bin/zsh
cd "$(dirname "$0")" || exit 1
if ! command -v node >/dev/null 2>&1; then
  echo '请先安装 Node.js 22 或更新版本，再打开 Sprout Studio。'
  read '?按回车退出…'
  exit 1
fi
echo 'Sprout Studio 已准备好。请打开 http://127.0.0.1:4173/'
echo '页面不自动播放，点击播放后有声音。关闭此终端会停止服务器。'
node server.mjs
