# BlitzRecorder license store

BlitzRecorder can run without a database, but production should use Neon Postgres so paid licenses can be queried, attributed, and revoked without relying only on stateless signed keys.

## Neon

Set `POSTGRES_URL` to the Neon pooled connection string for the production branch. `DATABASE_URL` also works, but `POSTGRES_URL` is preferred for clarity.

The app lazily creates and migrates these tables on first license-store access:

- `blitzrecorder_licenses`: license identity, customer/payment IDs, Stripe livemode/account context, checkout source, attribution metadata, status, and revocation reason.
- `blitzrecorder_revoked_payment_intents`: payment-intent level revocations from refunds/disputes so future license backfills stay revoked.

Useful manual revocation:

```sql
UPDATE blitzrecorder_licenses
SET status = 'revoked',
    revoked_reason = 'manual_review',
    updated_at = now()
WHERE license_id = '<license_id>' AND status <> 'revoked';
```

## Stripe

Required environment variables:

- `STRIPE_SECRET_KEY`
- `STRIPE_WEBHOOK_SECRET`
- `BLITZRECORDER_STRIPE_PRICE_ID`
- `BLITZRECORDER_LICENSE_SECRET`
- `POSTGRES_URL`

Recommended:

- `STRIPE_ACCOUNT_ID`: stored with each license when the checkout session is created outside Stripe Connect webhook context.
- `STRIPE_AUTOMATIC_TAX=true`: if tax collection is enabled in Stripe.

Configure the Stripe webhook endpoint at:

```text
https://<site>/api/stripe/webhook
```

Subscribe to:

- `checkout.session.completed`
- `charge.refunded`
- `charge.dispute.created`

Checkout metadata is copied into `blitzrecorder_licenses.attribution`, including `checkout_source`, landing path/referrer, UTM fields, click IDs, and DataFast visitor/session IDs when available.

The 2026 early lifetime payload is explicitly grandfathered:

```text
plan: early_lifetime_2026
maxDevices: null
grandfathered: true
```

Future device-limited plans should use new plan identifiers rather than changing
the terms of already-issued early lifetime keys.
