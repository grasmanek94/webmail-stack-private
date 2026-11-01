# STRATO-backed self-hosted webmail (no public MX changes)

A **testable Docker proof-of-concept (updated 2026-10-28)**, intentionally structured for future WAN access. Uses **Mailu 2024.06** (Mailu's currently documented stable series), an **independent official Roundcube Docker image**, Nginx for webmail HTTPS, and STRATO as the **unchanged public inbound MX and outgoing SMTP relay**.

**Important:** The package has been statically reviewed but **not actually run against Docker or STRATO** in the build environment. Test with noncritical mail first. Particularly verify whether Roundcube's `custom_from` plugin loads, Mailu's sender policy permits the chosen dynamic alias, and the retrieved STRATO message preserves the intended recipient. Do not change DNS or route your only mailbox through this setup until these checks pass.

## Already installed? Upgrade, do not reinstall

**Do not unzip over your live project.** Read [UPGRADE.md](UPGRADE.md), stage the updated ZIP in a separate directory, and run its `upgrade.sh` against `/opt/webmail-stack`. It saves your previous project configs and keeps `.env`, `mailu.env`, mailboxes and credentials intact. Then use `./webmail.sh prepare`, `./webmail.sh config-check`, and `./webmail.sh apply` (no raw Docker commands needed). See [AI_SUMMARY.md](AI_SUMMARY.md) for the full previous conversation and verified findings.

## Quick start

Prerequisites: Linux (x86-64 or ARM64 or ARMv7), Docker Engine, Docker Compose v2 plugin, OpenSSL, Python 3, tar, available ports and sufficient disk. Raspberry Pi-class hardware with ~2 GB+ free RAM recommended without antivirus (actual usage varies). STRATO incoming/outgoing access uses credentials you enter **on your own server**.

```bash
unzip webmail-stack.zip
cd webmail-stack
chmod +x webmail.sh

# Optional: choose a data path now, before first install
./webmail.sh configure /srv/webmail
./webmail.sh install
./webmail.sh admin-create
./webmail.sh relay
./webmail.sh doctor
```

On the new Raspberry Pi, **persistent data defaults to `/srv/webmail`**, owned by `root:root` at the top level. To select a different location before installation:

```bash
./webmail.sh configure /mnt/ssd/webmail
# Or interactively: ./webmail.sh configure
# IMPORTANT: if SSD at /mnt/ssd, set DATA_DISK_MOUNT=/mnt/ssd in .env.
# Confirm the filesystem is mounted and will auto-mount after reboot:
findmnt /mnt/ssd
./webmail.sh install
```

The installer checks `DATA_DISK_MOUNT` (when set) is mounted, preventing silent writes to the Pi's SD card if the SSD isn't available. **Changing DATA_ROOT after installation does not migrate existing mail data**, and the `configure` helper refuses changes after initial initialization.

The installer creates the persistent folder, certificates, spam data and databases. It also creates a **persistent Roundcube session encryption key** in `.env` (mode 600), so recreating the container does not rotate that key. The top-level directory defaults to `root:root`. Container-managed subdirectories are NOT recursively chowned after creation: Redis, Mailu/Dovecot, etc. require their own runtime UIDs. You may be asked to use `sudo` if your Docker socket is restricted; membership in `docker` is effectively root-equivalent.

**First-run files:** `install` creates `.env` from `.env.example`, and `mailu.env` from the example with a random 32-byte SECRET_KEY. It does not overwrite them on subsequent installs. It auto-detects a likely LAN IPv4 via routing, but you should check `LAN_IP` in `.env` before relying on the self-signed certificate. Certificates are generated only once; changing hostname/IP later requires importing/regenerating appropriate certs.

## Web URLs and ports

Default host bindings are `0.0.0.0` as requested, **not limited to LAN**. These services are immediately accessible on whichever host interfaces/firewall routes are permitted. No inbound TCP/25 is published. Your router/firewall is your responsibility.

| URL / Port | Purpose |
| --- | --- |
| `https://SERVER_LAN_IP/` (443) | Roundcube webmail, HTTPS |
| `https://SERVER_LAN_IP:8443/admin` | Mailu admin (and Rspamd link) |
| `http://SERVER_LAN_IP:8080` | HTTP -> HTTPS redirect |
| TCP 993 | IMAP over TLS for FairEmail |
| TCP 465 | SMTP over TLS for authenticated submission |
| TCP 587 | SMTP submission STARTTLS |
| TCP 4190 | ManageSieve, optional for third-party filtering clients |
| TCP 25 | **NOT published**; STRATO remains sole public MX |

The initial certificates are **self-signed** and may trigger browser/client warnings. Do not disable certificate verification for Internet-facing clients. For WAN use, obtain a certificate valid for the exact DNS hostname and install it via `./webmail.sh cert-install fullchain.pem privkey.pem`. If your provider/NAT/CGNAT/firewall limits external access, the stack itself will not fix that. STRATO **must remain the MX**; do not add your home server as backup or primary for this phase.

Both web frontends can coexist even though Roundcube runs as a standalone container: Roundcube talks to Mailu `front` over its private Docker network. Mailu's own integrated webmail is disabled to avoid a second conflicting Roundcube instance.

## Set up incoming STRATO mail (in browser)

1. Run `./webmail.sh admin-create` to make your **LOCAL** `r@example.nl` user. Choose a fresh local password independent from STRATO.
2. Visit `https://SERVER_IP:8443/admin` and log in with that local account.
3. Select **Fetched accounts**, add a new account. Choose IMAP, hostname **`imap.strato.de`**, port **993**, TLS enabled, STRATO username **`r@example.nl`**, and STRATO's IMAP password.
4. Set the destination user to your local `r@example.nl`; check **Keep emails on server** to prevent deletion at STRATO; enable **Scan emails** only after confirming scanned fetches do not cause rejection/quarantine you didn't intend.
5. Save. With `FETCHMAIL_DELAY=300`, it polls periodically. Test with **new unread** messages to an alias before enabling on production traffic.

**Crucial Fetchmail caveat:** Mailu's built-in fetcher currently retrieves **unread** messages. If STRATO or another client marks a new message read before the fetcher processes it, that message can be skipped. It is **not** a bidirectional mailbox mirror. Historical/read messages, deletion, flags, folders and STRATO sent items do NOT automatically synchronize. You can use the STRATO inbox as your safety copy. If full UID-based synchronization becomes important, replace the fetcher with a separate UID-tracking getmail6/mbsync service after testing.

## Sending via STRATO

Run `./webmail.sh relay` and enter the STRATO **SMTP password** privately at the terminal. It writes it into local `mailu.env` (mode 600), then recreates Mailu SMTP when running. The configured route is:

`Roundcube / FairEmail => local Mailu authenticated SMTP => smtp.strato.de:587 with STARTTLS => internet`

STRATO's test confirmed that direct SMTP submission as an unregistered `@example.nl` sender works and DKIM/DMARC pass, but **Mailu itself can impose additional sender policies**. The file sets `WILDCARD_SENDERS=r@example.nl`, which grants wide sender-spoofing permission to that authenticated local user. Mailu's documented behavior may differ depending on whether the From address exists as a local alias. If a dynamic test is rejected, create a local **catch-all alias** using Mailu Admin > Domains > example.nl > Aliases, enable SQL LIKE and choose a pattern such as `%@example.nl` with destination `r@example.nl`. Confirm it does not duplicate fetched delivery. Don't open SMTP to untrusted users with overly broad sender-spoofing rights.

For an end-to-end test from your LAN:

```bash
python3 tools/test_local_smtp.py
```

It asks for the **LOCAL** Mailu password, a controlled external mailbox, and an arbitrary alias; it reports whether local submission is accepted. Check the destination's actual `From`, `Return-Path`, DKIM/SPF/DMARC and Received headers to confirm **STRATO** relayed it. This test script ignores TLS trust *only for the initial self-signed LAN test*. Don't use it as a WAN client.

For Android, configure **FairEmail** with IMAP `SERVER_HOST:993` SSL/TLS and SMTP `SERVER_HOST:465` SSL/TLS (or 587 STARTTLS), username and password = **LOCAL Mailu account**. FairEmail supports the catch-all username regex `.*`; enable editable username and test that reply From matches the original delivered alias. If local SMTP's sender authorization blocks a dynamic From, a safe temporary fallback is STRATO SMTP `smtp.strato.de:465` on the phone with STRATO credentials, while leaving the phone's IMAP pointed to Mailu.

## Webmail / dynamic catch-all sender

Open `https://SERVER_IP/` and log in with the LOCAL Mailu account. The official Roundcube container installs plugin `r3c/custom-from:1.8.2` from Composer when started; **an internet connection to Packagist/GitHub is needed on initial startup**. The plugin adds a custom From editor and can pick the original To address on reply. Its configuration is `roundcube/zz-local.php`.

Check plugin behavior under **Settings -> Preferences -> Reply address (Custom From)**. The config restricts automatic guesses to the same domain as the signed-in identity and checks headers in this order: **`To`, `Cc`, `X-Original-To`, `Envelope-To`, `Delivered-To`** (first matching address preferred). For this initial single-domain setup, the allowed domain is `@example.nl`. Per-user rule overrides are disabled by default; use `./webmail.sh reply-policy first-to` or `delivery-first` to change the ordering. This has not yet been verified with a multiple-`To:` real-world test. If fetchmail loses the original envelope address, BCC and forwarded messages may not get correct automatic sender selection. ALWAYS check From before sensitive replies.

## Browser-based filtering / SPAM_REJECT

Roundcube includes **ManageSieve** and **Mark as Junk** plugins. Go to **Settings -> Filters** for point-and-click filtering or raw Sieve editing. The raw editor is enabled via `roundcube/zz-local.php`.

Create an IMAP folder `SPAM_REJECT` first. See `examples/SPAM_REJECT.sieve` for a sample raw script matching specific `To`/`Cc` aliases, moving messages into that folder and not sending a bounce. **This is a local move, not an internet-level SMTP reject.** The example will **NOT** reliably match BCC or all forwarded mail, because original envelope recipient might have been lost at STRATO/fetchmail. Test headers with both normal and BCC messages before creating permanent rules.

Mailu Admin also exposes **Rspamd** for spam training and thresholds. Some high-scoring messages may still be refused on local reinjection when you enable `Scan emails`; leave scanning off until testing catches and classifications are safe for your use case. `SPAM_REJECT` is independent of the Junk training folder.

## CLI commands

The script now covers common operations without requiring raw `docker compose` commands:

```bash
./webmail.sh help
./webmail.sh configure [/path/to/data]  # only before first install
./webmail.sh install
./webmail.sh prepare                  # create persistent Roundcube session key if missing
./webmail.sh apply                    # apply edited project config, recreate Roundcube
./webmail.sh update                   # pull newer Docker images AND apply
./webmail.sh start | stop | restart | status
./webmail.sh recreate roundcube       # or smtp, fetchmail, imap, web ...
./webmail.sh restart-service fetchmail
./webmail.sh logs fetchmail           # live; Ctrl-C exits
./webmail.sh logs-once smtp 200       # last 200 lines; no follow
./webmail.sh attachments 30           # change single-file upload cap in MB (1..30)
./webmail.sh fetch-interval 120       # change polling interval seconds (60..3600)
./webmail.sh reply-policy first-to    # or delivery-first
./webmail.sh alias-check test@example.nl # confirm local Mailu catch-all lookup
./webmail.sh smtp-test                # interactive local SMTP end-to-end test
./webmail.sh strato-folders           # read-only folder discovery at STRATO
./webmail.sh doctor
./webmail.sh admin-create
./webmail.sh relay
./webmail.sh config-check             # validation only; does not print secrets
./webmail.sh config-backup            # UNENCRYPTED local config snapshot (includes secrets)
./webmail.sh backup                   # UNENCRYPTED local archive
./webmail.sh backup-remote-init       # optional restic SFTP
./webmail.sh backup-remote
./webmail.sh backup-remote-list
./webmail.sh backup-remote-check
./webmail.sh cert-install /path/fullchain.pem /path/privkey.pem
```

Default Roundcube upload cap is **30M** instead of the official image's 5M; Mailu's 50 MB total MIME message limit and Nginx's 52 MB body limit still apply, and remote servers may impose their own limits. Note that MIME/base64 encoding increases attachment size. Updating `roundcube/zz-local.php` or `docker-compose.yml` manually? `./webmail.sh apply` handles refreshing the relevant container.

Mailu's SQL-LIKE catch-all alias should be configured once in Admin as **`%@example.nl` -> `r@example.nl`** with "Use SQL LIKE Syntax" enabled; Mailu's user sender-spoof permission must also be enabled. The observed `postmap` result confirmed lookup, but keep testing fresh arbitrary senders: it does *not* prove all SMTP submissions will succeed.

**Update** pulls images tagged by your `.env` and recreates them, without deleting volumes. Back up first. `MAILU_VERSION=2024.06` follows Mailu stable patch releases; Roundcube `latest` follows its stable updates. For fully reproducible builds, pin the exact Roundcube image digest after initial validation.

**Local backup** stops the stack, archives the whole persistent `DATA_ROOT` tree (excluding previous backups) to `DATA_ROOT/backups/`, then restarts the stack. It does **not** include project files if you've extracted the ZIP somewhere else; back up `docker-compose.yml`, `.env`, `mailu.env`, `proxy/`, and `roundcube/` separately. Backups include email content, DBs, TLS private keys and credentials: encrypt off-host copies. Restore is manual, with services stopped; test backups periodically. For **encrypted, versioned, off-Pi backups to your main server**, a restic-over-SFTP helper and `backup.env.example` are included. See `BACKUPS.md`. The feature is inactive until you configure your destination, SSH key and a passphrase on the Pi. `./webmail.sh backup-remote-init` initializes it; `./webmail.sh backup-remote` uploads encryption-protected snapshots with data and stack configuration. Nothing is auto-scheduled by default.

`./webmail.sh config` and `./webmail.sh config-check` now validate Compose **without printing expanded credentials**. Keep the environment files private. **Never share** `mailu.env`, live TLS keys, full logs with authentication tokens, or unredacted messages.

## Limits before WAN use

- **WAN-ready topology is NOT equivalent to a hardened public deployment.** Replace self-signed certs, confirm DNS to your actual host, lock down 8443 admin behind VPN/allowlist if feasible, enable firewall restrictions, monitor authentication abuse, configure backups, and update images. Do not forward public TCP/25 during the STRATO-only phase.
- Your public MX and SMTP authentication reputation remain at STRATO. If you later move MX home, revisit MX priority, SPF/DKIM/DMARC, PTR, port 25, spam protection, rate limiting, and backup MX design before making that change.
- Mailu runs on a bridge network, and custom From is an externally maintained Roundcube plugin. The exact combined behavior hasn't been verified against a live server in this environment.

## Official references

- Mailu compose setup: https://mailu.io/2024.06/compose/setup.html
- Mailu config: https://mailu.io/2024.06/configuration.html
- Mailu fetched account admin docs: https://mailu.io/2024.06/webadministration.html
- Roundcube Docker docs: https://github.com/roundcube/roundcubemail-docker
- Roundcube custom-from: https://github.com/r3c/custom_from
