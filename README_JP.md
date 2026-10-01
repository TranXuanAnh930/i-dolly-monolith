# i-dolly-monolith

[English](README.md) | 日本語

**I-Dolly** のアンブレラリポジトリです — **アルバム／シングルのマーケットプレイス** を備えたアイドル公演の
**チケット予約** プラットフォームで、フルスタックのエンジニアリングを示すためのプロジェクトとして
構築しました: バックエンドのスキーマ設計／レイヤードアーキテクチャ／マイグレーションの規律／RBAC、
そしてそれを利用する Vue 3 SPA です。バックエンドとフロントエンドは別々に独立して開発されている
リポジトリで、ここでは git サブモジュールとして組み込まれています — それぞれが独自の README、ドキュメント、
CI、デプロイ先を持っています。このファイルはレビュアーが最初に訪れる場所を 1 つ提供するためのもので、
どちらかにすでに記載されている内容を重複させるためのものではありません。

**本番システムではありません。** 両サブモジュールとも、未完成の部分をそれぞれのドキュメントで明記して
います — 機能が完成していると判断する前に、それぞれの「Known limitations」／「Project status」セクションを
確認してください。


**🚀 ライブデモ**

注意: Render の無料および下位プランのインスタンスは 15 分間操作がないとスピンダウンするため、最初の
リクエストでは約 30〜50 秒（場合によっては最大 1 分）のコールドスタートの読み込み時間が発生します。
そのため、初めてサイトにアクセスする際は 50 秒ほどかかることがあります。

**フロントエンド:** https://i-dolly-app.site

**API:** https://api.i-dolly-app.site

**API ドキュメント:** https://api.i-dolly-app.site/docs

<img width="1919" height="1030" alt="image" src="https://github.com/user-attachments/assets/8480700a-cecc-4360-865b-7f151fd360ec" />


<img width="1918" height="1013" alt="image" src="https://github.com/user-attachments/assets/a4502c75-a702-4325-9dec-034a520b6772" />

---

## 目次

| ドキュメント | 内容 |
|---|---|
| [概要](docs/overview_JP.md) | ドメインとそのテーブル、ロール、機能、バージョン付きの技術スタック |
| [アーキテクチャとデータフロー](docs/architecture_JP.md) | システム構成図、バックエンドのレイヤー構造、キャッシュ付きの読み取り、モックおよび PayPal での購入、抽選処理 |
| [ビジネスロジック](docs/business-logic_JP.md) | すべてのルールとデータベーストリガーによる保険の有無、抽選アルゴリズム、ステータスのライフサイクル |
| [ユースケースフロー](docs/use-case-flows_JP.md) | エンドポイントごとの 6 つの流れ: パスワードリセット、購入手続き、抽選、一般販売チケット、公演の準備、発送 |
| [エンジニアリング上の判断](docs/engineering-decisions_JP.md) | 理由: 行ロックと共有ロック、トリガーによる保険、同期ハンドラー、レート制限、Webhook、キャッシュ、通知、論理削除 |
| [ローカルでの実行](docs/local-development_JP.md) | 両アプリを 1 コマンドで起動する Docker 構成、`.env` の要点、ポート、シードデータ、テストの実行 |
| [デプロイ](docs/deployment_JP.md) | 各コンポーネントの配置、DNS レコード、サービス間の設定、CI/CD |
| [現状とロードマップ](docs/status-and-roadmap_JP.md) | 既知の制限事項、テスト方法、未解決の課題、今後の取り組み |

## 構成

これはサブモジュールベースのモノレポであり、共有コードベースではありません — バックエンドと
フロントエンドは互いにインポートすることはなく、HTTP でのみ通信します:

- [`i-dolly-backend/`](https://github.com/TranXuanAnh930/i-dolly-backend) — FastAPI + PostgreSQL +
  Redis + Celery の API
- [`i-dolly-frontend/`](https://github.com/TranXuanAnh930/i-dolly-frontend) — Vue 3 + Vite + Pinia
  の SPA

### クローン

```bash
git clone --recurse-submodules https://github.com/TranXuanAnh930/i-dolly-monolith.git
```

`--recurse-submodules` を付けずにクローンした場合:

```bash
git submodule update --init --recursive
```

各サブモジュールはそれぞれのリポジトリの特定のコミットに固定されています — そのサブモジュール自身の
`main` から最新を取得するには `git submodule update --remote` を実行します（サブモジュール内で、または
トップレベルで `--remote` を付けて）。

### Docker ですべてを起動する

```bash
cp i-dolly-backend/.env.example i-dolly-backend/.env   # その後シークレットを設定
docker compose up --build
```

フロントエンドは `http://localhost:8080`、API ドキュメントは `http://localhost:8000/docs` です。
`.env` の設定、シードデータ、テストについては [ローカルでの実行](docs/local-development_JP.md) を参照してください。

## サブモジュールのドキュメント

各サブモジュールが自身のドキュメントを管理しており、ここでは何も重複させていません — 最新に保たれて
いるのはそのコピーだけなので、ミラーではなくサブモジュール側のドキュメントを読んでください:

| リポジトリ | ドキュメント |
|---|---|
| バックエンド | [`database-design.md`](https://github.com/TranXuanAnh930/i-dolly-backend/blob/main/docs/database-design.md)（スキーマ／ER 図／RBAC／抽選ロジック）、[`architecture.md`](https://github.com/TranXuanAnh930/i-dolly-backend/blob/main/docs/architecture.md)（コードのレイヤー構造／規約）、[`project_status.md`](https://github.com/TranXuanAnh930/i-dolly-backend/blob/main/docs/project_status.md)（実装済みと未対応、既知の問題）、[`api-spec.md`](https://github.com/TranXuanAnh930/i-dolly-backend/blob/main/docs/api-spec.md)（全ルート）、[`deployment.md`](https://github.com/TranXuanAnh930/i-dolly-backend/blob/main/docs/deployment.md) |
| フロントエンド | [`architecture.md`](https://github.com/TranXuanAnh930/i-dolly-frontend/blob/main/docs/architecture.md)、[`business_logic.md`](https://github.com/TranXuanAnh930/i-dolly-frontend/blob/main/docs/business_logic.md) |

## ライセンス

プロプライエタリ — 両サブモジュールと同様に、すべての権利を留保します。
