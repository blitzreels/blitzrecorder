# BlitzReels Entitlement Contract

The Mac app uses this endpoint to unlock BlitzRecorder Pro for eligible active BlitzReels subscribers.

## Endpoint

`GET https://www.blitzreels.com/api/blitzrecorder/entitlement`

## Authentication

The app sends the access token returned by BlitzReels sign-in:

```http
Authorization: Bearer <token>
Accept: application/json
```

The endpoint must reject missing, expired, malformed, or ineligible tokens.

## Sign-In Redirect

The app starts included-access sign-in at:

`https://www.blitzreels.com/blitzrecorder/sign-in?return_to=blitzrecorder://auth/blitzreels`

If the user is not signed in to BlitzReels, this route redirects to BlitzReels login with a `next` parameter that returns to the same BlitzRecorder sign-in route. After a valid BlitzReels session is present, the route redirects back to the allowed app callback:

`blitzrecorder://auth/blitzreels?token=<access-token>`

The web route must reject arbitrary `return_to` URLs. `Scripts/validate-submission-artifacts.sh` verifies that the production sign-in route redirects unauthenticated users through BlitzReels login and returns HTTP `400` for an invalid external callback URL.

## Success Response

HTTP `200`

```json
{
  "active": true,
  "planName": "BlitzReels Pro"
}
```

Rules:

- `active` is required and must be a boolean.
- `planName` is optional when `active` is `false`.
- `planName` should be a customer-facing BlitzReels plan label when `active` is `true`.
- Do not return subscription IDs, Stripe customer IDs, internal workspace IDs, email addresses, or billing details.

## Ineligible Response

HTTP `200`

```json
{
  "active": false,
  "planName": null
}
```

Use this when the token is valid but the user does not currently have an eligible BlitzReels subscription.

## Auth Failure

HTTP `401` or `403`

```json
{
  "error": {
    "code": "unauthorized",
    "message": "Sign in to BlitzReels again."
  }
}
```

The Mac app treats `401` and `403` as expired sign-in and clears the cached token.

## Temporary Failure

HTTP `429` or `5xx`

```json
{
  "error": {
    "code": "temporarily_unavailable",
    "message": "BlitzReels access could not be verified."
  }
}
```

The Mac app may use a recently verified entitlement cache for up to 7 days when verification is temporarily unavailable.

## Local Validation

Use:

```bash
Scripts/validate-entitlement-endpoint.sh
BLITZRECORDER_ENTITLEMENT_TOKEN=TOKEN Scripts/validate-entitlement-endpoint.sh
BLITZRECORDER_ENTITLEMENT_TOKEN=TOKEN BLITZRECORDER_ENTITLEMENT_EXPECTED_ACTIVE=true Scripts/validate-entitlement-endpoint.sh
BLITZRECORDER_ENTITLEMENT_TOKEN=INACTIVE_TOKEN BLITZRECORDER_ENTITLEMENT_EXPECTED_ACTIVE=false Scripts/validate-entitlement-endpoint.sh
```

The first command verifies that unauthenticated requests are rejected. The second verifies an authenticated JSON response shape. The final two commands assert the production positive and negative entitlement states that must be captured before App Store submission.
