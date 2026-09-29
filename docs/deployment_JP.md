# デプロイ

[← README に戻る](../README.md)

手順ごとのセットアップ、環境変数の一覧、デプロイ後の確認事項はバックエンドの
[`deployment.md`](https://github.com/TranXuanAnh930/i-dolly-backend/blob/main/docs/deployment.md)
にあります。このページはその全体像を示すものです。

## 各コンポーネントの配置

| コンポーネント | プラットフォーム | アドレス / プラン |
|---|---|---|
| フロントエンド（Vue SPA） | Vercel | `https://i-dolly-app.site`（`www.` はここにリダイレクト） |
| API（FastAPI） | Render Web サービス、Docker | `https://api.i-dolly-app.site`（ドキュメントは `/docs`）· 無料プラン |
| Celery ワーカー | Render バックグラウンドワーカー、同じ Docker イメージ | Starter プラン（Render には無料のワーカーがない） |
| Redis | Render Key Value | 無料プラン · キャッシュ、レート制限、Celery ブローカー |
| PostgreSQL | Supabase | セッションプーラー接続 |
| 画像 | S3 互換バケット | `STORAGE_BACKEND=s3` |
| メール | Resend | `mail.i-dolly-app.site` から送信 |
| DNS とドメイン | Cloudflare Registrar と DNS | `i-dolly-app.site` |
| 決済 | PayPal | サンドボックスモード |

- **バックエンド**: Docker イメージは uvicorn の起動前に `alembic upgrade head` を実行するため、
  デプロイのたびに未適用のマイグレーションが先に適用されます。ワーカーは同じイメージを Celery コマンドで
  実行し、API と同じデータベース、Redis、メールの設定が必要です。
  `i-dolly-backend/docs/deployment.md` を参照してください。
- **フロントエンド**: Vercel — `vercel.json` はクライアントサイドルーティングのためにすべてのルートを
  `index.html` にリライトします。デプロイ先の API URL はビルド時に `VITE_API_URL` で渡されるため、
  変更するには再デプロイが必要です。
- **ドメイン**: `i-dolly-app.site`（Cloudflare Registrar/DNS）。フロントエンドは `i-dolly-app.site`、
  API は `api.i-dolly-app.site` で提供され、どちらも Vercel と Render を指す DNS only の Cloudflare
  レコードを経由します。API を同じサイトのサブドメインに置くことで、ログイン用のリフレッシュ Cookie が
  ファーストパーティになります。セットアップ、環境変数、確認事項:
  [`deployment.md` §12](https://github.com/TranXuanAnh930/i-dolly-backend/blob/main/docs/deployment.md)。
- **メール**: Resend を使用し、Resend のサンドボックス送信元ではなく認証済みドメイン
  （`mail.i-dolly-app.site`、Cloudflare Registrar/DNS 上 — DKIM、SPF 関連の CNAME、DMARC）から送信する
  ため、認証／リセットメールはアカウント所有者だけでなく任意の宛先に届きます。

## DNS レコード

Web 用のレコードはすべて **DNS only**（グレーの雲）です: Vercel と Render がそれぞれ独自に証明書を発行します。

| 名前 | タイプ | 向き先 |
|---|---|---|
| `i-dolly-app.site` | A | Vercel |
| `www` | CNAME | Vercel（apex にリダイレクト） |
| `api` | CNAME | `i-dolly-backend.onrender.com` |
| `mail` サブドメインのレコード | TXT / CNAME | Resend（DKIM、SPF、DMARC） |

## 各コンポーネントをつなぐ設定

| 場所 | 設定 | 値 |
|---|---|---|
| Render（API + ワーカー） | `BASE_URL` | `https://api.i-dolly-app.site` — メール認証リンクで使用 |
| Render（API + ワーカー） | `FRONTEND_BASE_URL` | `https://i-dolly-app.site` — リセットリンクと PayPal の戻り／キャンセル URL で使用 |
| Render（API + ワーカー） | `CORS_ORIGINS` | apex、`www`、および旧 `vercel.app` アドレス |
| Render（API + ワーカー） | `FROM_EMAIL` | `noreply@mail.i-dolly-app.site` |
| Render（API + ワーカー） | `DEBUG` | 未設定または `false`（メールをログに出力せず実際に送信するため） |
| Vercel | `VITE_API_URL` | `https://api.i-dolly-app.site` |
| PayPal ダッシュボード | Webhook URL | API の `/payment/paypal/webhook`。その ID を `PAYPAL_WEBHOOK_ID` に設定 |

## CI/CD

- **バックエンド:** GitHub Actions が `main` への push とプルリクエストで `ruff` と pytest の全テスト
  （Postgres と Redis のサービスコンテナを使用し、カバレッジを Codecov にアップロード）を実行します。
  `main` で両方が通った後、`RENDER_DEPLOY_HOOK` シークレットが設定されていれば Render のデプロイフックを
  呼び出します。Render も `main` へのコミットごとに再デプロイするよう設定されています。
- **フロントエンド:** 独自の CI ワークフローはなく、Vercel が Git 連携を通じてビルドとデプロイを行います。

## 注意事項

- Render の無料 Web サービスはトラフィックがない状態が 15 分続くとスリープするため、その後の最初の
  リクエストには 30〜60 秒かかることがあります。
- プラットフォームのアドレス（`i-dolly-frontend.vercel.app`、`i-dolly-backend.onrender.com`）は
  カスタムドメインと並行して引き続き利用できます。
