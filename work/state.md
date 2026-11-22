# 現状（state）

最終更新: 2026-11-23 02:05

## ゴール
- d-42A (dtab Compact d-42A / Lenovo ELF-8605L / docomo) を KernelSU 化
  - GitHub Actions でカーネルをビルド
  - Zygisk Next 等で root 検出回避
  - 純正 boot.img / カーネルソースの入手
- できるだけ確認なしで（破壊的削除はしない）

## 端末（実測 / adb・fastboot）
| 項目 | 値 |
|---|---|
| serial | HA18JVX3 |
| model | d-42A (Lenovo ELF-8605L, Type ZA7N) |
| SoC | trinket / SM6125 (Snapdragon 665) |
| OS | Android 12 (SDK 31) |
| build | d-42A_S_S203037_2212092223_JP / SKQ1.220201.001 |
| fingerprint | Lenovo/d-42A/d-42A:12/SKQ1.220201.001/...:user/release-keys |
| kernel | 4.14.190-perf+ #1 SMP PREEMPT Sat Dec 10 01:49:30 CST 2022 aarch64 |
| compiler | clang 10.0.7 (Android NDK) / GNU ld 2.27 |
| A/B | なし (A-only, slot_suffix 空) |
| bootloader | **unlocked** (verifiedbootstate=orange, flash.locked=0, sys.oem_unlock_allowed=1) |
| root | なし（su/Magisk なし） |
| shell から block dev | 読めない (/dev/block/sde11 0600 root:root) |
| recovery | 起動可だが adb は `unauthorized`（/data 未マウントで adb_keys 無し）。sideload も不可 |

## 重要な入手物（すべて work/ 以下、削除禁止）
- `orig/d-42A_S_S203037_2212092223_JP.zip` … 純正ファーム (2,287,941,964 bytes, lolinet ミラー)
  - URL: https://mirrors-obs-1.lolinet.com/firmware/lenowow/2020/docomo/D-42A/d-42A_S_S203037_2212092223_JP.zip
  - 中身: boot.img(64MB), recovery.img(96MB), dtbo.img(8MB), vbmeta, super_*.img, NON-HLOS.bin,
    **prog_firehose_ddr.elf / prog_firehose_lite.elf**, rawprogram*.xml, patch*.xml, gpt_*.bin など
- `orig/fw/` … 上記から抽出した boot.img ほか（EDL 用 firehose 含む）
- `boot/kernel` (gzip, 14,887,248 B) / `boot/ramdisk` (gzip, 709,145 B) / `boot/dtb` (515,277 B)
- `boot/kernel.raw` … 展開済み ARM64 Image (35,095,040 B)
- `boot/config.txt` … IKCONFIG から抽出した実カーネル config (160,393 B)

## boot.img 解析結果
- header v2 / page 4096 / kernel_addr 0x8000 / ramdisk_addr 0x1000000 / dtb_addr 0x1f00000
- cmdline: `androidboot.hardware=qcom ... androidboot.fstab_suffix=default buildvariant=user`
- `boot/dtb` は 9 個の DTB 連結。8番目が trinket SoC (338,521 B)。d-42A 固有は dtbo の overlay
  - dtbo overlay 内のパネル: td4330_truly(cmd/video), hx83112a_truly, nt36672_truly, hx82790_boe_fhd, sim
  - touch: synaptics_tcm / himax_ts / focaltech, SAR: abov_sar, battery: 4602692_LC_ATL_P500_5000mAH_PMI632
  - → Qualcomm trinket QRD リファレンスに近い構成

## カーネル config の要点（boot/config.txt）
- `CONFIG_LOCALVERSION="-perf"` → release は `4.14.190-perf+`
- `CONFIG_MODULES=y` / `CONFIG_MODVERSIONS=y` / `CONFIG_MODULE_SIG=y` → .ko は完全一致必須
- **`CONFIG_KPROBES` は未設定** → KernelSU の kprobe フックが使えない（manual hook が必要 or KPROBES を有効化して再ビルド）
- `CONFIG_STATIC_USERMODEHELPER=y` → KernelSU の usermode helper 実行に影響する可能性（要検証）
- `CONFIG_IKCONFIG=y` / `CONFIG_IKCONFIG_PROC=y` / `CONFIG_KALLSYMS=y`
- SELinux: `CONFIG_SECURITY_SELINUX=y`

## カーネルソースの状況（ブロッカー）
- KernelSU 1.0+ は非 GKI 非対応 → **KernelSU-Next `legacy` ブランチ**が候補（4.4〜6.x, manual hook 対応）
- d-42A の純正カーネルソースは未発見:
  - `opensource.lenovo.com` は NXDOMAIN（Lenovo OSS ポータルは support.lenovo.com/HT511330 に移行）
  - HT511330 の一覧に dtab / d-42A は無し（Phones のみ数機種）
  - 製品ページ `pcsupport.lenovo.com/.../d-42a-elf-8605l/za7n/downloads` にも Open Source Code の項目なし
  - GitHub `toromame8373/d-42A_kernel` は空リポジトリ
- 代替案: trinket 4.14 の CAF/LineageOS 系ソース + 純正 config + 純正 DTB でビルドし、
  `fastboot boot` で非破壊テスト（失敗しても再起動で戻る）
- 最終手段: Magisk（boot.img パッチ）+ 内蔵 Zygisk + Shamiko で root/隠蔽は達成可能

## 端末の現在の状態（要注意）
- 02:00 頃 `fastboot reboot recovery` で recovery に入れたが **adb unauthorized のまま**。
  fastboot からも制御できないため、**本体の電源ボタン長押し（10〜15秒）で再起動が必要**。
- 復旧手段: 純正 boot/recovery/super イメージを fastboot で書き戻せる（すべて手元にあり）

## 次の一手
1. ユーザーに電源長押しで通常起動へ戻してもらう
2. 起動後: `/proc/config.gz`, `/vendor/lib/modules/*.ko`, `/proc/device-tree/compatible` を回収
3. Magisk パッチ boot で root 取得（安全・即効）→ バックアップ & 情報収集
4. 並行して KernelSU-Next legacy + trinket 4.14 ソースで GitHub Actions ビルドを準備し、
   `fastboot boot` で検証 → 成功したら flash

## 追記 (2026-11-23 02:10)
- boot.img 末尾に **AVB footer** を確認: `AVBf` @ 0x3FFFF00、original_image_size=0x00F60000 (16,121,856)、
  vbmeta_offset=0x00F60000、vbmeta_size=0x380（boot 内に埋め込み vbmeta あり）
  - パッチ後は AVB ハッシュが変わるが、bootloader unlocked (orange) のため検証は無効化されている想定
  - flash 時は元の vbmeta/footer 領域が残らないよう注意（必要なら後で検証）
- `work/tools/bootimg.py` を自作（v0/v1/v2 unpack/repack）。純正 boot.img で **round-trip 完全一致**を確認済み
- ツール取得済み（work/tools/）:
  - Magisk-v31.1.apk
  - KernelSU-Next-manager.apk (v3.4.2)
  - Zygisk-Next-1.5.3.zip
  - Zygisk-Assistant-2.1.4.zip
- KernelSU-Next legacy 手順メモ: `notes/ksun_legacy.md`
  - kprobe 方式: setup.sh legacy + CONFIG_KPROBES/KPROBE_EVENTS/KSU_KPROBE_HOOKS/KSU=y
  - 純正 config は KPROBES 無効なので、ビルド時に有効化が必要
- KernelSU-Next は v3.4.2 が最新

## 追記 (2026-11-23 02:30) GitHub リポジトリ作成・push 完了
- GitHub アカウント: `mizutama1`（device flow で認証、token は `~/.d42a_gh_token` に 600 で保存）
- リポジトリ: **https://github.com/mizutama1/d42a-kernel**（Public）
- push 済み: `.github/workflows/build-kernel.yml`（Actions で active を確認）, `d42a/` 一式, work の md/ツール
- ローカル git: branch `main`, origin 追跡設定済み（credential helper は token ファイル参照）
- Actions 実行方法: リポジトリ → Actions → build-kernel → Run workflow
  - `source_url` に Lenovo カーネルソース tar.gz の URL を指定（未 push の場合）
  - `kernel_dir` は空で自動検出
- 未対応: 4.14 では `KSU_KPROBES_HOOK` 非推奨（Kconfig に「5.10 未満では使うな」）かつ
  `KSU_SYSCALL_TABLE_HOOK` は 4.17+ 必須 → **`KSU_MANUAL_HOOK=y` + ソースへのパッチ**が本命。
  ソース入手後に build.sh / patches を差し替える。
