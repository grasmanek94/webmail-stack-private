# Changelog

## 2026-10-28 — updated Raspberry Pi deployment package

- Added persistent, automatically generated `ROUNDCUBE_DES_KEY` in `.env`, passed to official Roundcube image. Already configured keys are retained. Solves key persistence; existing sessions might need one re-login after upgrade.
- Raised Roundcube attachment upload size from its default 5 MB to `30M`, configurable with `./webmail.sh attachments MB`. Mailu message cap remains 50 MB; Nginx proxy cap 52 MB.
- Configured `custom_from` to prefer the **first matching own-domain To recipient** over Cc and delivery headers; restricted to `@example.nl`, disabled per-user overrides for deterministic server policy. Change priority via `./webmail.sh reply-policy`.
- Added `./webmail.sh prepare`, `apply`, `config-check`, `recreate SERVICE`, `restart-service SERVICE`, `logs-once`, `fetch-interval`, `alias-check`, `smtp-test`, `strato-folders`, `config-backup`.
- Changed `config` to validation-only, preventing accidental printing of expanded secrets.
- Fixed Raspberry Pi initial directory ownership fallback typo (now `root:root`).
- Added staged `upgrade.sh` with config snapshots and preservation of live `.env`, `mailu.env`, `backup.env`, and persistent data.
- Added `UPGRADE.md` and `AI_SUMMARY.md` documenting entire problem and findings, user test results, unresolved details, and future steps.
- Retained STRATO as sole public MX (no published host TCP/25), `mailu.env` relay settings, fetch accounts, local aliases, Docker data/backup design and optional restic encrypted backups.

**Not changed automatically:** local SQL-LIKE catch-all alias and 'Allow the user to spoof the sender' must still be configured in Mailu Admin. Existing accounts and passwords remain intact on upgrades. All new/revised settings still require live integration testing.
