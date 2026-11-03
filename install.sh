#!/usr/bin/env bash
# Erstinstallation einer Seite auf einer frischen Ubuntu-Instanz.
#
#   Als root ausführen:  bash install.sh <seite>
#
# Ablauf: Git + Deploy-Key einrichten → Repo (nur scripts/ + sites/<seite>/)
# nach /opt/web-workbench holen → alle Migrationen ab Version 0 ausführen.
# Danach aktualisiert ein einfaches `wwb-update` die Instanz.
set -euo pipefail

SITE="${1:?Nutzung: bash install.sh <seite>}"
REPO="${WWB_REPO:-git@github.com:TyraelN/web-workbench.git}"
DIR="${WWB_DIR:-/opt/web-workbench}"
KEY=/root/.ssh/web-workbench_deploy

log() { echo -e "\033[1;34m[install]\033[0m $*"; }
[ "$(id -u)" -eq 0 ] || { echo "Bitte als root ausführen" >&2; exit 1; }

log "Pakete: git, rsync, curl, gpg"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq git rsync curl gpg ca-certificates openssh-client >/dev/null

SSH_CMD=""
if [[ "$REPO" == git@* ]]; then
  install -d -m 700 /root/.ssh
  [ -f "$KEY" ] || ssh-keygen -q -t ed25519 -N "" -C "web-workbench@$(hostname)" -f "$KEY"
  SSH_CMD="ssh -i $KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
  export GIT_SSH_COMMAND="$SSH_CMD"
  until git ls-remote "$REPO" >/dev/null 2>&1; do
    echo
    echo "Diesen Deploy-Key bei GitHub eintragen:"
    echo "  github.com/TyraelN/web-workbench → Settings → Deploy keys → Add deploy key"
    echo "  (Titel: $(hostname), 'Allow write access' NICHT anhaken)"
    echo
    cat "$KEY.pub"
    echo
    read -rp "Eingetragen? Enter drücken … " _ </dev/tty
  done
fi

if [ ! -d "$DIR/.git" ]; then
  log "Repo holen → $DIR"
  git clone -q --depth 1 --filter=blob:none --sparse "$REPO" "$DIR"
  git -C "$DIR" sparse-checkout set scripts
  [ -n "$SSH_CMD" ] && git -C "$DIR" config core.sshCommand "$SSH_CMD"
fi
git -C "$DIR" sparse-checkout add "sites/$SITE"
[ -d "$DIR/sites/$SITE" ] || { echo "Seite '$SITE' gibt es im Repo nicht" >&2; exit 1; }

install -d /etc/web-workbench
echo "$SITE" > /etc/web-workbench/site
ln -sf "$DIR/scripts/update.sh" /usr/local/sbin/wwb-update

log "Migrationen ausführen"
exec bash "$DIR/scripts/update.sh" "$SITE" --no-pull
