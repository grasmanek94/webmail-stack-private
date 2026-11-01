# AI SUMMARY — STRATO-backed self-hosted mail project

**Updated:** 2026-10-28  
**Purpose:** Self-contained context for resuming a future ChatGPT / assistant / human admin session.  
**Status:** An actual user installation on a new Raspberry Pi is operational for webmail and STRATO IMAP fetching; additional end-to-end catch-all reply validation remains. The packaged updates have been statically tested, **not** run against the user's live Pi.

## Original user request / priorities

The user owns domain `example.nl` and uses paid **STRATO** hosted email with a catch-all mailbox `r@example.nl`. Every company gets a unique ad-hoc address, e.g. `marktplaats@example.nl`, `mediamarkt@example.nl`, `politie@example.nl`, or `gemeente@example.nl`. The user can identify leaked or sold addresses and block them. They want:

- No requirement to pre-create individual catch-all aliases.
- Reply automatically **from the address the original message was sent to**, on **Android and webmail**. For a message `To: x@example.nl, y@example.nl`, they prefer `x@example.nl` (first matching `To:` address); then try `Cc:` and original-recipient headers as fallbacks.
- Programmable filtering, preferably managed from a **browser** (visual filters and raw scripts), so leaked aliases can be quarantined in a folder like `SPAM_REJECT` and mail can be marked/junked/organized.
- Privacy, local Docker hosting, encrypted backup to main Linux server, few SSH interventions.
- Initially **no MX change**. STRATO receives internet email, local Mailu fetches it, and outgoing mail relays via STRATO. Possibly later home MX plus STRATO backup MX, but not now.
- Docker on a dedicated Raspberry Pi, rather than a shared Linux server with other root users. Other root users cannot be reliably prevented from inspecting runtime mail/passwords on a shared host.
- The original main server used `/data/users/shared/docker/webmail` with owner rafal; new separate Pi defaults to persistent data `/srv/webmail` (configurable before initial install). Pi is headless Debian Trixie.

## Chosen architecture

```
Internet incoming mail -> STRATO (unchanged public MX + catch-all)
   STRATO IMAP 993 (fetch periodically, originals retained)
       -> Mailu Fetchmail -> local Mailu/Postfix/Dovecot mailbox
           -> Roundcube webmail (https, custom_from and ManageSieve)
           -> FairEmail Android (local IMAPS/SMTPS)

Outbound:
Roundcube/FairEmail -> Mailu submission -> smtp.strato.de:587 STARTTLS -> internet
```

Deployment: **Mailu 2024.06**, Docker Compose, separate Roundcube official Docker container, `r3c/custom-from:1.8.2`, Rspamd, Dovecot/Sieve, fetchmail, nginx proxy. No public host port 25 is published. Bind IP defaults `0.0.0.0` (potentially WAN-ready port exposure; user controls network firewall). TLS initially self-signed; must install trusted cert and harden access before WAN.

## Confirmed real-world tests by user

1. **STRATO arbitrary same-domain sender works directly:** Python SMTP test authenticated `r@example.nl` to `smtp.strato.de:465`, sent normal and random `strato-test-3ce1dde74c@example.nl` email to a controlled Gmail inbox. Gmail received both. Random From and Return-Path preserved. `dkim=pass`, `dmarc=pass`, `spf=none`. Another Ed25519 DKIM signature reported neutral/no key, but RSA DKIM passed. The `spf=none` result is an improvement opportunity, not a current failure.
2. **Mailu local alias lookup works:** After creating a SQL-LIKE catch-all alias in Mailu (pattern `%@example.nl`, mapped to `r@example.nl`), `postmap -q test@example.nl socketmap:unix:/tmp/podop.socket:alias` returned `r@example.nl`. **This only confirms alias lookup, not yet consistently successful outgoing submission from every unknown alias.**
3. **STRATO IMAP fetch is operational:** Initially nothing appeared, then mail showed up after polling delay (configured `FETCHMAIL_DELAY=300` seconds in original package). User saw incoming mail in Roundcube.
4. **Roundcube login recovered after container recreation:** Error seen: `Connection to storage server failed. Server Error: Empty password`. Logging out and signing in again fixed it. Earlier assistant suspected changing Roundcube session encryption key across recreation; **not conclusively proven**. This new package persists a stable key, though first application may invalidate existing sessions once.
5. **SMTP rejection before Mailu catch-all alias:** Roundcube error `SMTP Error (550): Failed to add recipient ... Sender address rejected: User unknown in virtual mailbox table`. Mailu `WILDCARD_SENDERS` / sender spoof checkbox alone does not necessarily exempt unlisted senders from Postfix validation. User had experienced failure on attempts 1–2, success on third; **reason for intermittent behavior has not been proven**. After adding SQL-LIKE alias, verify actual first-attempt submission for several *fresh* unknown aliases, and inspect SMTP logs if still rejected.
6. **Original STRATO folder discovery via IMAP:** Python `imaplib.IMAP4_SSL(...).list()` returned 9 folders, separator `.`. Using `mail.list('', '*')` caused STRATO error `[CLIENTBUG] Command syntax error`; corrected with `mail.list()`.

## STRATO IMAP folders discovered by the user

```
(\\Junk \\HasNoChildren) "." "Spam"
(\\Drafts \\HasNoChildren) "." "Drafts"
(\\Trash \\HasNoChildren) "." "Trash"
(\\Sent \\HasNoChildren) "." "Sent Items"
(\\HasChildren) "." "INBOX"
(\\HasNoChildren) "." "INBOX.SPAM_Unsubscribed"
(\\HasNoChildren) "." "INBOX.RijpelbergNieuwbouw"
(\\HasNoChildren) "." "INBOX.UWB"
(\\HasNoChildren) "." "INBOX.Archive"
```

Commas for Mailu's Fetched accounts folder field if deliberately collecting all:
`INBOX,Spam,Drafts,Trash,Sent Items,INBOX.SPAM_Unsubscribed,INBOX.RijpelbergNieuwbouw,INBOX.UWB,INBOX.Archive`

**Caution:** Mailu's built-in Fetchmail is a mail collector, not a 2-way IMAP mirror; documentation describes unread-message fetching, and folder hierarchy/flags are not reliably preserved. Fetching Sent/Drafts/Trash may re-deliver mail through the incoming pipeline. For full history/folder/flag migration, imapsync is a better one-time option (not included in this stack). Do not simultaneously configure POP3 and IMAP fetch of the same messages.

## Useful operational details and lessons

- STRATO servers: `imap.strato.de:993` SSL/TLS; `pop3.strato.de:995` SSL/TLS; `smtp.strato.de:465` SSL/TLS for direct clients, `smtp.strato.de:587` STARTTLS for Mailu relay (test relay on your installation).
- `mailu.env` contains relay password in plaintext mode `600`. Fetched-account IMAP credentials are saved inside Mailu's application database. Anyone with host root or Docker access can access these credentials/runtime memory. Remote backup can be restic-encrypted in transit and at rest but does not change host-root trust.
- Browser-managed Sieve filters: Roundcube Settings > Filters; raw Sieve editing enabled. Move blocked aliases to `SPAM_REJECT` rather than emitting SMTP reject/bounce after the STRATO delivery. Sieve rules comparing `To:` and `Cc:` cannot reliably identify BCC/original envelope recipients unless an original-recipient header is preserved.
- Roundcube `r3c/custom-from` supports automatic reply identity matching. **Package now defaults to first same-domain address in `To:`, followed by `Cc:`, then delivery headers**. It restricts matching to `example.nl` and disables per-user override for consistency. This preference has not yet been end-to-end verified for multi-address/quoted/forwarded emails.
- Roundcube official Docker image defaults to **5 MB upload**; package now sets `ROUNDCUBEMAIL_UPLOAD_MAX_FILESIZE=30M`. Mailu has 50 MB message limit, nginx proxy 52 MB body limit. Due to MIME/base64 overhead, keep a single attachment ~30 MB or below. STRATO/destination may have smaller limits.
- New default includes a stable `ROUNDCUBEMAIL_DES_KEY` generated once and held in `.env`. Changing it will invalidate Roundcube sessions. **Do not print or rotate casually.**
- Docker image updates are a separate operational task: `./webmail.sh update` pulls new images; `./webmail.sh apply` applies already packaged config changes without pulling new images. Keep version pinning/change control in mind (Roundcube tag `latest` by default).
- The old installer initially had an owner fallback typo that could attempt `rafal:rafal` even when user was not on the Pi; corrected to `root:root` default for a new Raspberry Pi. Do not recursively chown data used by Mailu containers.
- Mailu 2024.06 Postfix can reject unlisted senders despite sender spoofing checkbox; SQL-LIKE catch-all alias and Mailu sender authorization both matter. Do not disable sender validation globally without a careful security review.
- FairEmail Android regex `.*` for catch-all identities was identified, but not yet user-validated in this installation.

## Commands in updated `webmail.sh`

```
./webmail.sh install                # new deployment only
./webmail.sh prepare                # generate stable Roundcube key if missing
./webmail.sh config-check           # validate Compose without printing secrets
./webmail.sh apply                  # apply packaged config; recreate Roundcube only if needed
./webmail.sh update                 # pull Docker images and apply
./webmail.sh recreate roundcube     # replace only a named container
./webmail.sh restart-service smtp   # restart only one service
./webmail.sh attachments 30         # upload cap (MB)
./webmail.sh fetch-interval 120     # poll delay seconds
./webmail.sh reply-policy first-to  # or delivery-first
./webmail.sh alias-check test@example.nl
./webmail.sh logs-once smtp 100
./webmail.sh logs fetchmail        # follow; Ctrl+C to stop
./webmail.sh smtp-test             # interactive local outgoing mail test
./webmail.sh strato-folders        # read-only IMAP folder discovery
./webmail.sh config-backup         # local plaintext secret-bearing config archive
./webmail.sh backup               # stop/locally archive data, unencrypted
./webmail.sh backup-remote-init / backup-remote / backup-remote-list / backup-remote-check
./webmail.sh relay / admin-create / cert-install ...
./webmail.sh doctor / status / start / stop / restart / help
```

## Upgrading from the original ZIP safely

**Do not unzip directly over the live `/opt/webmail-stack` directory.** Extract the updated ZIP to a staging directory and invoke its `upgrade.sh`:

```
mkdir -p /tmp/webmail-new
unzip webmail-stack-updated.zip -d /tmp/webmail-new
sudo bash /tmp/webmail-new/webmail-stack/upgrade.sh /opt/webmail-stack
cd /opt/webmail-stack
sudo ./webmail.sh prepare
sudo ./webmail.sh config-check
sudo ./webmail.sh apply
sudo ./webmail.sh doctor
```

`upgrade.sh` snapshots existing project files under `/opt/webmail-stack/.upgrade-history/...` (mode 700; **may include secrets**), replaces only packaged project files, and **does NOT replace** `.env`, `mailu.env`, `backup.env`, certs, local mail, Redis, Mailu database, or other `$DATA_ROOT` files. It overwrites old `roundcube/zz-local.php` and `docker-compose.yml` after snapshot: preserve/merge any unrelated local tweaks. The new Roundcube key might force a one-time re-login.

## Outstanding work / prioritize next time

1. Validate fresh unknown alias sending **on the first try** via `./webmail.sh smtp-test`, Mailu alias lookup and real recipient headers; logs if 550 persists.
2. Validate **automatic reply from correct first To recipient**, including a message with two `@example.nl` To recipients, Cc fallback, BCC if possible, and check Gmail `From` and `Return-Path` after sending.
3. Decide whether full STRATO folder sync is required; if so use imapsync for initial history, then design reliable ongoing strategy with UID tracking instead of assuming fetchmail is sync.
4. Establish encrypted restic backups from Pi to the main Linux server; test restoration and retention. No schedule is active by default.
5. Before any WAN exposure, trusted TLS certificate, firewall, credential policy, MFA where possible, and security/abuse monitoring. Keep public TCP/25 closed while STRATO is MX.
6. If a real SMTP-level reject is desired later, home must become public MX (or an internet-facing gateway must reject before STRATO accepts it). `SPAM_REJECT` is only local quarantine.

## Technical references

- Mailu 2024.06 config: https://mailu.io/2024.06/configuration.html
- Mailu admin/fetched accounts/aliases: https://mailu.io/2024.06/webadministration.html
- Roundcube Docker: https://github.com/roundcube/roundcubemail-docker
- Custom From plugin: https://github.com/r3c/custom_from
- Restic: https://restic.readthedocs.io/

**No credentials are embedded in this summary or the ZIP.** Never share runtime `.env`, `mailu.env`, `backup.env`, TLS private keys, restic passphrase or raw authentication logs.
