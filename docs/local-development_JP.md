# ローカルでの実行

[← README に戻る](../README_JP.md)

リポジトリのルートで `docker compose up` を 1 回実行するだけで、スタック全体が起動します: バックエンド
（API、Celery ワーカー、Postgres、Redis）と、Vite でビルドし nginx で配信するフロントエンドです。ルートの
[`docker-compose.yaml`](../docker-compose.yaml) は各サブモジュール自身の compose ファイルを取り込むだけなので、
すべてのサービス定義はそれぞれ 1 か所だけにあります。

各アプリを個別に実行することもできます。[各アプリを個別に実行する](#各アプリを個別に実行する)を
参照してください。

## 前提条件

- サブモジュールのチェックアウト: `git submodule update --init --recursive`
- Docker Desktop、または Compose v2.20 以降の Docker Engine（ルートの compose ファイルは `include` を使用）
- Node.js 22 以降と npm（フロントエンドを Docker の外で実行する場合のみ。ホットリロードやテストなど）
- Python 3.12（Docker の外でバックエンドのユニットテストや ruff を実行する場合のみ）

## 1. バックエンドの設定

```bash
cp i-dolly-backend/.env.example i-dolly-backend/.env
```

初回起動の前に `i-dolly-backend/.env` を編集します。ルートの compose ファイルもこのファイルを読み込むため、
ルートに別の `.env` は必要ありません。

| 設定 | 設定する値 |
|---|---|
| `JWT_SECRET_KEY`、`JWT_REFRESH_SECRET_KEY`、`JWT_EMAIL_SECRET_KEY` | それぞれ異なる 3 つのランダム値: `python -c "import secrets; print(secrets.token_hex(32))"` |
| `DATABASE_URL`、`DATABASE_NAME`、`DATABASE_USER`、`DATABASE_PWD` | 互いに一致する値。`DATABASE_URL` のホストは `postgres`（compose のサービス名）のまま |
| `DEBUG` | `true` にすると、メール（認証リンクやリセットリンクを含む）を Resend で送信せずコンソールに出力します。お問い合わせページの質問も Claude に送信せず出力します。デフォルトは `false` です。 |
| `RESEND_API_KEY`、`FROM_EMAIL` | `DEBUG=true` の場合は任意のプレースホルダー。実際に送信する場合は本物のキーと認証済みドメインのアドレス |
| `PAYPAL_*` | 任意。空のままにしてモックゲートウェイを使うか、PayPal サンドボックスの認証情報を追加 |
| `ANTHROPIC_API_KEY` | 任意。未設定にするとお問い合わせページの即時回答が無効になります。有効にするには Claude Console で取得した Claude API キーを追加します。キーがあり `DEBUG=false` の場合、質問ごとに実際の課金される呼び出しになります（Haiku 4.5 で 1 セント未満） |

## 2. すべてを起動する

リポジトリのルートで:

```bash
docker compose up --build
```

5 つのコンテナが起動し、起動時にデータベースのマイグレーションが実行されます:

| サービス | コンテナ | ローカルマシンのポート |
|---|---|---|
| `frontend`（nginx） | `i-dolly-monolith-frontend-1` | `8080` — `http://localhost:8080` を開く |
| `app`（FastAPI） | `i-dolly-backend` | `8000` — API ドキュメントは `http://localhost:8000/docs` |
| `worker`（Celery） | `i-dolly-worker` | —（抽選処理とメール送信を実行） |
| `postgres` | `postgres_latest` | `5433` |
| `redis` | `redis` | `6379` |

バックエンドのソースはバインドマウントされているため、編集するたびに uvicorn が API を再起動します。
`requirements.txt` を変更した場合は再ビルド（`--build`）してください。フロントエンドのコンテナは本番ビルドを
配信するため、フロントエンドの編集にも再ビルドが必要です。フロントエンドをホットリロードしながら開発するには、
このスタックと並行して[フロントエンドを個別に実行](#フロントエンド)してください（どちらもポート `8080` を
使うため、先に `docker compose stop frontend` で `frontend` サービスを停止します）。

API を呼び出すのはコンテナではなくブラウザなので、フロントエンドのバンドルは API の公開ポートである
`http://localhost:8000` を呼び出します。この URL は Vite がビルド時に埋め込みます。別のバックエンドを
指すには、値を設定して再ビルドします（例: `VITE_API_URL=https://api.example.com docker compose up --build`）。
バックエンドのデフォルトの `CORS_ORIGINS` はすでに `http://localhost:8080` を許可しています。

停止するには `docker compose down` を実行します。`-v` を付けると Postgres のデータボリュームも削除されます。

バックエンドのコンテナ名は固定のため、このスタックを起動する前に `i-dolly-backend/` から起動したスタックを
停止してください（逆の場合も同様です）。

### シードデータ

必要に応じてサンプルデータを投入できます — 会社、グループ、アイドル、会場、公演、商品、および各ロールの
アカウント。冪等に実行できます:

```bash
docker compose exec app python scripts/seed.py
```

投入されるログインには `admin@example.com`、`manager.nova@example.com`、`alex.fan@example.com` が
含まれます。パスワードはすべて共通で、環境変数の `SEED_PASSWORD`、または `scripts/seed.py` の
デフォルト値です。

購入手続きでは、支払いを即座に承認または拒否するには **mock** ゲートウェイを、バックエンドに
サンドボックスの認証情報がある場合は **PayPal** を選択します。

### テストとリント

統合テストは実際の Postgres と Redis を使うため、`app` コンテナ内で実行します。テストは最初に別の
`<database>_test` データベースを作成・マイグレーションするため、開発用のデータには影響しません:

```bash
docker compose exec app python -m pytest tests/integration
```

統合テスト全体には数分かかります。一部だけを実行するにはフォルダやファイルを指定してください
（例: `tests/integration/events`）。

バックエンドのユニットテストはモックとインメモリのフェイク Redis を使うため、Docker の外で実行できます:

```bash
cd i-dolly-backend
pip install -r requirements-dev.txt
python -m pytest tests/unit
ruff check .
```

フロントエンドのイメージにはビルド済みファイルしか含まれないため、テストとリントは Docker の外で実行します:

```bash
cd i-dolly-frontend
npm ci
npm test
npm run lint
```

## 各アプリを個別に実行する

### バックエンド

バックエンドのサブモジュールには、同じ 4 つのバックエンドサービスを持つ独自の compose ファイルがあります:

```bash
cd i-dolly-backend
docker compose up --build
```

上記のコマンドはこのディレクトリからも同じように動作します。

### フロントエンド

```bash
cd i-dolly-frontend
npm install
npm run dev
```

Vite の開発サーバーが `http://localhost:8080` で起動します。バックエンドの接続先は
[`src/env.js`](https://github.com/TranXuanAnh930/i-dolly-frontend/blob/main/src/env.js) で決まり、
`VITE_API_URL` を読み取り、未設定の場合は `http://localhost:8000`（バックエンドのポート）に
フォールバックします。そのため、ローカルで起動したバックエンドに対して開発する場合は設定変更は不要です。

フロントエンドのサブモジュールにも独自の `docker compose up --build` と `Makefile`（`make` でターゲット一覧を
表示）があります。

それぞれの詳細な手順（環境変数、テスト、リント）は、各リポジトリの README を参照してください:
[バックエンド](https://github.com/TranXuanAnh930/i-dolly-backend#readme)、
[フロントエンド](https://github.com/TranXuanAnh930/i-dolly-frontend#readme)。
