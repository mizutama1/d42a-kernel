#!/usr/bin/env bash
# d-42A (ELF-8605L) KernelSU-Next kernel build script
# - Lenovo kernel source を自動検出
# - KernelSU-Next (legacy) を組み込み
# - 純正 config + 純正 ramdisk/DTB で boot.img を再構築
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

log() { printf '\n=== %s ===\n' "$*"; }

# ---------------------------------------------------------------- 1. source
KD="${KERNEL_DIR:-}"
if [ -z "$KD" ] || [ ! -f "$KD/Makefile" ]; then
  KD=""
  # リポジトリ内を最大 4 階層まで探索（work/ と out/ は除外）
  while IFS= read -r mk; do
    d="$(dirname "$mk")"
    case "$d" in ./work|./work/*|./out|./out/*) continue ;; esac
    if [ -d "$d/arch/arm64" ] && grep -qE '^VERSION[[:space:]]*=[[:space:]]*4' "$mk"; then
      KD="$d"; break
    fi
  done < <(find . -maxdepth 4 -type f -name Makefile | sort)
fi
if [ -z "$KD" ]; then
  echo "ERROR: kernel source (Makefile + arch/arm64) が見つかりません。"
  echo "リポジトリ直下に展開するか、workflow の kernel_dir を指定してください。"
  exit 1
fi
echo "kernel dir: $KD"

# ------------------------------------------------------- 2. KernelSU-Next
log "KernelSU-Next (legacy) を組み込み"
cd "$KD"
if [ ! -d KernelSU ]; then
  curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s legacy
else
  echo "KernelSU/ は既に存在します（スキップ）"
fi

# ---------------------------------------------------------------- 3. config
log "defconfig を適用"
mkdir -p arch/arm64/configs
cp -f "$ROOT/d42a/config/d42a_defconfig" arch/arm64/configs/d42a_defconfig

export ARCH=arm64
export SUBARCH=arm
export CROSS_COMPILE=aarch64-linux-gnu-
export CLANG_TRIPLE=aarch64-linux-gnu-

make O=out ARCH=arm64 d42a_defconfig

# KernelSU + kprobe 用の設定を強制
scripts/config --file out/.config \
  -e MODULES \
  -e KPROBES \
  -e KPROBE_EVENTS \
  -e KALLSYMS \
  -e KALLSYMS_ALL \
  -e KSU \
  -e KSU_KPROBE_HOOKS \
  --set-str LOCALVERSION "-perf"

# 追加指定 (workflow input, 空白区切り。例: "KSU_MANUAL_HOOK")
for c in ${EXTRA_CONFIGS:-}; do
  echo "extra config: $c"
  scripts/config --file out/.config -e "$c"
done

make O=out ARCH=arm64 olddefconfig

log "有効化チェック"
grep -E '^CONFIG_(KSU|KSU_KPROBE_HOOKS|KPROBES|KPROBE_EVENTS|KALLSYMS_ALL|LOCALVERSION)=' out/.config || true

# ----------------------------------------------------------------- 4. build
log "ビルド開始"
JOBS="$(nproc)"
MAKEVARS=(ARCH=arm64 O=out CC=clang CROSS_COMPILE=aarch64-linux-gnu- CLANG_TRIPLE=aarch64-linux-gnu-)
if ! make -j"$JOBS" "${MAKEVARS[@]}" KCFLAGS="-Wno-error" Image 2>&1 | tee out/build.log; then
  echo "Image ターゲットで失敗。デフォルトターゲットで再試行します"
  make -j"$JOBS" "${MAKEVARS[@]}" KCFLAGS="-Wno-error" 2>&1 | tee -a out/build.log
fi

IMG="out/arch/arm64/boot/Image"
[ -f "$IMG" ] || { echo "ERROR: $IMG が生成されていません"; exit 1; }
gzip -9 -c "$IMG" > out/Image.gz
ls -l "$IMG" out/Image.gz

# ------------------------------------------------------------- 5. repack boot
log "boot.img を再構築（純正 ramdisk/DTB を維持）"
mkdir -p "$ROOT/out"
python3 "$ROOT/d42a/tools/bootimg.py" unpack "$ROOT/d42a/boot/stock_boot.img" out/boot_unpack
python3 "$ROOT/d42a/tools/bootimg.py" repack out/boot_unpack "$ROOT/out/boot-ksu.img" --kernel out/Image.gz

cp -f out/Image.gz "$ROOT/out/Image.gz"
cp -f out/.config "$ROOT/out/kernel.config"
cp -f out/build.log "$ROOT/out/build.log"
ls -l "$ROOT/out"
echo "DONE: $ROOT/out/boot-ksu.img"
