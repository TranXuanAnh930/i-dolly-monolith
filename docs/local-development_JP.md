# ローカルでの実行

[← README に戻る](../README_JP.md)

2 つのアプリは独立して動作します — このレベルには共有の docker-compose はなく、各サブモジュールが
それぞれ独自のものを持っています。

## 前提条件

- Docker Desktop（バックエンドの Postgres、Redis、API、Celery ワーカー用）
- Node.js と npm（フロントエンド用）
- Python 3.12（Docker の外でバックエンドのユニットテストや ruff を実行する場合のみ）

## 1. バックエンド

```bash
cd i-dolly-backend
cp .env.example .env
docker compose up --build
```

初回起動の前に `.env` を編集します:

| 設定 | 設定する値 |
|---|---|
| `JWT_SECRET_KEY`、`JWT_REFRESH_SECRET_KEY`、`JWT_EMAIL_SECRET_KEY` | それぞれ異なる 3 つのランダム値: `python -c "import secrets; print(secrets.token_hex(32))"` |
| `DATABASE_URL`、`DATABASE_NAME`、`DATABASE_USER`、`DATABASE_PWD` | 互いに一致する値。`DATABASE_URL` のホストは `postgres`（compose のサービス名）のまま |
| `DEBUG` | `true` にすると、メール（認証リンクやリセットリンクを含む）を Resend で送信せずコンソールに出力します。デフォルトは `false` です。 |
| `RESEND_API_KEY`、`FROM_EMAIL` | `DEBUG=true` の場合は任意のプレースホルダー。実際に送信する場合は本物のキーと認証済みドメインのアドレス |
| `PAYPAL_*` | 任意。空のままにしてモックゲートウェイを使うか、PayPal サンドボックスの認証情報を追加 |

`docker compose up` は 4 つのコンテナを起動し、起動時にデータベースのマイグレーションを実行します:

| サービス | コンテナ | ローカルマシンのポート |
|---|---|---|
| `app`（FastAPI） | `i-dolly-backend` | `8000` — API ドキュメントは `http://localhost:8000/docs` |
| `worker`（Celery） | `i-dolly-worker` | —（抽選処理とメール送信を実行） |
| `postgres` | `postgres_latest` | `5433` |
| `redis` | `redis` | `6379` |

必要に応じてサンプルデータを投入できます — 会社、グループ、アイドル、会場、公演、商品、および各ロールの
アカウント。冪等に実行できます:

```bash
docker compose exec app python scripts/seed.py
```

投入されるログインには `admin@example.com`、`manager.nova@example.com`、`alex.fan@example.com` が
含まれます。パスワードはすべて共通で、環境変数の `SEED_PASSWORD`、または `scripts/seed.py` の
デフォルト値です。

### テストとリント

ユニットテストはモックとインメモリのフェイク Redis を使うため、Docker の外で実行できます:

```bash
pip install -r requirements-dev.txt
python -m pytest tests/unit
ruff check .
```

統合テストは実際の Postgres と Redis を使うため、`app` コンテナ内で実行します。テストは最初に別の
`<database>_test` データベースを作成・マイグレーションするため、開発用のデータには影響しません:

```bash
docker compose exec app python -m pytest tests/integration
```

統合テスト全体には数分かかります。一部だけを実行するにはフォルダやファイルを指定してください
（例: `tests/integration/events`）。

## 2. フロントエンド

```bash
cd i-dolly-frontend
npm install
npm run dev
```

Vite の開発サーバーが `http://localhost:8080` で起動します。バックエンドの接続先は
[`src/env.js`](https://github.com/TranXuanAnh930/i-dolly-frontend/blob/main/src/env.js) で決まり、
`VITE_API_URL` を読み取り、未設定の場合は `http://localhost:8000` にフォールバックします — 上記の
バックエンドのデフォルトと一致するため、ローカルで起動したバックエンドに対して開発する場合は設定変更は
不要です。バックエンドのデフォルトの `CORS_ORIGINS` はすでに `http://localhost:8080` を許可しています。

購入手続きでは、支払いを即座に承認または拒否するには **mock** ゲートウェイを、バックエンドに
サンドボックスの認証情報がある場合は **PayPal** を選択します。

それぞれの詳細な手順（環境変数、テスト、リント）は、各リポジトリの README を参照してください:
[バックエンド](https://github.com/TranXuanAnh930/i-dolly-backend#readme)、
[フロントエンド](https://github.com/TranXuanAnh930/i-dolly-frontend#readme)。
