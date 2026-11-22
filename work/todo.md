# TODO

凡例: [ ] 未着手 / [~] 作業中 / [x] 完了 / [!] ブロック

## 調査（完了分）
- [x] 実機情報の取得（model, SoC, kernel, bootloader 状態）
- [x] KernelSU の非 GKI (4.14) 対応状況 → KernelSU-Next `legacy` ブランチ
- [x] 純正ファームウェア入手（lolinet ミラー、最新 S203037）
- [x] boot.img / dtbo / config の抽出・解析
- [x] Lenovo OSS ポータル調査 → d-42A のソース公開なし（現時点）
- [x] fastboot ドライバ問題の解決（18D1:D00D 用に INF 改変してインストール）

## 端末復旧
- [!] recovery から通常起動へ戻す（電源長押しが必要・ユーザー操作待ち）
- [ ] 起動後に `adb shell` 復帰確認

## 情報収集（起動後）
- [ ] /proc/config.gz と boot/config.txt の一致確認
- [ ] /vendor/lib/modules の一覧（.ko 依存の確認）
- [ ] /proc/device-tree/compatible, ro.boot.* の再確認
- [ ] vendor_boot 有無・super パーティション構成の確認

## root 化（段階的）
- [ ] Magisk で boot.img をパッチ → `fastboot boot` で試験 → flash（安全策）
- [ ] 起動確認後、パーティションのフルバックアップ（必要に応じ EDL/firehose 使用）

## KernelSU
- [ ] ソース方針決定（純正ソースが無い場合: CAF/LineageOS trinket 4.14 + 純正 config/DTB）
- [ ] KernelSU-Next legacy の組み込み手順確定（kprobe 有効化 or manual hook）
- [ ] CONFIG_KPROBES 等のビルド時追加と STATIC_USERMODEHELPER の扱い整理
- [ ] GitHub Actions ワークフロー作成（.github/workflows/build-kernel.yml）
- [ ] ビルド成果 boot.img を `fastboot boot` で非破壊検証
- [ ] 成功したら flash、KernelSU マネージャで root 確認

## 隠蔽
- [ ] Zygisk Next + Shamiko / Zygisk Assistant の導入
- [ ] root 検出アプリでの検証

## ドキュメント
- [ ] work/log.md / state.md の更新を継続
