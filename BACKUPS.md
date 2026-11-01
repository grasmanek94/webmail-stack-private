# Encrypted off-Pi backups with restic (optional; configure later)

This is a *prepared but inactive* feature. It does not contact the main server until configured and invoked. All backup content is encrypted client-side on the Raspberry Pi before upload to the main server. Backups include mail, spam database, credentials, and application configuration. STRATO continues receiving internet email during the brief stop for consistency, so incoming mail is not lost due to our backup operation; fetching resumes afterward.

## Destination setup (on your main server)

1. Create a dedicated, restricted backup account with SSH/SFTP access to an appropriate storage directory; don't reuse a personal shell account. Restrict accessible directories and network sources if possible. In this example the repository is `/srv/backups/webmail-restic`.
2. Prefer append-only storage, server-side snapshots or a separate immutable backup to protect against deletion by a compromised Pi. restic encryption protects confidentiality, **not** deletion by an account that can modify its repository.
3. Give the Pi an SSH key and test `sftp mailbackup@MAIN-SERVER` before initializing restic. Store the destination in a filesystem with sufficient space and monitoring.

## Raspberry Pi setup

```bash
sudo apt update && sudo apt install restic
sudo install -d -m 700 /root/.config/webmail
# Generate and copy a dedicated SSH key (example shown; configure authorized_keys on server):
sudo ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519_webmail_backup -C 'webmail-restic'
# Then configure /root/.ssh/config to use that key for MAIN-SERVER.
cp backup.env.example backup.env
chmod 600 backup.env
# EDIT backup.env with the actual SFTP endpoint and password-file path.
# Create a long, random restic repository passphrase and preserve an OFF-PI copy.
sudo sh -c 'umask 077; openssl rand -base64 48 > /root/.config/webmail/restic-password'
chmod 600 /root/.config/webmail/restic-password
./webmail.sh backup-remote-init
./webmail.sh backup-remote
./webmail.sh backup-remote-list
./webmail.sh backup-remote-check
```

Use `sudo` consistently if you initialized under root. The helper does NOT schedule backups or prune snapshots by default. After testing one complete restoration to a test directory, create a systemd timer or cron job to execute `./webmail.sh backup-remote` at an appropriate interval. Choose a conservative retention policy separately (`restic forget --keep-daily 14 --keep-weekly 8 --keep-monthly 12 --prune`). Do not configure `forget --prune` without first verifying the repository and remote storage limits. Stop/restart means users temporarily cannot access the self-hosted mailbox during a backup, while STRATO still accepts new mail.

**Do not lose the restic repository passphrase.** Without it your backups cannot be decrypted. Anyone with root access to your Pi while it is running could access your cleartext mailbox and credentials; backup encryption only protects the remote copy.

## Restore rehearsal (on a secure test computer)

Configure restic credentials, then:

```bash
restic snapshots
restic restore latest --target /tmp/webmail-restore-test
```

Check that the restored paths include the host data tree and project configuration. Never restore directly over a running mail stack, and never paste secrets or restored config content into chats.

## Local archive command is different

`./webmail.sh backup` still creates an **UNENCRYPTED** tarball at `$DATA_ROOT/backups/`, intended only for short-term local recovery. Do not copy those archives to your shared server unless you encrypt them first. `backup-remote` instead uses restic end-to-end encryption.
