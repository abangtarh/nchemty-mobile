// Nchemty receipt verification: Cyclos 4 custom web service script.
//
// Setup (System > Tools): see docs/cyclos/receipt-verification.md.
//   URL mappings:   verify-receipt
//                   verify-receipt/json
//   HTTP method:    GET      Run as: Guest
//
// The receipt QR opens
//   https://ebank.nchemty.com/run/verify-receipt?tx=<reference>&a=<amount>
// and the app calls .../verify-receipt/json?tx=..&a=.. for the same answer.
//
// A receipt is genuine only when BOTH the reference and the amount match a
// real transfer, so someone who only knows (or guesses) a reference learns
// nothing. Names are shortened ("Abang T.") so the page never exposes full
// member details. Read-only: the script never changes anything.

import java.math.RoundingMode
import java.text.SimpleDateFormat

import org.cyclos.entities.banking.QTransfer
import org.cyclos.model.utils.ResponseInfo

String tx = (request.parameters.tx ?: '').toString().trim()
String amountText = (request.parameters.a ?: '').toString().trim().replaceAll(/[\s,]/, '')
boolean asJson = (path ?: '').endsWith('json')

// ---------- helpers ----------
String esc(Object v) {
    (v == null ? '' : v.toString())
        .replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
        .replace('"', '&quot;').replace("'", '&#39;')
}

def unproxy(Object o) {
    try { return org.hibernate.Hibernate.unproxy(o) } catch (Throwable ignored) { return o }
}

/** "Abang Tarh Adrian" -> "Abang T."; system accounts -> account type name. */
String partyName(Object account) {
    if (account == null) return 'Nchemty Credit Union'
    def acc = unproxy(account)
    def user = null
    try { user = unproxy(acc.user) } catch (Throwable ignored) { }
    if (user == null) {
        try { return acc.type?.name ?: 'Nchemty Credit Union' } catch (Throwable ignored) { return 'Nchemty Credit Union' }
    }
    String name = (user.name ?: user.username ?: '').toString().trim()
    def parts = name.split(/\s+/).findAll { it }
    if (parts.isEmpty()) return 'Nchemty member'
    return parts.size() == 1 ? parts[0] : "${parts[0]} ${parts[1].substring(0, 1).toUpperCase()}."
}

String money(BigDecimal v) {
    String s = String.format(Locale.US, '%,d', v.abs().setScale(0, RoundingMode.HALF_UP).longValue())
    return s.replace(',', ' ') + ' XAF'
}

// ---------- lookup ----------
def transfer = null
BigDecimal claimed = null
try { claimed = amountText ? new BigDecimal(amountText) : null } catch (Exception ignored) { }

if (tx && claimed != null) {
    def t = QTransfer.transfer
    try {
        transfer = entityManagerHandler.from(t).where(t.transactionNumber.eq(tx)).singleResult(t)
    } catch (Throwable ignored) { }
    // Without transaction numbers enabled, the app prints the internal id.
    if (transfer == null && tx ==~ /\d{1,18}/) {
        try {
            transfer = entityManagerHandler.from(t).where(t.id.eq(Long.valueOf(tx))).singleResult(t)
        } catch (Throwable ignored) { }
    }
}

boolean valid = false
if (transfer != null) {
    BigDecimal real = transfer.amount.abs().setScale(0, RoundingMode.HALF_UP)
    valid = real.compareTo(claimed.abs().setScale(0, RoundingMode.HALF_UP)) == 0
}

Map result = [valid: valid, reference: tx]
if (valid) {
    def tz = TimeZone.getTimeZone('Africa/Douala')
    def human = new SimpleDateFormat('d MMM yyyy, HH:mm', Locale.ENGLISH); human.timeZone = tz
    def iso = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX"); iso.timeZone = tz
    boolean reversed = false
    try { reversed = transfer.chargedBackBy != null } catch (Throwable ignored) { }
    String typeName = null
    try { typeName = transfer.type?.name } catch (Throwable ignored) { }
    result += [
        amount  : transfer.amount.abs().setScale(0, RoundingMode.HALF_UP),
        currency: 'XAF',
        date    : iso.format(transfer.date),
        dateText: human.format(transfer.date),
        type    : typeName,
        from    : partyName(transfer.from),
        to      : partyName(transfer.to),
        reversed: reversed,
    ]
}

if (asJson) return result

// ---------- HTML page ----------
String body
if (valid) {
    String status = result.reversed
        ? '<div class="warn">This transaction was later reversed.</div>' : ''
    body = """
      <div class="badge ok">&#10003;</div>
      <h1>Genuine receipt</h1>
      <p class="lead">Nchemty recorded this transaction.</p>
      ${status}
      <div class="amount">${esc(money(result.amount as BigDecimal))}</div>
      <table>
        <tr><td>Reference</td><td><b>${esc(tx)}</b></td></tr>
        <tr><td>Date</td><td>${esc(result.dateText)}</td></tr>
        ${result.type ? "<tr><td>Type</td><td>${esc(result.type)}</td></tr>" : ''}
        <tr><td>From</td><td>${esc(result.from)}</td></tr>
        <tr><td>To</td><td>${esc(result.to)}</td></tr>
      </table>
      <p class="small">Check that the amount, date and names on the paper slip match this page exactly.</p>"""
} else {
    String why = (!tx || claimed == null)
        ? 'This link is incomplete. Scan the QR code on the receipt again.'
        : 'No Nchemty transaction matches this reference and amount. The receipt may have been altered. Do not release goods or cash against it.'
    body = """
      <div class="badge bad">!</div>
      <h1>Not verified</h1>
      <p class="lead">${esc(why)}</p>
      ${tx ? "<table><tr><td>Reference</td><td>${esc(tx)}</td></tr>${claimed != null ? "<tr><td>Amount on slip</td><td>${esc(money(claimed))}</td></tr>" : ''}</table>" : ''}
      <p class="small">Questions? Visit any Nchemty branch with the receipt.</p>"""
}

String html = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Nchemty receipt check</title>
<style>
  body{margin:0;font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;background:#f4f1ea;color:#1d2420}
  header{background:#0f4c3a;color:#fff;padding:16px 20px}
  header b{display:block;font-size:17px} header span{color:#c8962e;font-size:13px}
  main{max-width:460px;margin:20px auto;padding:0 16px}
  .card{background:#fff;border-radius:14px;padding:24px 20px;box-shadow:0 1px 3px rgba(0,0,0,.08);text-align:center}
  .badge{width:56px;height:56px;border-radius:50%;margin:0 auto 10px;display:flex;align-items:center;justify-content:center;font-size:30px;font-weight:700;color:#fff}
  .ok{background:#1f8a5b} .bad{background:#b3261e}
  h1{margin:6px 0 4px;font-size:22px} .lead{color:#5b6660;margin:0 0 14px}
  .amount{font-size:30px;font-weight:800;margin:8px 0 14px}
  table{width:100%;border-collapse:collapse;text-align:left;font-size:15px}
  td{padding:9px 4px;border-top:1px solid #eee;vertical-align:top} td:first-child{color:#5b6660;width:40%}
  .warn{background:#fff4e0;color:#8a5a00;border-radius:8px;padding:8px;margin-bottom:10px}
  .small{color:#5b6660;font-size:13px;margin-top:16px}
</style></head>
<body><header><b>Nchemty Credit Union</b><span>Receipt verification</span></header>
<main><div class="card">${body}</div></main></body></html>"""

def response = new ResponseInfo(status: 200, stringBody: html)
response.setHeader('Content-Type', 'text/html;charset=UTF-8')
response.setHeader('Cache-Control', 'no-store')
return response
