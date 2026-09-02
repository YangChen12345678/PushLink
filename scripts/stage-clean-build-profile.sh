#!/bin/sh
# 把 build-profile.json5 的 app.signingConfigs 清空后放进 Git 暂存区，
# 工作区文件保持原样——DevEco 的本地签名配置不受影响，编译照常。
#
# 用法：在提交前执行一次
#     sh scripts/stage-clean-build-profile.sh
set -e
cd "$(git rev-parse --show-toplevel)"

CLEAN=$(node -e '
const fs = require("fs");
let t = fs.readFileSync("build-profile.json5", "utf8");
const i = t.indexOf("\"signingConfigs\"");
if (i < 0) { process.stdout.write(t); process.exit(0); }
const j = t.indexOf("[", i);
let depth = 0, k = j;
for (; k < t.length; k++) {
  if (t[k] === "[") depth++;
  else if (t[k] === "]") { depth--; if (depth === 0) break; }
}
process.stdout.write(t.slice(0, j) + "[]" + t.slice(k + 1));
')

BLOB=$(printf '%s' "$CLEAN" | git hash-object -w --stdin)
git update-index --add --cacheinfo 100644,"$BLOB",build-profile.json5
echo "已将 signingConfigs 清空的版本放入暂存区（工作区未改动）。"
