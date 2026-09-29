# 概要

[← README に戻る](../README.md)

## このプロジェクトについて

アイドル／グループ、会場／公演、抽選および一般販売によるチケット販売、そしてアルバム／グッズの
マーケットプレイスを提供します — フォークした EC ボイラープレートのカート／注文／支払い／配送の仕組みを
再利用しています。ロールベースのアクセス制御（`admin`/`manager`/`fan`、会社単位のマネージャー）、
アプリ内通知（注文／チケット／抽選の確認、抽選結果、マネージャー向けの抽選処理状況、パスワード
リセット）、マネージャーが実行し Celery のバックグラウンドジョブとして動く抽選処理とその結果画面、
そしてローカル開発用のモック決済ゲートウェイと並ぶ PayPal 決済を備えています。最新かつ正確な範囲の
機能一覧: [`i-dolly-backend/README.md`](https://github.com/TranXuanAnh930/i-dolly-backend#readme)。

## ドメイン

バックエンドは 4 つのドメインパッケージと 1 つの共有パッケージに分かれており、すべてのレイヤー
（ルーター、サービス、モデル、スキーマ）が同じ分割に従います。

| ドメイン | テーブル | 対象範囲 |
|---|---|---|
| **Identity** | `users`、`refresh_tokens` | 登録、ログイン、JWT アクセストークン + ローテーションするリフレッシュトークン、メール認証、パスワードリセット、ロール |
| **Talent** | `management_companies`、`groups`、`idols`、`idol_colors`、`positions`、`idol_positions` | 事務所とそのアーティスト。公演や商品の履歴が残るよう、グループとアイドルは論理削除（`is_active`） |
| **Events & ticketing** | `venues`、`concerts`、`concert_performers`、`ticket_types`、`direct_sale_campaigns`、`lottery_campaigns`、`lottery_preferences`、`lottery_entries`、`tickets` | キャパシティに基づくチケットティアを持つ公演。一般販売（販売期間内）または抽選で販売 |
| **Marketplace** | `products`、`categories`、`album_details`、`merch_details`、`genres`、`album_genres`、`cart`、`orders`、`orders_items`、`payment`、`shipping_addresses`、`shipping_status` | アルバム／シングル／EP と公式グッズ: カート → 購入手続き → 支払い → 配送 |
| **Shared** | `notifications` | ファンとマネージャー向けのアプリ内通知 |

合計 30 テーブルで、1 本の直線的な Alembic マイグレーションチェーンで構築されています。

## ロール

| ロール | できること |
|---|---|
| **fan** | すべてを閲覧。抽選ティアの順位付けと応募。一般販売チケットの購入と抽選当選分の支払い。カートと購入手続き。自分の注文、チケット、通知の閲覧 |
| **manager** | 1 つの事務所に所属。その会社のグループ、アイドル、公演、チケット種別、キャンペーン、商品の作成と編集。抽選の実行と結果の閲覧。会社の注文の閲覧と発送済みへの変更。チケットと商品の売上の閲覧 |
| **admin** | マネージャーができることをすべての会社に対して実行可能。会社、会場、カテゴリの管理。マネージャーアカウントの作成と管理者への昇格 |

マネージャーと管理者は何も購入できません: カート、購入手続き、抽選への応募、チケット購入はすべて
彼らを拒否します。マネージャーの会社スコープは UI で隠すだけでなく、データベースクエリで適用されます。
詳細: [ビジネスロジック](business-logic_JP.md)。

## 機能一覧

- **チケット販売:** 公演ごとにキャパシティに基づくティア（VIP / プレミアム / 一般）があり、それぞれ
  一般販売キャンペーンの期間中に直接販売されるか、抽選キャンペーンを通じて販売されます。両方の経路を
  通じて、1 公演につきファン 1 人が持てる有効なチケットは 1 枚です。
- **抽選:** ファンは受け入れ可能なティアを順位付けし、応募期間中に応募します。応募締め切り後に
  マネージャーが抽選を実行します。抽選は Celery ワーカー上で動き、各当選者には支払期限付きの
  `pending_payment` チケットが発行されます。
- **マーケットプレイス:** アルバムまたはグッズの詳細を持つ商品、ジャンル、ファンごとの転売防止上限
  （1 商品あたり 3 個）、カート、購入手続き、配送先住所、そしてマネージャーの「発送」操作。
- **決済:** ローカル開発とデモ用のモックゲートウェイ（`simulate_succ` true/false）と、サンドボックス
  モードの PayPal Orders v2（リダイレクトによる承認、キャプチャエンドポイント、署名付き Webhook）。
- **通知:** 注文確認と発送、チケット確認、抽選の登録・結果・支払いリマインダー・支払い確認、
  マネージャー向けの抽選開始／完了／失敗、パスワードリセット。（`event_reminder` は定義されていますが、
  まだ送信する処理はありません。）
- **メール:** Resend を使用し、Celery タスクから送信するため、リクエストが配信を待つことはありません。
- **画像:** アイドルと商品のアップロードは、開発環境ではローカルファイルシステムに、本番環境では
  S3 互換ストレージに保存されます。
- **パフォーマンスと不正利用対策:** 公開ページとマネージャーページのデータ一式に対する Redis キャッシュ、
  62 のルートに対する Redis によるレート制限。

## 技術スタック

| レイヤー | 技術 |
|---|---|
| API | Python 3.12、FastAPI 0.122、Pydantic 2.12、uvicorn 0.38 |
| データベース | PostgreSQL（本番は Supabase）、SQLAlchemy 2.0、Alembic 1.17 |
| キャッシュ、レート制限、キュー | Redis（msgpack でシリアライズしたキャッシュ）、Redis をブローカーと結果バックエンドに使う Celery 5.6 |
| 認証 | JWT（python-jose、HS256）、passlib 経由の bcrypt |
| 外部連携 | PayPal REST API（httpx）、Resend、S3 互換ストレージ用の boto3 |
| テストと CI | pytest — インメモリのフェイク Redis を使うユニットテスト、実際の Postgres と Redis に対する統合テスト。ruff、GitHub Actions、Codecov |
| フロントエンド | Vue 3、Vite 5、Pinia、Vue Router 4、vue-i18n（`en`/`ja`）、Axios、Sass |
| ホスティング | Render（API、Celery ワーカー、Key Value/Redis）、Supabase、Vercel、Cloudflare DNS |

詳細: [`i-dolly-backend/README.md`](https://github.com/TranXuanAnh930/i-dolly-backend#readme)
および [`i-dolly-frontend/README.md`](https://github.com/TranXuanAnh930/i-dolly-frontend#readme)。
