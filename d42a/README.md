# d-42A (ELF-8605L) KernelSU-Next ビルド

## 構成
```
.github/workflows/build-kernel.yml  … GitHub Actions（手動実行）
d42a/build.sh                       … 組み込み + ビルド + boot.img 再構築
d42a/config/d42a_defconfig          … 純正カーネル config（IKCONFIG から抽出）
d42a/boot/stock_boot.img            … 純正 boot.img（ramdisk/DTB の供給元・復旧用）
d42a/tools/bootimg.py               … boot image v0/v1/v2 unpack/repack
```

## 前提
- カーネルソース: Lenovo 純正 4.14.190（`Makefile` + `arch/arm64` を含むディレクトリ）
- 純正カーネルは `CONFIG_KPROBES` 無効 → `build.sh` が `KPROBES/KPROBE_EVENTS/KSU_KPROBE_HOOKS/KSU` を有効化
- boot.img は純正 ramdisk/DTB を維持し、kernel だけ差し替え（AVB は unlocked のため未更新）

## GitHub Actions の使い方
1. リポジトリ作成（Public 推奨）
2. `.github/` `d42a/` `.gitignore` を push
   - ソースを push しない場合は Actions 実行時に `source_url` を指定（推奨）
3. Actions → `build-kernel` → Run workflow
4. Artifact `boot-ksu` を取得（`boot-ksu.img` / `Image.gz` / `kernel.config` / `build.log`）
5. 実機:
   ```
   adb reboot bootloader
   fastboot boot boot-ksu.img        # 非破壊テスト
   fastboot flash boot boot-ksu.img  # 問題なければ本適用
   ```
6. 失敗時は純正に戻す:
   ```
   fastboot flash boot d42a/boot/stock_boot.img
   ```

## 入力
| name | 説明 |
|---|---|
| `source_url` | カーネルソース tar.gz の URL（空ならリポジトリ内を使用） |
| `kernel_dir` | ソースのディレクトリ（空なら自動検出） |
| `extra_configs` | 追加 CONFIG（例: `KSU_MANUAL_HOOK`） |
