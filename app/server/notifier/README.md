# The notifier — what it would be, and what it costs

Not built. This file exists so that the decision is written down before
somebody builds it in an afternoon and gives away the thing v2 was designed to
withhold.

## What the app already does without it

Opens, checks, and decrypts with no server at all. `EnsReader` reads the chain
directly from the phone. Take every server away — ours included — and the app
still finds and opens what belongs to it. That property is the product, not a
feature of it.

## What a notification needs

Somebody watching the chain who can reach the phone. Two things follow, and
both are costs:

1. **A subscription the server can see.** Firebase topics are the cheap way:
   the app subscribes to `nk-<first 16 bytes of SHA-256 of the name>` for each
   watched name. The notifier learns that *some* device watches a name whose
   hash it can compute for any name it already knows. It cannot tell two
   subscribers apart, and there is no account to attach them to.

2. **A watcher.** A Cloudflare Worker on a cron, reading `TextChanged` logs on
   the Sepolia ENS resolver, mapping each affected name to its topic and
   sending one content-free message: *a record changed on a name you watch*.

## What it must never do

- **Subscribe by grant address.** `nextkey.g2.<tag>` is computable only from the
  shared secret. A server that knew a device's tags could link sender and
  recipient — exactly what v1 leaked by putting the recipient's key hash in the
  record name, and exactly what v2 was rebuilt to stop.
- **Carry content.** The message says something changed. It never carries a
  ciphertext, never a record value, never a name in plaintext.
- **Keep a log.** The API next door already states this, and its `wrangler.toml`
  is the statement: no KV, no D1, no analytics. The absence is the
  configuration.

## The alternative worth measuring first

A periodic local check (`WorkManager`, a few times a day) needs no server, no
Firebase project, and no subscription anybody can see. It costs battery and
latency. For a product whose whole claim is that nothing rests on a server we
run, that may be the better trade — and it is cheap to try before the notifier
is written.
