# Middleware `/v1` contract (proposed)

The app calls these routes on the Node middleware / Payment Hub. They are new:
build them on top of the current MoMo bridge, LoanCoreLib / ACAOCoreLib
operations and the KYC pipeline.

## Rules for every route

- **Auth:** the app sends the member's Cyclos session token in `X-Cyclos-Session`.
  The hub calls Cyclos `GET /api/auth` with `Session-Token: <token>` to resolve
  the member, then acts as that member (or via its own access client, scoped to
  that member). Never accept a member id from the request.
- **Money movement** (`/momo/topup`, `/momo/cashout`, `/loans/{id}/repay`,
  `/savings/subscribe`): require `Idempotency-Key`; a repeat with the same key
  returns the first result and never posts twice.
- **Confirmation:** cash-out, repay and subscribe forward `Confirmation-Password`
  to Cyclos so Cyclos validates the transaction PIN / OTP.
- **Errors:** JSON `{ "error": "<code>", "message": "<human text>" }` with a
  4xx/5xx status. `401` means the Cyclos session is no longer valid.
- **Audit:** log member, route, amount, outcome and upstream response to the
  PostgreSQL audit log.

## MoMo

| Method | Path | Body | Returns |
| --- | --- | --- | --- |
| POST | `/momo/topup` | `{ msisdn: "2376XXXXXXXX", amount: 20000 }` | `MomoRequest` (status `PENDING`); credits via TT 40 on success |
| GET | `/momo/requests/{id}` | — | `MomoRequest` |
| POST | `/momo/cashout/quote` | `{ msisdn, amount }` | `{ quoteId, amount, fee, total, expiresAt }` |
| POST | `/momo/cashout` | `{ quoteId }` | `MomoRequest`; debits via TT 41 + fee splits (55–58) |

`MomoRequest` = `{ id, status: "PENDING" | "SUCCESSFUL" | "FAILED", message? }`.

Fee in the quote follows the existing tiered logic: 35 XAF flat under
5 000 XAF; from 5 000 XAF up, ceiling(0.7% + 4), minimum 39 XAF.
Quotes should expire after a short window (e.g. 2 minutes).

## Loans (LoanCoreLib)

| Method | Path | Body | Returns |
| --- | --- | --- | --- |
| GET | `/loans` | — | `[{ id, reference, principal, outstanding, status, nextDueDate?, nextDueAmount? }]` |
| POST | `/loans/apply` | `{ productCode, amount, termMonths, purpose? }` | Application with cost recap |
| POST | `/loans/{id}/accept` | `{ acceptTerms: true }` | Grant result |
| POST | `/loans/{id}/repay` | `{ amount }` | Repayment result |

## Savings (ACAOCoreLib)

| Method | Path | Body | Returns |
| --- | --- | --- | --- |
| GET | `/savings/products` | — | `[{ code, name, summary, subscribed, balance? }]` |
| POST | `/savings/subscribe` | `{ productCode, initialDeposit, acceptTerms }` | Subscription result; sets `acceptanceDate` / `acceptTerms` |

## KYC

| Method | Path | Body | Returns |
| --- | --- | --- | --- |
| POST | `/kyc/session` | — | `{ sessionId }` |
| POST | `/kyc/{sessionId}/upload` | multipart: `stage` (`selfie` \| `document_front` \| `document_back`), `documentType?` (`CNI` \| `PASSPORT` \| `DRIVING_LICENCE`), `image` | `{ accepted, message? }` |
| GET | `/kyc/{sessionId}` | — | `{ status, message? }` |

Liveness, authenticity, OCR, face match and the compliance result run
server-side in the existing pipeline; images are never stored on the device.
