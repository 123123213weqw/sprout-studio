#!/bin/zsh
cd "$(dirname "$0")" || exit 1
if ! command -v node >/dev/null 2>&1; then
  echo 'Install Node.js 22 or newer, then open this launcher again.'
  read '?Press Return to exit…'
  exit 1
fi
echo 'Starting Sprout with the V100 DeepSeek V4.1 Flash service. The key stays on V100.'
echo 'Open http://127.0.0.1:4173/ and choose the model service in Assistant settings.'
echo 'Startup makes no model calls. Generate only stages a candidate; Apply changes the song.'
echo 'Closing this terminal stops the local server and SSH bridge.'
node scripts/start-v100.mjs
