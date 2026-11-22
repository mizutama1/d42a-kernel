#!/usr/bin/env bash
# d-42A (ELF-8605L) / trinket 4.14.190 KernelSU-Next ビルドスクリプト
#  - Lenovo 純正ソース（kernel-4.14/msm-4.14）を自動検出
#  - KernelSU-Next (legacy) を in-tree で組み込み
#  - 4.14 は kprobe hook 非対応なので manual hook を挿入
#  - 純正 config / ramdisk / DTB を使って boot.img を再構築
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

log() { printf '\n=== %s ===\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- 1. source
KD="${KERNEL_DIR:-}"
if [ -n "$KD" ] && [ ! -f "$KD/Makefile" ]; then
  echo "WARN: KERNEL_DIR=$KD に Makefile がありません。自動検出します"
  KD=""
fi
if [ -z "$KD" ]; then
  while IFS= read -r mk; do
    d="$(dirname "$mk")"
    case "$d" in ./work|./work/*|./out|./out/*|./.git|./.git/*) continue ;; esac
    if [ -d "$d/arch/arm64" ] && grep -qE '^VERSION[[:space:]]*=[[:space:]]*4' "$mk"; then
      KD="$d"; break
    fi
  done < <(find . -maxdepth 6 -type f -name Makefile | sort)
fi
[ -n "$KD" ] || die "カーネルソースが見つかりません（Makefile + arch/arm64 が必要）"
KD="$(cd "$KD" && pwd)"
echo "kernel dir : $KD"
grep -E '^(VERSION|PATCHLEVEL|SUBLEVEL) ' "$KD/Makefile" | tr '\n' ' '; echo

# ------------------------------------------------------- 2. KernelSU-Next
log "KernelSU-Next (legacy) を組み込む"
cd "$KD"
if [ -d KernelSU-Next ] || [ -e drivers/kernelsu ]; then
  echo "既に組み込み済み（スキップ）"
else
  curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/legacy/kernel/setup.sh" -o /tmp/ksu-setup.sh
  sh /tmp/ksu-setup.sh legacy
fi
[ -e drivers/kernelsu ] || die "drivers/kernelsu が作成されていません（setup.sh 失敗）"

# ------------------------------------------------------- 3. manual hooks
log "manual hook をカーネルソースへ挿入（4.14 は kprobe 非対応）"
python3 "$ROOT/d42a/patches/apply_manual_hooks.py" "$KD"

# ---------------------------------------------------------------- 4. config
log "defconfig を適用"
mkdir -p arch/arm64/configs
cp -f "$ROOT/d42a/config/d42a_defconfig" arch/arm64/configs/d42a_defconfig

export ARCH=arm64
export SUBARCH=arm
export LC_ALL=C

make O=out ARCH=arm64 d42a_defconfig

# 純正 config を維持しつつ、必要な点だけ変更する
#  - KSU: in-tree 組み込み + manual hook
#  - MODULE_SIG_FORCE: 純正 vendor .ko は Lenovo の鍵で署名されているため、
#    こちらのビルド鍵で強制検証すると .ko が全部ロードできなくなる。無効化する。
scripts/config --file out/.config \
  -e MODULES \
  -e KALLSYMS \
  -e KALLSYMS_ALL \
  -e KSU \
  -e KSU_MANUAL_HOOK \
  -d KSU_KPROBES_HOOK \
  -d KSU_SYSCALL_TABLE_HOOK \
  -d MODULE_SIG_FORCE \
  --set-str LOCALVERSION "-perf"

for c in ${EXTRA_CONFIGS:-}; do
  echo "extra config: $c"
  scripts/config --file out/.config -e "$c"
done

make O=out ARCH=arm64 olddefconfig

log "有効化チェック"
grep -E '^CONFIG_(KSU|KSU_MANUAL_HOOK|MODULES|KALLSYMS_ALL|LOCALVERSION|MODVERSIONS|PREEMPT)=' out/.config || true
grep -E '^# CONFIG_(KSU_KPROBES_HOOK|KSU_SYSCALL_TABLE_HOOK|MODULE_SIG_FORCE) is not set' out/.config || true
grep -q '^CONFIG_KSU=y' out/.config || die "CONFIG_KSU が有効になっていません"
grep -q '^CONFIG_KSU_MANUAL_HOOK=y' out/.config || die "CONFIG_KSU_MANUAL_HOOK が有効になっていません"

# ----------------------------------------------------------------- 5. build
log "ビルド開始"
JOBS="$(nproc)"
if [ -x "$KD/build_tools/bin/clang" ]; then
  echo "toolchain: 純正 build_tools (clang + aarch64-linux-android-4.9) を使用"
  export PATH="$KD/build_tools/aarch64-linux-android-4.9/bin:$PATH"
  MAKEVARS=(
    ARCH=arm64 O=out
    CROSS_COMPILE=aarch64-linux-android-
    DTC_EXT="$KD/build_tools/dtc"
    DTC_OVERLAY_TEST_EXT="$KD/build_tools/ufdt_apply_overlay"
    CONFIG_BUILD_ARM64_DT_OVERLAY=y
    REAL_CC="$KD/build_tools/bin/clang"
    CLANG_TRIPLE=aarch64-linux-gnu-
  )
else
  echo "toolchain: システムの clang / aarch64-linux-gnu- を使用"
  MAKEVARS=(
    ARCH=arm64 O=out
    CC=clang
    CROSS_COMPILE=aarch64-linux-gnu-
    CLANG_TRIPLE=aarch64-linux-gnu-
  )
fi

set +e
make -j"$JOBS" "${MAKEVARS[@]}" KCFLAGS="-Wno-error" Image 2>&1 | tee out/build.log
rc=${PIPESTATUS[0]}
set -e
if [ "$rc" -ne 0 ] || [ ! -f out/arch/arm64/boot/Image ]; then
  echo "Image ビルド失敗 (rc=$rc)。ログ末尾:"
  tail -n 60 out/build.log
  die "ビルド失敗"
fi

IMG="out/arch/arm64/boot/Image"
gzip -9 -c "$IMG" > out/Image.gz
ls -l "$IMG" out/Image.gz

# ------------------------------------------------------------- 6. repack boot
log "boot.img を再構築（純正 ramdisk / DTB を維持）"
rm -rf out/boot_unpack "$ROOT/out"
mkdir -p "$ROOT/out"
python3 "$ROOT/d42a/tools/bootimg.py" unpack "$ROOT/d42a/boot/stock_boot.img" out/boot_unpack
python3 "$ROOT/d42a/tools/bootimg.py" repack out/boot_unpack "$ROOT/out/boot-ksu.img" --kernel out/Image.gz

cp -f out/Image.gz "$ROOT/out/Image.gz"
cp -f "$IMG" "$ROOT/out/Image"
cp -f out/.config "$ROOT/out/kernel.config"
cp -f out/build.log "$ROOT/out/build.log"
ls -l "$ROOT/out"
echo "DONE: $ROOT/out/boot-ksu.img"
