#!/usr/bin/env bash
set -euo pipefail

# === Config ===
HOSTS_FILE="/etc/hosts"
BACKUP_PREFIX="/etc/hosts.gta-battleye-backup"
DOMAINS=(
  "paradise-s1.battleye.com"
  "test-s1.battleye.com"
  "paradiseenhanced-s1.battleye.com"
)
IP_BLOCK="0.0.0.0"

# === Logging ===
log()  { printf '[INFO] %s\n' "$*" >&2; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
err()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

# === Root check ===
require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "Ce script doit être exécuté en root (sudo)."
  fi
}

# === OS detection (pour nsswitch hint seulement) ===
detect_os() {
  case "$(uname -s)" in
    Linux)  echo "linux" ;;
    Darwin) echo "macos" ;;
    CYGWIN*|MINGW*|MSYS*) echo "windows-like" ;;
    *) echo "unknown" ;;
  esac
}

# === /etc/hosts backup ===
backup_hosts() {
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  local backup="${BACKUP_PREFIX}-${ts}"
  cp "${HOSTS_FILE}" "${backup}"
  log "Backup créé: ${backup}"
}

# === nsswitch sanity check (Linux) ===
check_nsswitch() {
  local os
  os="$(detect_os)"

  if [ "${os}" != "linux" ]; then
    return 0
  fi

  if [ ! -f /etc/nsswitch.conf ]; then
    warn "/etc/nsswitch.conf introuvable, impossible de vérifier l'ordre de résolution (hosts)."
    return 0
  fi

  local line
  line="$(grep -E '^[[:space:]]*hosts:' /etc/nsswitch.conf || true)"

  if [ -z "${line}" ]; then
    warn "Aucune ligne 'hosts:' trouvée dans /etc/nsswitch.conf, comportement de résolution non standard."
    return 0
  fi

  local pos_files pos_dns
  pos_files="$(echo "${line}" | awk '{for (i=1;i<=NF;i++) if ($i=="files") print i}')"
  pos_dns="$(echo "${line}" | awk '{for (i=1;i<=NF;i++) if ($i=="dns") print i}')"

  if [ -n "${pos_dns}" ] && [ -n "${pos_files}" ]; then
    if [ "${pos_dns}" -lt "${pos_files}" ]; then
      warn "Dans /etc/nsswitch.conf, 'dns' apparaît avant 'files' pour 'hosts:'."
      warn "Dans cette config, /etc/hosts peut ne pas être prioritaire. Vérifie ta résolution si ça ne fonctionne pas."
    fi
  fi
}

# === Helpers /etc/hosts ===
contains_domain_line() {
  local domain="$1"
  grep -qE "^[[:space:]]*${IP_BLOCK}[[:space:]]+${domain}([[:space:]]|\$)" "${HOSTS_FILE}"
}

any_domain_present() {
  for d in "${DOMAINS[@]}"; do
    if grep -q "${d}" "${HOSTS_FILE}"; then
      return 0
    fi
  done
  return 1
}

apply_rules() {
  log "Application des règles Battleye dans ${HOSTS_FILE}..."

  backup_hosts
  check_nsswitch

  local added=0
  for d in "${DOMAINS[@]}"; do
    if contains_domain_line "${d}"; then
      log "Entrée déjà présente pour ${d}, on ne modifie pas."
    else
      # Si une entrée existe avec une autre IP, on la commente
      if grep -q "${d}" "${HOSTS_FILE}"; then
        log "Une entrée existe déjà pour ${d} avec une IP différente, on la commente."
        sed -i.bak "/${d}/ s/^/# GTA-BE-OLD # /" "${HOSTS_FILE}"
      fi
      printf '%s %s\n' "${IP_BLOCK}" "${d}" >> "${HOSTS_FILE}"
      log "Ajout: ${IP_BLOCK} ${d}"
      added=1
    fi
  done

  if [ "${added}" -eq 0 ]; then
    log "Aucune nouvelle entrée ajoutée. Tout était déjà en place."
  else
    log "Règles Battleye ajoutées. Redémarre le jeu pour prendre en compte les changements."
  fi
}

remove_rules() {
  log "Suppression des règles Battleye dans ${HOSTS_FILE}..."

  if ! any_domain_present; then
    log "Aucune entrée liée aux domaines Battleye n'a été trouvée, rien à faire."
    return 0
  fi

  backup_hosts

  local pattern
  pattern="$(printf '%s|' "${DOMAINS[@]}")"
  pattern="${pattern%|}"

  sed -i.bak "/${pattern}/d" "${HOSTS_FILE}"
  log "Entrées pour Battleye supprimées de ${HOSTS_FILE}."
  log "Si besoin, tu peux revenir à un backup: ${BACKUP_PREFIX}-YYYYMMDD-HHMMSS"
}

# === Détection Proton BattlEye Runtime ===
find_runtime_path() {
  local candidates=(
    "$HOME/.local/share/Steam/steamapps/common/Proton BattlEye Runtime"
    "$HOME/.steam/steam/steamapps/common/Proton BattlEye Runtime"
    "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/common/Proton BattlEye Runtime"
    "/home/deck/.local/share/Steam/steamapps/common/Proton BattlEye Runtime"
  )

  for p in "${candidates[@]}"; do
    if [ -d "$p" ]; then
      echo "$p"
      return 0
    fi
  done

  echo ""
  return 1
}

# === Helper texte (Steam / Heroic / Lutris) ===
print_steam_instructions() {
  local launch_line="$1"
  local version_choice="$2"

  printf '>>> STEAM – Options de lancement GTA V\n\n'
  printf '1. Ouvre Steam\n'
  printf '2. Va dans ta bibliothèque de jeux\n'

  if [ "$version_choice" = "1" ] || [ "$version_choice" = "3" ]; then
    printf '\n[Legacy]\n'
    printf '  - Clic droit sur "Grand Theft Auto V"\n'
    printf '  - "Propriétés..."\n'
    printf '  - Dans "Options de lancement", colle cette ligne :\n\n'
    printf '      %s\n\n' "$launch_line"
  fi

  if [ "$version_choice" = "2" ] || [ "$version_choice" = "3" ]; then
    printf '\n[Enhanced]\n'
    printf '  - Clic droit sur "Grand Theft Auto V Enhanced"\n'
    printf '  - "Propriétés..."\n'
    printf '  - Dans "Options de lancement", colle cette ligne :\n\n'
    printf '      %s\n\n' "$launch_line"
  fi
}

print_heroic_instructions() {
  local runtime_path="$1"

  printf '>>> HEROIC – Variables d’environnement / arguments\n\n'
  printf '1. Ouvre Heroic\n'
  printf '2. Sélectionne GTA V dans ta bibliothèque\n'
  printf '3. Ouvre les paramètres du jeu (Settings)\n'
  printf '4. Ajoute la variable d’environnement suivante :\n\n'
  printf '   PROTON_BATTLEYE_RUNTIME=\"%s\"\n\n' "$runtime_path"
  printf '5. Assure-toi d’utiliser Proton/Wine compatible dans Heroic.\n'
}

print_lutris_instructions() {
  local runtime_path="$1"

  printf '>>> LUTRIS – Variables d’environnement\n\n'
  printf '1. Ouvre Lutris\n'
  printf '2. Clic droit sur GTA V -> \"Configurer\"\n'
  printf '3. Onglet \"Système\" / \"Game options\" (selon version)\n'
  printf '4. Dans \"Variables d’environnement\", ajoute :\n\n'
  printf '   PROTON_BATTLEYE_RUNTIME=\"%s\"\n\n' "$runtime_path"
}

print_generic_instructions() {
  local runtime_path="$1"

  printf '>>> AUTRE LAUNCHER – Variable d’environnement générique\n\n'
  printf 'Ajoute une variable d’environnement au lancement du jeu :\n\n'
  printf '   PROTON_BATTLEYE_RUNTIME=\"%s\"\n\n' "$runtime_path"
  printf 'Reportez-vous à la documentation de votre launcher pour savoir où définir des variables d’environnement.\n'
}

helper_mode() {
  log "Assistant de configuration Proton BattlEye Runtime (aucune modification système)."

  runtime_path="$(find_runtime_path || true)"

  if [ -z "$runtime_path" ]; then
    warn "Proton BattlEye Runtime introuvable sur ce système."
    cat <<'EOF'
[Action requise]

Installe Proton BattlEye Runtime dans Steam :

  1. Ouvre Steam
  2. Library -> Tools
  3. Cherche "Proton BattlEye Runtime"
  4. Clique sur Install

Ensuite relance :

  sudo ./gta-battleye-hosts.sh full
EOF
    return 0
  fi

  log "Proton BattlEye Runtime détecté : $runtime_path"

  printf '\nTu utilises quel launcher pour GTA V ?\n'
  printf '  1) Steam\n'
  printf '  2) Heroic\n'
  printf '  3) Lutris\n'
  printf '  4) Autre\n'
  read -rp 'Choix [1-4] : ' launcher

  printf '\nTu joues à quelle(s) version(s) ?\n'
  printf '  1) Legacy seulement\n'
  printf '  2) Enhanced seulement\n'
  printf '  3) Legacy + Enhanced\n'
  read -rp 'Choix [1-3] : ' version_choice

  read -rp $'\nEs-tu sur Steam Deck ? [y/N] : ' is_deck
  is_deck="${is_deck:-N}"

  local prefix=""
  if [[ "$is_deck" =~ ^[Yy]$ ]]; then
    prefix="SteamDeck=0 "
  fi

  local base_opt
  base_opt=${prefix}"PROTON_BATTLEYE_RUNTIME=\"${runtime_path}\" %command%"

  printf '\n=============================\n'
  printf '         INSTRUCTIONS\n'
  printf '=============================\n\n'

  case "$launcher" in
    1)
      print_steam_instructions "$base_opt" "$version_choice"
      ;;
    2)
      print_heroic_instructions "$runtime_path"
      ;;
    3)
      print_lutris_instructions "$runtime_path"
      ;;
    *)
      print_generic_instructions "$runtime_path"
      ;;
  esac

  printf '\nIMPORTANT : Lance d’abord le mode Histoire, puis rejoins une session privée (invite-only / friends-only) pour GTA Online.\n'
}

print_usage() {
  cat >&2 <<EOF
Usage: $0 [apply|remove|full]

  apply   : ajoute uniquement les entrées /etc/hosts pour bloquer les domaines Battleye.
  remove  : supprime ces entrées du fichier hosts.
  full    : applique les règles /etc/hosts PUIS lance l'assistant
            pour configurer Proton BattlEye Runtime (Steam / Heroic / Lutris).

Exemples:

  sudo $0 apply
  sudo $0 remove
  sudo $0 full
EOF
}

# === Main ===
ACTION="${1:-}"

if [ -z "${ACTION}" ]; then
  print_usage
  exit 1
fi

case "${ACTION}" in
  apply)
    require_root
    [ -f "${HOSTS_FILE}" ] || err "Fichier ${HOSTS_FILE} introuvable."
    apply_rules
    ;;
  remove)
    require_root
    [ -f "${HOSTS_FILE}" ] || err "Fichier ${HOSTS_FILE} introuvable."
    remove_rules
    ;;
  full)
    require_root
    [ -f "${HOSTS_FILE}" ] || err "Fichier ${HOSTS_FILE} introuvable."
    apply_rules
    printf '\n--- Étape suivante : configuration du launcher / Proton BattlEye Runtime ---\n\n'
    # helper ensuite sans exiger root (non nécessaire pour le reste)
    # on relance le script en user normal si possible
    sudo -u "$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")" bash "$0" _helper-internal || helper_mode
    ;;
  _helper-internal)
    # mode interne pour relancer en user classique
    helper_mode
    ;;
  *)
    print_usage
    exit 1
    ;;
esac