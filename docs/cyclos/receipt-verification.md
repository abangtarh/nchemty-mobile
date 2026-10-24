# Receipt verification (Cyclos custom web service)

Every receipt the app prints carries a QR code with a link like:

    https://ebank.nchemty.com/run/verify-receipt?tx=<reference>&a=<amount>

Anyone can scan it with a normal phone camera and see a **Genuine receipt** or
**Not verified** page served by Cyclos itself. Inside the app, **Scan** and
**Menu → Verify a receipt** call the same service (`.../verify-receipt/json`).

The page shows a receipt as genuine only when the reference **and** the amount
both match a real transfer. Names are shortened (e.g. "Abang T.").

## Setup in Cyclos (admin, about 5 minutes)

1. **System → Tools → Scripts → New → Custom web service**
   - Name: `Verify receipt`
   - Script code: paste `docs/cyclos/verify-receipt.groovy`
   - Save.
2. **System → Tools → Custom web services → New**
   - Name: `Verify receipt`
   - Script: `Verify receipt`
   - URL mappings (one per line):
     ```
     verify-receipt
     verify-receipt/json
     ```
   - HTTP method: `GET`
   - Run as: `Guest` (no HTTP username/password)
   - IP whitelist: leave empty
   - Save and enable.
3. Test in a browser, using a reference and amount from any receipt:
   `https://ebank.nchemty.com/run/verify-receipt?tx=<reference>&a=<amount>`
   - With the right amount: **Genuine receipt**.
   - Change the amount by 1: **Not verified**.
   - `.../verify-receipt/json?tx=..&a=..` returns `{"valid": true, ...}`.

If Nchemty uses a network path (e.g. `https://ebank.nchemty.com/nchemty/...`),
the link becomes `https://ebank.nchemty.com/<network>/run/verify-receipt`, so
build the app with `--dart-define=RECEIPT_VERIFY_URL=<that URL>`.

## App configuration

- Default: `<Cyclos host>/run/verify-receipt`, derived from `CYCLOS_URL`.
- Override: `--dart-define=RECEIPT_VERIFY_URL=https://.../run/verify-receipt`.
- Turn off: `--dart-define=RECEIPT_VERIFY_URL=off` (the QR then only holds the
  reference, amount and time).

## Troubleshooting

- **404 on the link**: the custom web service is missing, disabled, or the URL
  mapping is not exactly `verify-receipt`.
- **Script error / 500**: open System → Tools → Scripts → Verify receipt and run
  it, or check the Cyclos error log. The lookup uses the `Transfer` entity's
  `transactionNumber` (and the numeric id as a fallback).
- **Always "Not verified" for real receipts**: confirm transaction numbers are
  enabled (System → Configurations → Transaction number); otherwise the receipt
  prints the internal id, which the script also accepts.
