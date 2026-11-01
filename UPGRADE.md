# Upgrading an existing Raspberry Pi installation

**This is a project-package upgrade, not a Mailu/Roundcube image upgrade.** It preserves existing mail, databases, certificates and credentials. It may recreate Roundcube when you apply the changes.

## From an older `webmail-stack-pi.zip`

Download the new `webmail-stack-updated.zip` and transfer it to the Pi. Stage it **away** from the live folder:

```bash
mkdir -p /tmp/webmail-new
unzip -q webmail-stack-updated.zip -d /tmp/webmail-new
sudo bash /tmp/webmail-new/webmail-stack/upgrade.sh /opt/webmail-stack
cd /opt/webmail-stack
sudo ./webmail.sh prepare
sudo ./webmail.sh config-check
sudo ./webmail.sh apply
sudo ./webmail.sh doctor
```

If installed somewhere other than `/opt/webmail-stack`, pass that location to `upgrade.sh` and `cd` there.

The upgrade snapshots live project configs **before overwriting** under `.upgrade-history/TIMESTAMP/`, with directory permissions `700`. This includes potentially secret-bearing `.env` and `mailu.env`. The files in `$DATA_ROOT` (by default `/srv/webmail`) are left alone. `upgrade.sh` does not touch Docker or STRATO; `apply` validates and applies changes to running containers. It does **not** pull fresh images; use `./webmail.sh update` separately when you choose to update images.

**IMPORTANT about local edits:** `docker-compose.yml` and `roundcube/zz-local.php` in the live folder are replaced by the new packaged versions; your previous customizations are in the timestamped snapshot. Review and selectively merge them if you added unrelated custom settings. Your `.env`, `mailu.env` and `backup.env` remain intact. Existing fetched accounts, SQL-LIKE catch-all alias and SMTP permissions are stored in Mailu's database and are not reset.

If you edited your original `.env` and already configured `ROUNDCUBE_DES_KEY`, it is retained. Otherwise `prepare` generates one. Existing Roundcube sessions may need a **one-time logout/login** after the key is first configured, but future container recreations should keep the same key.

## Normal commands (no manual Docker needed)

```bash
sudo ./webmail.sh status
sudo ./webmail.sh logs-once smtp 200
sudo ./webmail.sh logs fetchmail           # follow; Ctrl-C exits logs only
sudo ./webmail.sh recreate roundcube
sudo ./webmail.sh restart-service fetchmail
sudo ./webmail.sh attachments 30
sudo ./webmail.sh fetch-interval 120
sudo ./webmail.sh reply-policy first-to
sudo ./webmail.sh alias-check test@example.nl
sudo ./webmail.sh smtp-test
sudo ./webmail.sh strato-folders
sudo ./webmail.sh config-backup
```

If necessary, you can restore prior project config from the `.upgrade-history` snapshot, **after stopping/restarting services as appropriate**. Do not remove mail data or wipe the Mailu database. The snapshot contains plaintext secrets, so restrict permissions and retain it only as long as needed.

## New install instead of upgrade

```bash
sudo unzip webmail-stack-updated.zip -d /opt
cd /opt/webmail-stack
sudo ./webmail.sh configure /srv/webmail
sudo ./webmail.sh install
sudo ./webmail.sh admin-create
sudo ./webmail.sh relay
sudo ./webmail.sh doctor
```

Set `DATA_DISK_MOUNT` if using a dedicated SSD. Do not run `admin-create` again for an existing account just because you upgraded. If fetched accounts are already running, no need to re-enter STRATO's IMAP credentials.

## Verification after apply

1. Open Roundcube; if you see `Server Error: Empty password`, log out and log back in using your **local** Mailu mailbox password. If still failing: `./webmail.sh logs-once roundcube 200` and `./webmail.sh logs-once imap 100`.
2. `./webmail.sh alias-check test@example.nl` should return `r@example.nl` if you created Mailu's SQL-LIKE `%@example.nl` alias; this verifies local lookup, not outgoing success.
3. Send a fresh external message to `test@example.nl` and allow for the configured polling interval.
4. Reply from Roundcube and inspect automatically chosen sender *before* sending; check external Gmail `From`/`Return-Path` after sending.
5. If SMTP rejects a new alias, inspect `./webmail.sh logs-once smtp 200`, not repeated Send clicks (which could produce duplicates).

## Safety caveats

- The storage/mail stack is **not a fully verified production deployment**; package syntax and a simulated upgrade were tested in the build environment, not a live Raspberry Pi Mailu integration.
- Backend mail service credentials are not protected from a user with host root or Docker privileges.
- An automated fetcher may skip read STRATO messages and does not provide complete IMAP synchronization.
- Public exposure needs trusted certificates, firewall rules and administrator account protections. No public TCP/25 is published, by design.
