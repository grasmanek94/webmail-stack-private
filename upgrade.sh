#!/usr/bin/env bash
# Update project code from a staged ZIP without overwriting persistent data or live secrets.
set -Eeuo pipefail
umask 077
source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
target="${1:-/opt/webmail-stack}"
[[ "$target" = /* ]] || { echo 'Target must be an absolute path' >&2; exit 2; }
target="$(cd "$target" 2>/dev/null && pwd -P)" || { echo "Missing target directory: $target" >&2; exit 2; }
[[ "$target" != "$source_dir" ]] || { echo 'Staged source and target cannot be the same directory' >&2; exit 2; }
for f in .env mailu.env webmail.sh docker-compose.yml; do
  [[ -f "$target/$f" ]] || { echo "Missing live $target/$f - use install on a new stack" >&2; exit 2; }
done
for f in docker-compose.yml webmail.sh roundcube/zz-local.php tools/list_strato_folders.py AI_SUMMARY.md; do
  [[ -f "$source_dir/$f" ]] || { echo "Invalid new package: missing $f" >&2; exit 2; }
done
stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
snapshot="$target/.upgrade-history/$stamp"
mkdir -p "$snapshot"
chmod 700 "$target/.upgrade-history" "$snapshot"
# Back up all project configs and sensitive env files first. Do not archive mailboxes.
for f in .env mailu.env backup.env docker-compose.yml webmail.sh upgrade.sh roundcube proxy tools; do
  if [[ -e "$target/$f" ]]; then
    mkdir -p "$snapshot/$(dirname "$f")"
    cp -a "$target/$f" "$snapshot/$f"
  fi
done
# Curated manifest: no .env, mailu.env, backup.env, certificates, or mail data.
files=(.env.example mailu.env.example backup.env.example docker-compose.yml
  README.md BACKUPS.md UPGRADE.md AI_SUMMARY.md CHANGELOG.md
  webmail.sh upgrade.sh
  roundcube/zz-local.php proxy/default.conf
  tools/backup-restic.sh tools/test_local_smtp.py tools/list_strato_folders.py
  examples/SPAM_REJECT.sieve)
for f in "${files[@]}"; do
  [[ -f "$source_dir/$f" ]] || { echo "Missing packaged $f" >&2; exit 2; }
  mkdir -p "$target/$(dirname "$f")"
  cp -p "$source_dir/$f" "$target/$f"
done
chmod 755 "$target/webmail.sh" "$target/upgrade.sh" "$target/tools/backup-restic.sh"
chmod 600 "$target/.env" "$target/mailu.env"
[[ -e "$target/backup.env" ]] && chmod 600 "$target/backup.env"
echo "Package files updated in $target"
echo "Previous config and scripts saved (CONTAINS SECRETS): $snapshot"
echo 'Existing .env, mailu.env, backup.env, mailbox data and certificates were NOT overwritten.'
echo 'IMPORTANT: local modifications to roundcube/zz-local.php and docker-compose.yml were backed up and replaced.'
echo "NEXT: $target/webmail.sh prepare"
echo "      $target/webmail.sh config-check"
echo "      $target/webmail.sh apply"
echo 'Read UPGRADE.md before proceeding; a first-time persistent session key may require logging in again.'
