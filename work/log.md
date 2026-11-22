# 実行ログ

## 2026-11-22 / 2026-11-23（セッション1）

### 環境確認
- `adb devices` → `HA18JVX3 device`
- `adb shell getprop ...` → d-42A / trinket / Android 12 / kernel 4.14.190-perf+ / verifiedbootstate=orange / flash.locked=0
- `adb shell dd if=/dev/block/sde11 ...` → **Permission denied**（shell からは block dev 不可）
- `adb shell which su` → 無し（未 root）

### ネットワーク / 調査
- `curl https://github.com` → 200（ネット利用可）
- KernelSU 公式: 非 GKI は手動ビルド。1.0 以降非対応、最終対応 v0.9.5
- KernelSU-Next: `legacy` ブランチで 4.4〜6.x 対応、manual hook あり
- d-42A の純正ファーム発見: `https://mirrors-obs-1.lolinet.com/firmware/lenowow/2020/docomo/D-42A/`
  - 最新 `d-42A_S_S203037_2212092223_JP.zip` (2,287,941,964 B) を `work/orig/` に保存（約 4.3MB/s）
- Lenovo OSS ポータル `opensource.lenovo.com` → NXDOMAIN（8.8.8.8 でも NXDOMAIN）
- `https://support.lenovo.com/us/en/solutions/HT511330`（Lenovo Open Source Portal）
  - r.jina.ai 経由で取得。dtab / d-42A のソースは一覧に無し
- 製品ページ発見: `d-42A (ELF-8605L)` Type ZA7N
  - `pcsupport.lenovo.com/us/en/products/tablets/a-series/d-42a-elf-8605l/za7n/downloads` に OSS 項目なし
- GitHub `toromame8373/d-42A_kernel` → size 0（空）

### fastboot（重要な設定変更）
- `adb reboot bootloader` 後、Windows で `Android` デバイスが **Error（ドライバ無し, VID_18D1 PID_D00D）**
- Google USB Driver r13 を `work/tools/usb_driver` に展開 → 公式 INF に D00D の定義が無く失敗
- INF を複製し `USB\VID_18D1&PID_D00D` と `USB\Class_FF&SubClass_42&Prot_03` を追記
  （`work/tools/usb_driver_custom/android_winusb.inf`）
- `pnputil /add-driver ... /install`（UAC 昇格）→ oem5.inf として登録、デバイスは
  `Android Bootloader Interface` として正常化
- `fastboot devices` → `HA18JVX3 fastboot` / `unlocked:yes`
- `fastboot fetch boot` → 非対応（"Device does not support fetch command"）
- パーティション一覧を `work/notes/partitions.txt` に保存（168 行）
  - boot=sde11(0x4000000), bootbak=sde30, recovery(0x6000000), dtbo, vbmeta, super(6GB), userdata(f2fs)
- `fastboot reboot recovery` → recovery 起動。**adb は unauthorized**（sideload も不可）
  → fastboot からも制御できず、現在ここで停止（電源長押し待ち）

### ファームウェア解析
- zip 内 76 entries。boot.img / recovery.img / dtbo.img / vbmeta / super_1..4 / NON-HLOS.bin /
  prog_firehose_ddr.elf / prog_firehose_lite.elf / rawprogram*.xml / patch*.xml / gpt_* を抽出
  （`work/orig/fw/`）
- boot.img: header v2, page 4096, kernel 14,887,248 (gzip), ramdisk 709,145 (gzip),
  dtb 515,277 (DTB 9個連結, 8番目 trinket SoC)
- kernel から IKCONFIG 抽出 → `work/boot/config.txt`（KPROBES 無効, MODVERSIONS 有効,
  STATIC_USERMODEHELPER 有効, LOCALVERSION=-perf）
- dtbo overlay のパネル: td4330_truly / hx83112a_truly / nt36672_truly / hx82790_boe_fhd（Qualcomm QRD 系）

### 未解決
- d-42A 純正カーネルソースの入手経路
- 端末が recovery で停止中（要・物理電源操作）

### 02:10 追記
- `work/tools/bootimg.py` 作成、純正 boot.img で unpack→repack の完全一致を確認
- boot.img 末尾の AVB footer / 埋め込み vbmeta (0xF60000, 0x380) を確認
- Magisk v31.1 / KernelSU-Next v3.4.2 manager / Zygisk Next 1.5.3 / Zygisk Assistant 2.1.4 を取得
- KernelSU-Next legacy の non-GKI 手順を notes/ksun_legacy.md に保存

### 02:20-02:30 GitHub
- `git init` → commit（scaffold / docs）
- GitHub device flow で認証（gh CLI の公開 client_id 使用、token はローカル保存・非表示）
- `POST /user/repos` で `mizutama1/d42a-kernel` (public) を作成
- `git push` 成功（15.00 MiB pack、stock_boot.img 64MB は 50MB 超警告のみ）
- Actions workflow `build-kernel` が active で登録されたことを API で確認
