#!/usr/bin/env bash
# OPTIONAL: restic backup over SFTP. See BACKUPS.md before use.
set -Eeuo pipefail
umask 077
cmd="${1:?operation required}"; project="${2:?project path required}"; root="${3:?data path required}"
cd "$project"
die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
command -v restic >/dev/null || die 'Install restic on this Pi first: sudo apt install restic'
[[ -f backup.env ]] || die 'Create protected backup.env from backup.env.example; see BACKUPS.md'
# Read limited KEY=VALUE values only; do not execute shell statements.
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  [[ "$line" == *=* ]] || die 'Invalid line in backup.env'
  key="${line%%=*}"; val="${line#*=}"
  case "$key" in RESTIC_REPOSITORY|RESTIC_PASSWORD_FILE) export "$key=$val" ;; *) die "Unexpected backup.env key: $key";; esac
done < backup.env
[[ -n "${RESTIC_REPOSITORY:-}" && -n "${RESTIC_PASSWORD_FILE:-}" ]] || die 'Missing RESTIC_REPOSITORY / RESTIC_PASSWORD_FILE'
[[ "$(stat -c %a backup.env)" =~ ^(400|600)$ ]] || die 'backup.env must have mode 400 or 600'
[[ "$RESTIC_REPOSITORY" == sftp:* ]] || die 'Only encrypted restic-over-SFTP repositories are enabled in this helper'
[[ -s "$RESTIC_PASSWORD_FILE" ]] || die 'Missing/empty local restic password file'
[[ "$(stat -c %a "$RESTIC_PASSWORD_FILE")" =~ ^(400|600)$ ]] || die 'Passphrase file must have mode 400 or 600'
case "$cmd" in
  init)
    printf 'Initializing remote encrypted restic repo %s\n' "$RESTIC_REPOSITORY"
    restic init
    ;;
  snapshots)
    restic snapshots
    ;;
  check)
    restic check
    ;;
  backup)
    command -v docker >/dev/null || die 'Docker missing'
    printf 'Stopping webmail briefly for a consistent encrypted backup...\n'
    docker compose --project-directory "$project" -f "$project/docker-compose.yml" stop
    restart(){ docker compose --project-directory "$project" -f "$project/docker-compose.yml" up -d; }
    trap restart EXIT
    restic backup --tag webmail --exclude "$root/backups" "$root" "$project"
    printf 'Backup uploaded and encrypted by restic. Restarting services.\n'
    restart
    trap - EXIT
    ;;
  *) die "Unknown restic action: $cmd" ;;
esac
