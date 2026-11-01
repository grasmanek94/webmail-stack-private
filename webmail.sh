#!/usr/bin/env bash
# STRATO-backed Mailu / Roundcube stack manager.
set -Eeuo pipefail
umask 077
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

say(){ printf '\n==> %s\n' "$*"; }
warn(){ printf 'WARNING: %s\n' "$*" >&2; }
die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "Missing program: $1"; }

load_env(){
  [[ -f .env ]] || die "Missing .env; run: ./webmail.sh install"
  # Only literal KEY=VALUE pairs, not shell code.
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" == *=* ]] || die "Bad line in .env: $line"
    local k="${line%%=*}" v="${line#*=}"
    [[ "$k" =~ ^[A-Z][A-Z0-9_]*$ ]] || die "Bad .env key: $k"
    export "$k=$v"
  done < .env
  export DATA_ROOT="${DATA_ROOT:-/srv/webmail}"
  export MAIL_DOMAIN="${MAIL_DOMAIN:-example.nl}" LOCAL_MAILBOX="${LOCAL_MAILBOX:-r@example.nl}"
  export MAIL_HOSTNAME="${MAIL_HOSTNAME:-mailhome.example.nl}" LAN_IP="${LAN_IP:-127.0.0.1}"
  [[ "$DATA_ROOT" = /* && "$DATA_ROOT" != / ]] || die "DATA_ROOT must be an absolute non-root path"
  [[ "$DATA_ROOT" != *'/../'* && "$DATA_ROOT" != */.. && "$DATA_ROOT" != *'/./'* ]] || die "DATA_ROOT cannot contain .. or . segments"
  if [[ -n "${DATA_DISK_MOUNT:-}" ]]; then
    need mountpoint
    mountpoint -q "${DATA_DISK_MOUNT}" || die "Required data volume is NOT mounted at ${DATA_DISK_MOUNT}. Refusing to write to the SD card."
    case "${DATA_ROOT}/" in "${DATA_DISK_MOUNT%/}/"*) ;; *) die "DATA_ROOT must be under DATA_DISK_MOUNT";; esac
  fi
  [[ "$MAIL_DOMAIN" =~ ^[a-zA-Z0-9.-]+$ ]] || die "Invalid MAIL_DOMAIN"
  [[ "$MAIL_HOSTNAME" =~ ^[a-zA-Z0-9.-]+$ ]] || die "Invalid MAIL_HOSTNAME"
  [[ "$LOCAL_MAILBOX" =~ ^[a-zA-Z0-9._+-]+@[a-zA-Z0-9.-]+$ ]] || die "Invalid LOCAL_MAILBOX"
  [[ "${LOCAL_MAILBOX#*@}" == "$MAIL_DOMAIN" ]] || die "LOCAL_MAILBOX must be in MAIL_DOMAIN"
}
compose(){ docker compose --project-directory "$HERE" -f "$HERE/docker-compose.yml" "$@"; }
check_docker(){
  need docker
  docker compose version >/dev/null 2>&1 || die "Docker Compose v2 is required (docker compose)."
  docker info >/dev/null 2>&1 || die "Docker daemon unavailable. Add your user to the docker group or run with sudo."
}
ensure_dirs(){
  local d
  mkdir -p "$DATA_ROOT"
  # Own just the top-level and initial directories. Do NOT recursively chown
  # running mail data: internal container services have their own UID/GIDs.
  if [[ $(id -u) -eq 0 ]] && getent passwd "${OWNER_USER:-root}" >/dev/null && getent group "${OWNER_GROUP:-root}" >/dev/null; then
    chown "${OWNER_USER:-root}:${OWNER_GROUP:-root}" "$DATA_ROOT"
  elif ! getent passwd "${OWNER_USER:-root}" >/dev/null; then
    warn "Owner ${OWNER_USER:-root} not found; leaving host directory ownership untouched."
  fi
  for d in certs data dkim mail mailqueue filter redis roundcube roundcube/db overrides overrides/nginx overrides/dovecot overrides/postfix overrides/rspamd backups; do
    mkdir -p "$DATA_ROOT/$d"
  done
  chmod 700 "$DATA_ROOT/certs" "$DATA_ROOT/backups" || true
}
install_env(){
  if [[ ! -f .env ]]; then
    cp .env.example .env
    local found=""
    if command -v ip >/dev/null; then
      found="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}' || true)"
    fi
    if [[ -n "$found" && "$found" =~ ^[0-9.]+$ ]]; then
      sed -i "s/^LAN_IP=.*/LAN_IP=$found/" .env
    fi
    say "Created .env (review DATA_ROOT, MAIL_HOSTNAME, LAN_IP and ports)."
  fi
  chmod 600 .env
}
configure(){
  need python3
  [[ ! -f mailu.env ]] || die "Mailu is already initialized. Changing DATA_ROOT now could orphan your mail. Migrate carefully instead."
  install_env
  load_env
  local chosen="${1:-}"
  if [[ -z "$chosen" ]]; then
    read -r -p "Persistent DATA_ROOT [${DATA_ROOT}]: " chosen
    chosen="${chosen:-$DATA_ROOT}"
  fi
  [[ "$chosen" = /* && "$chosen" != / && "$chosen" =~ ^/[a-zA-Z0-9_./-]+$ ]] || die "Use a simple absolute path without spaces (e.g. /srv/webmail or /mnt/ssd/webmail)"
  [[ "$chosen" != *'/../'* && "$chosen" != */.. && "$chosen" != *'/./'* ]] || die "Invalid path traversal"
  CHOSEN_ROOT="$chosen" python3 - <<'PYCONFIG'
import os
from pathlib import Path
p=Path('.env')
s=p.read_text()
s='\n'.join('DATA_ROOT='+os.environ['CHOSEN_ROOT'] if line.startswith('DATA_ROOT=') else line for line in s.splitlines())+'\n'
p.write_text(s)
PYCONFIG
  chmod 600 .env
  say "Persistent data configured at $chosen"
  say "Review .env (especially DATA_DISK_MOUNT for SSDs) and then run ./webmail.sh install"
}
# Set a single simple .env value without sourcing arbitrary shell code.
set_dotenv_key(){
  need python3
  local k="$1" v="$2"
  DOTENV_KEY="$k" DOTENV_VALUE="$v" python3 - <<'PYDOTENV'
import os
from pathlib import Path
p=Path('.env'); k=os.environ['DOTENV_KEY']; v=os.environ['DOTENV_VALUE']
assert k.isupper() and k.replace('_','').isalnum()
assert all(c.isalnum() or c in '._-/@' for c in v), 'Unsafe value'
lines=p.read_text().splitlines()
updated=False
out=[]
for line in lines:
    if line.startswith(k+'='):
        if not updated: out.append(k+'='+v); updated=True
    else: out.append(line)
if not updated: out.append(k+'='+v)
p.write_text('\n'.join(out)+'\n')
PYDOTENV
  chmod 600 .env
}
ensure_roundcube_key(){
  [[ -f .env ]] || die 'Missing .env; run install first.'
  local current
  current="$(grep -m1 '^ROUNDCUBE_DES_KEY=' .env | cut -d= -f2- || true)"
  if [[ -n "$current" ]]; then
    [[ ${#current} -ge 24 ]] || die 'Existing ROUNDCUBE_DES_KEY is too short; refusing silent rotation.'
    return 0
  fi
  need openssl
  local generated; generated="$(openssl rand -hex 16)"
  set_dotenv_key ROUNDCUBE_DES_KEY "$generated"
  say 'Created stable Roundcube session encryption key in .env (mode 600).'
  warn 'If you previously ran without a persistent key, existing web sessions may need one fresh login.'
}
prepare(){
  [[ -f .env && -f mailu.env ]] || die 'Missing .env or mailu.env; use install on a fresh deployment.'
  load_env; ensure_roundcube_key; load_env
}
valid_service(){
  case "$1" in redis|resolver|front|admin|imap|smtp|antispam|fetchmail|roundcube|web) ;; *) die "Unknown service: $1";; esac
}
service_recreate(){
  [[ $# -eq 1 ]] || die 'Usage: ./webmail.sh recreate SERVICE'
  valid_service "$1"; prepare; check_docker
  compose config -q
  compose up -d --no-deps --force-recreate "$1"
}
service_restart(){
  [[ $# -eq 1 ]] || die 'Usage: ./webmail.sh restart-service SERVICE'
  valid_service "$1"; load_env; check_docker
  compose restart "$1"
}
# Apply changed compose/config; recreate Roundcube to reload custom PHP and session key.
apply(){
  prepare; check_docker
  compose config -q
  compose up -d
  compose up -d --no-deps --force-recreate roundcube
  say 'Applied configuration. Roundcube was recreated; other services stay running unless their config changed.'
}
set_attachments(){
  [[ $# -eq 1 && "$1" =~ ^[0-9]+$ ]] || die 'Usage: ./webmail.sh attachments NUMBER_MB (1..30)'
  (( 10#$1 >= 1 && 10#$1 <= 30 )) || die 'Use 1..30 MB; Mailu message limit is 50 MB including MIME overhead.'
  prepare; set_dotenv_key ROUNDCUBE_UPLOAD_LIMIT "$((10#$1))M"
  say "Roundcube upload limit set to $1 MB."
  if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then service_recreate roundcube; else warn 'Run ./webmail.sh apply when Docker is available.'; fi
}
set_fetch_interval(){
  [[ $# -eq 1 && "$1" =~ ^[0-9]+$ ]] || die 'Usage: ./webmail.sh fetch-interval SECONDS (60..3600)'
  (( 10#$1 >= 60 && 10#$1 <= 3600 )) || die 'Use 60..3600 seconds to avoid hammering STRATO.'
  load_env; [[ -f mailu.env ]] || die 'Run install first.'
  set_env_key FETCHMAIL_DELAY "$((10#$1))"
  say "Fetchmail polling interval set to $1 seconds."
  if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then service_recreate fetchmail; else warn 'Run ./webmail.sh recreate fetchmail when Docker is available.'; fi
}
set_reply_policy(){
  [[ $# -eq 1 ]] || die 'Usage: ./webmail.sh reply-policy first-to|delivery-first'
  local rules
  case "$1" in
    first-to) rules='To=d;Cc=d;X-Original-To=d;Envelope-To=d;Delivered-To=d' ;;
    delivery-first) rules='X-Original-To=d;Envelope-To=d;Delivered-To=d;To=d;Cc=d' ;;
    *) die 'Choose first-to or delivery-first' ;;
  esac
  need python3
  REPLY_RULES="$rules" python3 - <<'PYREPLY'
import os,re
from pathlib import Path
p=Path('roundcube/zz-local.php')
s=p.read_text()
pat=r"(?m)^\$config\['custom_from_header_rules'\]\s*=.*;$"
matches=re.findall(pat,s)
if len(matches)!=1:
    raise SystemExit('Expected exactly one custom_from_header_rules setting; edit/resolve manually.')
p.with_suffix('.php.previous').write_text(s)
s=re.sub(pat,lambda _: "$config['custom_from_header_rules'] = '"+os.environ['REPLY_RULES']+"';",s)
p.write_text(s)
PYREPLY
  say "Reply selection mode set: $1"
  service_recreate roundcube
}
check_alias(){
  [[ $# -eq 1 ]] || die 'Usage: ./webmail.sh alias-check address@domain'
  load_env; check_docker
  [[ "$1" =~ ^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.-]+$ && "${1#*@}" == "$MAIL_DOMAIN" ]] || die 'Address must be valid and in your own domain.'
  say "Mailu alias lookup for $1"
  compose exec -T smtp postmap -q "$1" socketmap:unix:/tmp/podop.socket:alias
}
logs_once(){
  load_env; check_docker
  local service="${1:-}" lines="${2:-100}"
  [[ "$lines" =~ ^[0-9]+$ ]] && (( lines>=1 && lines<=5000 )) || die 'Lines must be 1..5000'
  if [[ -n "$service" ]]; then valid_service "$service"; compose logs --tail="$lines" "$service"; else compose logs --tail="$lines"; fi
}
config_backup(){
  load_env; ensure_dirs; need tar
  local out="$DATA_ROOT/backups/webmail-config-$(date -u +%Y%m%dT%H%M%SZ).tar.gz"
  local files=(.env mailu.env docker-compose.yml webmail.sh roundcube proxy tools)
  [[ -f backup.env ]] && files+=(backup.env)
  tar -czf "$out" -C "$HERE" "${files[@]}"
  chmod 600 "$out"
  say "Sensitive config snapshot written: $out (UNENCRYPTED, contains credentials)."
}
write_mailu_env(){
  need python3
  # Keep existing env if installed; never overwrite secrets on update.
  [[ -f mailu.env ]] && return
  cp mailu.env.example mailu.env
  local secret; secret="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
  MAILU_RANDOM_SECRET="$secret" python3 - <<'PY'
import os
from pathlib import Path
p=Path('mailu.env'); s=p.read_text()
replacements={
    'SECRET_KEY':'SECRET_KEY='+os.environ['MAILU_RANDOM_SECRET'],
    'DOMAIN':'DOMAIN='+os.environ['MAIL_DOMAIN'],
    'SUBNET':'SUBNET='+os.environ.get('MAILU_SUBNET','192.168.203.0/24'),
    'HOSTNAMES':'HOSTNAMES='+os.environ['MAIL_HOSTNAME'],
    'POSTMASTER':'POSTMASTER='+os.environ['LOCAL_MAILBOX'].split('@')[0],
    'RELAYUSER':'RELAYUSER='+os.environ['LOCAL_MAILBOX'],
    'DMARC_RUA':'DMARC_RUA='+os.environ['LOCAL_MAILBOX'].split('@')[0],
    'DMARC_RUF':'DMARC_RUF='+os.environ['LOCAL_MAILBOX'].split('@')[0],
    'WEBSITE':'WEBSITE=https://'+os.environ['MAIL_HOSTNAME'],
    'WILDCARD_SENDERS':'WILDCARD_SENDERS='+os.environ['LOCAL_MAILBOX'],
}
s='\n'.join(replacements.get(line.split('=',1)[0],line) for line in s.splitlines())+'\n'
p.write_text(s)
PY
  chmod 600 mailu.env
  say "Created mailu.env with random SECRET_KEY."
}
set_env_key(){
  local key="$1" value="$2"
  KEY="$key" VALUE="$value" python3 - <<'PY'
import os,re
from pathlib import Path
key=os.environ['KEY']; val=os.environ['VALUE']
if '\n' in val or '\r' in val: raise SystemExit('No newlines permitted in values')
# Compose env_file: single quoted strings are literal, preventing $ interpolation.
if not re.fullmatch(r'[A-Za-z0-9_.@!%+=:/\[\]-]*',val):
    val="'"+val.replace('\\','\\\\').replace("'","\\'")+"'"
p=Path('mailu.env'); lines=p.read_text().splitlines()
lines=[(key+'='+val if l.startswith(key+'=') else l) for l in lines]
if not any(l.startswith(key+'=') for l in lines): lines.append(key+'='+val)
p.write_text('\n'.join(lines)+'\n')
PY
  chmod 600 mailu.env
}
make_cert(){
  need openssl
  local cert="$DATA_ROOT/certs/cert.pem" key="$DATA_ROOT/certs/key.pem"
  if [[ -s "$cert" && -s "$key" ]]; then
    return
  fi
  [[ ! -e "$cert" && ! -e "$key" ]] || die "Incomplete cert/key pair; fix files manually or use cert-install."
  local san="DNS:${MAIL_HOSTNAME},IP:127.0.0.1"
  [[ "$LAN_IP" =~ ^[0-9.]+$ ]] && san="$san,IP:$LAN_IP"
  say "Generating a self-signed TLS certificate (NOT publicly trusted)."
  openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 365 \
    -keyout "$key" -out "$cert" -subj "/CN=${MAIL_HOSTNAME}" \
    -addext "subjectAltName=${san}" >/dev/null 2>&1
  chmod 600 "$key"; chmod 644 "$cert"
}
relay(){
  load_env
  [[ -f mailu.env ]] || die "Run install first."
  read -rs -p 'STRATO SMTP password for the relay (will be stored in mailu.env): ' password; echo
  [[ -n "$password" ]] || die "Empty password; no changes made."
  set_env_key RELAYPASSWORD "$password"
  unset password
  say "Stored relay password in mailu.env (mode 600)."
  if docker compose version >/dev/null 2>&1 && compose ps -q smtp | grep -q .; then
    say "Restarting SMTP service to apply relay credentials."
    compose up -d --force-recreate smtp
  fi
}
admin_create(){
  load_env; check_docker
  local localpart="${LOCAL_MAILBOX%@*}" domain="${LOCAL_MAILBOX#*@}" p1 p2
  read -rs -p "New LOCAL mailbox/admin password for ${LOCAL_MAILBOX}: " p1; echo
  read -rs -p 'Confirm local password: ' p2; echo
  [[ -n "$p1" && "$p1" = "$p2" ]] || die "Password missing or mismatch."
  [[ ${#p1} -ge 12 ]] || die "Use at least 12 characters."
  # Password temporarily passed as a process argument to Mailu's CLI.
  compose exec -T admin flask mailu admin "$localpart" "$domain" "$p1"
  unset p1 p2
  say "Local admin account created. STRATO mailbox password is a DIFFERENT credential."
}
cert_install(){
  load_env; ensure_dirs; need openssl
  [[ $# -eq 2 ]] || die "Usage: ./webmail.sh cert-install /path/fullchain.pem /path/privkey.pem"
  [[ -s "$1" && -s "$2" ]] || die "Certificate/key files missing or empty."
  local a b; a="$(openssl x509 -in "$1" -pubkey -noout | openssl pkey -pubin -outform DER | sha256sum | awk '{print $1}')"
  b="$(openssl pkey -in "$2" -pubout -outform DER 2>/dev/null | sha256sum | awk '{print $1}')"
  [[ "$a" = "$b" ]] || die "Certificate and private key do not match."
  cp "$DATA_ROOT/certs/cert.pem" "$DATA_ROOT/certs/cert.previous.pem" 2>/dev/null || true
  cp "$DATA_ROOT/certs/key.pem" "$DATA_ROOT/certs/key.previous.pem" 2>/dev/null || true
  install -m 644 "$1" "$DATA_ROOT/certs/cert.pem"
  install -m 600 "$2" "$DATA_ROOT/certs/key.pem"
  if docker compose version >/dev/null 2>&1; then compose restart front web; fi
  say "Certificate replaced; use a trusted certificate for WAN exposure."
}
backup(){
  load_env; check_docker; ensure_dirs
  local out="$DATA_ROOT/backups/webmail-$(date -u +%Y%m%dT%H%M%SZ).tar.gz"
  say "Stopping containers for a CONSISTENT backup (mail will remain at STRATO)."
  compose stop
  # Always restore running service, even if archiving fails.
  trap 'compose up -d' EXIT
  tar -czf "$out" -C "$DATA_ROOT" --exclude='./backups' .
  chmod 600 "$out"
  say "Data backup created at: $out"
  say "Keep a separate copy of stack files .env, mailu.env and docker-compose.yml."
  compose up -d
  trap - EXIT
}
doctor(){
  prepare; check_docker
  say "Docker Compose configuration"
  compose config -q
  say "Listening ports (not proof of firewall/NAT access)"
  compose ps || true
  if [[ -f "$DATA_ROOT/certs/cert.pem" ]]; then
    say "Installed TLS certificate"
    openssl x509 -in "$DATA_ROOT/certs/cert.pem" -noout -subject -dates
  fi
  say "Data root: $DATA_ROOT"
  if grep -Eq '^ROUNDCUBE_DES_KEY=.{24,}$' .env; then
    say 'Roundcube persistent encryption key: configured (value hidden)'
  else
    warn 'Roundcube persistent encryption key appears missing/invalid.'
  fi
  say "Roundcube upload limit: ${ROUNDCUBE_UPLOAD_LIMIT:-30M}"
  if [[ -f mailu.env ]]; then
    say "Fetchmail interval: $(grep -m1 '^FETCHMAIL_DELAY=' mailu.env | cut -d= -f2- || true) seconds"
  fi
  if [[ -n "${DATA_DISK_MOUNT:-}" ]]; then say "Required data mount: $DATA_DISK_MOUNT (mounted)"; fi
  df -h "$DATA_ROOT" 2>/dev/null || true
  say "Current public inbound MX remains STRATO; TCP/25 is NOT published."
  if [[ -f mailu.env ]] && grep -q '^RELAYPASSWORD=$' mailu.env; then warn 'STRATO relay password is not configured; run: ./webmail.sh relay'; fi
  if [[ "${BIND_IP:-0.0.0.0}" == '0.0.0.0' ]]; then
    warn 'Services listen on all host IPv4 interfaces. Verify your firewall and router before WAN use.'
  fi
  say "Reminder: test arbitrary From through LOCAL Mailu SMTP, not only directly through STRATO."
}
usage(){
  cat <<'EOF'
Usage: ./webmail.sh <command>
  configure [PATH]   Before first install, set DATA_ROOT (defaults to /srv/webmail)
  install            Prepare storage/config/cert and start stack; leaves STRATO MX untouched
  update             Pull images and apply project Compose changes (preserves data)
  prepare            Ensure persistent Roundcube encryption key exists
  apply              Apply local Compose/config changes; recreate Roundcube
  recreate SERVICE   Force-recreate one service (roundcube, fetchmail, smtp, ...)
  restart-service S  Restart exactly one service
  attachments MB     Set max Roundcube attachment size (1..30 MB; default 30)
  fetch-interval SEC Configure STRATO fetch polling seconds (60..3600)
  reply-policy MODE  Set first-to (default) or delivery-first auto From selection
  alias-check ADDRESS Check Mailu catch-all alias lookup via Postfix
  smtp-test          Test arbitrary sender via local Mailu SMTP (interactive)
  strato-folders     List IMAP folders at STRATO (interactive, read-only)
  logs-once [S] [N]  Print last N log lines without following them
  config-backup      Save a local protected (UNENCRYPTED) config snapshot
  start | stop       Start or stop containers
  restart            Restart services
  status             Show container status
  logs [service]     Follow all or one service log (Ctrl-C to leave)
  doctor             Validate Compose and report deployment details
  admin-create       Create the LOCAL r@example.nl admin/mail account (interactive)
  relay              Enter/change STRATO SMTP password (interactive, stored mode 600)
  cert-install C K   Install existing PEM certificate/fullchain and private key
  backup             Stop, archive persistent data LOCALLY (UNENCRYPTED), and restart
  backup-remote-init  Initialize encrypted restic SFTP repository (after backup.env setup)
  backup-remote      Stop, back up data + configs encrypted via restic, restart
  backup-remote-list List restic snapshots without stopping the stack
  backup-remote-check Verify encrypted repository structure
  config-check      Validate Compose without printing secrets
  config            Alias for config-check (no secrets printed)
  help               Print this help

Quick start: ./webmail.sh install; ./webmail.sh admin-create; ./webmail.sh relay
Then log into https://SERVER_IP:8443/admin and configure a fetched IMAP account.
See README.md for critical first-run and WAN safety steps.
EOF
}
cmd="${1:-help}"; shift || true
case "$cmd" in
  configure) configure "${1:-}" ;;
  install)
    check_docker; need openssl; need python3; need tar
    install_env; load_env; ensure_dirs; write_mailu_env; ensure_roundcube_key; make_cert
    say "Validating Compose file"
    compose config -q
    say "Pulling Docker images and starting services"
    compose pull
    compose up -d
    say "WEBMAIL: https://<SERVER_IP>:${WEB_HTTPS_PORT:-443}  |  ADMIN: https://<SERVER_IP>:${ADMIN_HTTPS_PORT:-8443}/admin"
    say "NEXT: ./webmail.sh admin-create ; ./webmail.sh relay ; configure fetched STRATO IMAP account in admin UI"
    warn "Generated TLS certificate is self-signed. Don't expose to WAN until you install a trusted cert and firewall harden."
    ;;
  prepare) prepare ;;
  apply) apply ;;
  update) prepare; check_docker; compose config -q; compose pull; compose up -d; compose up -d --no-deps --force-recreate roundcube; say 'Images updated and config applied. Review release notes before major version upgrades.' ;;
  start) prepare; check_docker; compose up -d ;;
  stop) load_env; check_docker; compose stop ;;
  restart) prepare; check_docker; compose restart ;;
  status) load_env; check_docker; compose ps ;;
  recreate) service_recreate "$@" ;;
  restart-service) service_restart "$@" ;;
  attachments) set_attachments "$@" ;;
  fetch-interval) set_fetch_interval "$@" ;;
  reply-policy) set_reply_policy "$@" ;;
  alias-check) check_alias "$@" ;;
  smtp-test) load_env; need python3; python3 "$HERE/tools/test_local_smtp.py" ;;
  strato-folders) need python3; python3 "$HERE/tools/list_strato_folders.py" ;;
  logs-once) logs_once "$@" ;;
  config-backup) config_backup ;;
  logs) load_env; check_docker; if [[ $# -gt 0 ]]; then [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]] || die 'Invalid service'; compose logs -f --tail=100 "$1"; else compose logs -f --tail=100; fi ;;
  doctor) doctor ;;
  admin-create) admin_create ;;
  relay) relay ;;
  cert-install) cert_install "$@" ;;
  backup) backup ;;
  backup-remote-init) load_env; check_docker; exec "$HERE/tools/backup-restic.sh" init "$HERE" "$DATA_ROOT" ;;
  backup-remote) load_env; check_docker; "$HERE/tools/backup-restic.sh" backup "$HERE" "$DATA_ROOT" ;;
  backup-remote-list) load_env; "$HERE/tools/backup-restic.sh" snapshots "$HERE" "$DATA_ROOT" ;;
  backup-remote-check) load_env; "$HERE/tools/backup-restic.sh" check "$HERE" "$DATA_ROOT" ;;
  config|config-check) prepare; check_docker; compose config -q; say "Compose configuration valid (no secrets printed)." ;;
  help|-h|--help) usage ;;
  *) usage; exit 2 ;;
esac
