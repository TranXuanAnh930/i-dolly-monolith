# アーキテクチャとデータフロー

[← README に戻る](../README_JP.md)

## システム構成

```
                      Cloudflare DNS (i-dolly-app.site)
                 ┌────────────────┴────────────────┐
                 ▼                                 ▼
   i-dolly-app.site (Vercel)          api.i-dolly-app.site (Render)
 ┌──────────────────────────┐        ┌───────────────────────────┐
 │ Frontend                 │  HTTPS │ Backend API               │
 │ Vue 3 + Vite + Pinia     │ ─────▶ │ FastAPI (Python 3.12)     │
 │ (i-dolly-frontend)       │  JSON  │ (i-dolly-backend)         │
 └──────────────────────────┘        └──────┬──────────┬─────────┘
                                            │          │
                                            ▼          ▼
                                ┌──────────────┐  ┌─────────────────────┐
                                │ PostgreSQL   │  │ Redis               │
                                │ (Supabase)   │  │ cache · rate limits │
                                └──────▲───────┘  │ Celery broker       │
                                       │          └──────────┬──────────┘
                                       │                     ▼
                                       │            ┌─────────────────┐
                                       └────────────│ Celery worker   │
                                                    │ lottery draw ·  │
                                                    │ email sending   │
                                                    └─────────────────┘

  外部サービス: PayPal（サンドボックス決済 + Webhook）· Resend（mail.i-dolly-app.site からのメール送信）
              · S3 互換ストレージ（アイドル／商品画像）
```

フロントエンドとバックエンドは別々にデプロイされ、HTTP のみで通信します。API はフロントエンドの
ドメインのサブドメイン上にあるため、リフレッシュトークンの Cookie は Safari や Firefox がブロックする
サードパーティ Cookie ではなく、ファーストパーティ Cookie として扱われます。

## バックエンドの内部構造

すべての機能は、ドメインパッケージ（`identity/`、`talent/`、`events/`、`marketplace/`、および
`shared/`）の中で同じ 3 層構造に従います。

| レイヤー | 場所 | 責務 |
|---|---|---|
| Router | `app/router/<domain>/` | ルートとその依存関係（DB セッション、現在のユーザー、レート制限）およびレスポンスモデルを宣言し、サービスメソッドを 1 つ呼び出し、`ServiceError` を対応する HTTP ステータスに変換する |
| Service | `app/services/<domain>/` | ビジネスルール、会社スコープ、行ロック、トランザクションを扱い、`NotFoundError` / `ForbiddenError` / `BadRequestError` を送出する |
| Model / schema | `app/db/models/`、`app/schema/` | SQLAlchemy のテーブル定義と Pydantic のリクエスト／レスポンスモデル（レスポンスは常に ORM モデルとは別クラス） |

横断的な仕組み:

- **ルートハンドラーは通常の `def`。** SQLAlchemy、bcrypt、PayPal、boto3 の呼び出しはすべて
  同期処理なので、FastAPI は各ハンドラーをイベントループではなくスレッドプール上で実行します。
  本当に非同期なのは PayPal Webhook の生ボディを読み取る処理だけで、これは非同期の依存関係として実装しています。
- **エラーの経路は 2 つ、ルーターのパターンは 1 つ。** サービスのルール違反は `ServiceError` の
  サブクラスを送出します。データベーストリガーによる拒否は `commit_or_raise()` / `flush_or_raise()` が
  `TriggerViolationError` のサブクラスに変換します。どちらも自身の HTTP ステータスコードを持ちます。
- **キャッシュは 2 つに分割。** `app/cache/invalidation.py` はキャッシュキーと `delete_cached_*`
  メソッドを持ち、Redis にのみ依存するため、サービスは自身の処理の中でキャッシュを無効化できます。
  `CacheService`（サービスを呼び出すリードスルーの `get_cached_*` メソッド）はこれを継承し、
  ルーターからのみ使用されます。これによりインポートの方向が一方向に保たれます。
- **バックグラウンド処理は Celery 経由:** 抽選処理とすべてのトランザクションメール。

<a id="data-flow"></a>
## データフロー

**キャッシュ付き・レート制限付きの読み取り**（例: `GET /products/store-page`）:

```
Frontend → FastAPI router
             │
             ├─ rate_limit() 依存関係: ルート + 識別子のキーに対して Redis INCR（キー作成時に
             │  有効期限を設定）、上限超過で 429、Redis 自体がエラーの場合はフェイルオープン
             │
             ├─ キャッシュヒット → キャッシュされたペイロードを msgpack デコードして返す — DB クエリは一切なし
             │
             └─ キャッシュミス → サービスがレスポンスを構築し、実際のレスポンススキーマで検証、
                msgpack エンコード + 5 分の TTL で SETEX して返す
```

書き込み処理はコミット直後に影響するキーを無効化するため、TTL は鮮度を保つ仕組みではなく
あくまで保険です。

**モックゲートウェイでの一般販売チケット購入**（`POST /tickets/checkout`、ユーザーごとに 60 秒あたり
3 リクエスト）:

1. ファン以外、再利用された冪等性キー、販売期間中でないティア、売り切れのティア、その公演の有効な
   チケットをすでに持っているファン、その公演の抽選エントリーが未確定のファンを拒否します。
2. `ticket_types` の行をロックし（`SELECT … FOR UPDATE`）、金額（価格 + 10 % の税）を確認して、
   チケットと支払いを作成します。
3. 支払いが成功した場合、`sold_quantity` をインクリメントし、`ticket_confirmation` 通知を追加します —
   すべて 1 回のコミットで行います。
4. コミット後: キャッシュされた公演詳細を無効化し、確認メールをキューに入れます。

**PayPal でのチケット購入** — ロック、Webhook、キャッシュ無効化がすべて関わるフロー:

1. `POST /tickets/checkout` が `pending_payment` のチケットと `pending` の支払いを作成し、PayPal に
   注文の作成を依頼してコミットします。この時点では座席はまだカウントされません。
2. フロントエンドはファンを PayPal の承認ページにリダイレクトし、PayPal はファンを
   `https://i-dolly-app.site/payment/paypal/return` に戻します。
3. フロントエンドが `POST /payment/paypal/capture/{pg_order_id}` を呼び出します。PayPal も同じ支払いに
   対して `POST /payment/paypal/webhook`（署名検証済み）を呼び出すことがあります。どちらも
   `finalize_paypal_payment()` を通ります。
4. この関数は支払い、チケット、チケット種別の行をロックし、支払いがまだ `pending` でなければ
   即座に戻ります — このチェックが冪等性ガードです。残り在庫を再確認し、PayPal で支払いをキャプチャ
   した後、支払いを `success`（返金の際に使う PayPal のキャプチャ ID を保存）、チケットを `paid` にし、
   `sold_quantity` をインクリメントするまでを 1 回のコミットで行います。2 番目の呼び出し元は
   pending でない支払いを見つけ、何もしません。

このフローの既知の課題: PayPal のキャプチャ呼び出しが行ロックを保持したまま実行されること、
また PayPal 側ではキャプチャが成功したがこちら側でコミットに失敗した場合に照合されないこと
（バックエンド `docs/bugs.md` #8）。放棄された PayPal 決済ではチケットが有効期限なしで
`pending_payment` のまま残ります（#12、#27）。

**抽選処理**（`PUT /concerts/lottery-draw/{id}`）: ルーターはマネージャーの所属会社を確認し、
その会社のマネージャーに抽選開始を通知して、`app.tasks.lottery.draw_lottery` をキューに入れます。
ワーカーは公演のチケット種別、受付中のキャンペーン、未確定のエントリーをロックし、
ランクのカスケード処理を実行します（[ビジネスロジック](business-logic_JP.md#lottery)を参照）。
各当選者に支払期限付きの `pending_payment` チケットを作成し、それ以外のエントリーをすべて `lost`、
キャンペーンを `drawn` にして、1 回だけコミットします。その後、完了または失敗をマネージャーに通知します。
シーケンス図の全体:
[`database-design.md` §5.2](https://github.com/TranXuanAnh930/i-dolly-backend/blob/main/docs/database-design.md)。
