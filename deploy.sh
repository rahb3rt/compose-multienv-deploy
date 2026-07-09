#!/bin/bash
set -euo pipefail

# ══════════════════════════════════════════════════════════════════════════════
# Multi-Environment Compose Platform — Multi-Environment Compose Deploy
# ══════════════════════════════════════════════════════════════════════════════
# Pulls repos, pre-builds Next.js apps, generates nginx config, then
# runs docker/podman compose to build images and start everything.
#
# Supports multiple isolated environments on the same host:
#   ./deploy.sh --env production
#   ./deploy.sh --env staging
#   ./deploy.sh --env customer-acme
#
# Each environment gets its own .env file, network, containers, and volumes.

# ─── Colors ───
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
DIM='\033[2m'
RESET='\033[0m'

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLATFORM_DIR="$(cd "$(dirname "$0")" && pwd)"
FORCE=false
SERVICES=()
ENV_NAME=""

# ─── Parse args ───
usage() {
  cat <<'HELP'
┌─────────────────────────────────────────────────────────┐
│    Multi-Environment Compose Platform Deploy (multi-environment)      │
└─────────────────────────────────────────────────────────┘

USAGE
  ./deploy.sh [options] [service ...]

OPTIONS
  --env, -e <name>  Deploy to a named environment (default: uses .env)
                    Each env gets its own network, containers, and volumes.
                    Reads config from .env.<name> (e.g. .env.staging)
  --force, -f       Force rebuild with --no-cache
  --list            List all running environments and their containers
  --status [name]   Show container status for an environment
  --stop <name>     Stop an environment (keeps containers)
  --down <name>     Tear down an environment (removes containers, keeps data)
  --nuke <name>     Destroy an environment AND its data volumes (asks confirmation)
  --help, -h        Show this help

SERVICES (compose service names)
  mysql minio mail payments extractor email kiosk api
  app web sms health monitoring nginx backup

ENVIRONMENTS
  Each --env creates a fully isolated stack:
    - Network:    <env>           (e.g. "staging")
    - Containers: <env>-api       (e.g. "staging-api")
    - Volumes:    <env>-mysql-data (e.g. "staging-mysql-data")
    - Config:     .env.<name>     (e.g. .env.staging)

  Without --env, uses .env and the default "platform" namespace.

EXAMPLES
  Default deploy (production):
    ./deploy.sh

  Deploy staging environment:
    ./deploy.sh --env staging

  Force rebuild staging api:
    ./deploy.sh --env staging --force api

  Deploy a customer environment:
    cp .env.example .env.acme-platform    # customize ports/domains
    ./deploy.sh --env acme-platform

  List all running environments:
    ./deploy.sh --list

  Check status of an environment:
    ./deploy.sh --status staging

  Stop / tear down / destroy:
    ./deploy.sh --stop staging               # pause (keeps containers)
    ./deploy.sh --down staging               # remove containers (keeps data)
    ./deploy.sh --nuke staging               # remove everything incl. database

HELP
  exit 0
}

# Parse all args (handle --env <value> pair)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env|-e)
      ENV_NAME="$2"
      shift 2
      ;;
    --force|-f)
      FORCE=true
      shift
      ;;
    --list)
      echo ""
      echo -e "${BLUE}Running environments:${RESET}"
      RT=$(command -v podman &>/dev/null && echo podman || echo docker)
      for net in $($RT network ls --format '{{.Name}}' 2>/dev/null); do
        containers=$($RT ps --filter "network=$net" --format '{{.Names}}' 2>/dev/null)
        count=$(echo "$containers" | grep -c . 2>/dev/null || echo 0)
        if [[ $count -gt 0 ]]; then
          echo -e "  ${GREEN}$net${RESET} — $count containers"
          echo "$containers" | sed "s/^/    ${DIM}/"
          echo -e "${RESET}"
        fi
      done
      echo ""
      exit 0
      ;;
    --status)
      # Show status for a specific or all environments
      shift
      if [[ $# -gt 0 ]]; then
        export COMPOSE_PROJECT_NAME="$1"
      fi
      COMPOSE_TMP=""
      if podman compose version &>/dev/null 2>&1; then COMPOSE_TMP="podman compose";
      elif command -v podman-compose &>/dev/null; then COMPOSE_TMP="podman-compose";
      elif docker compose version &>/dev/null 2>&1; then COMPOSE_TMP="docker compose";
      fi
      $COMPOSE_TMP -f "$(cd "$(dirname "$0")" && pwd)/docker-compose.yml" ps
      exit 0
      ;;
    --stop)
      # Stop an environment without removing it
      shift
      if [[ $# -gt 0 ]]; then
        export COMPOSE_PROJECT_NAME="$1"
        echo -e "${YELLOW}Stopping environment: $1${RESET}"
      else
        echo -e "${RED}Usage: ./deploy.sh --stop <env-name>${RESET}"
        exit 1
      fi
      COMPOSE_TMP=""
      if podman compose version &>/dev/null 2>&1; then COMPOSE_TMP="podman compose";
      elif command -v podman-compose &>/dev/null; then COMPOSE_TMP="podman-compose";
      elif docker compose version &>/dev/null 2>&1; then COMPOSE_TMP="docker compose";
      fi
      $COMPOSE_TMP -f "$(cd "$(dirname "$0")" && pwd)/docker-compose.yml" stop
      exit 0
      ;;
    --down)
      # Tear down an environment (containers + network, keeps volumes)
      shift
      if [[ $# -gt 0 ]]; then
        export COMPOSE_PROJECT_NAME="$1"
        echo -e "${RED}Tearing down environment: $1${RESET}"
      else
        echo -e "${RED}Usage: ./deploy.sh --down <env-name>${RESET}"
        exit 1
      fi
      COMPOSE_TMP=""
      if podman compose version &>/dev/null 2>&1; then COMPOSE_TMP="podman compose";
      elif command -v podman-compose &>/dev/null; then COMPOSE_TMP="podman-compose";
      elif docker compose version &>/dev/null 2>&1; then COMPOSE_TMP="docker compose";
      fi
      $COMPOSE_TMP -f "$(cd "$(dirname "$0")" && pwd)/docker-compose.yml" down
      exit 0
      ;;
    --nuke)
      # Tear down an environment AND delete its volumes
      shift
      if [[ $# -gt 0 ]]; then
        export COMPOSE_PROJECT_NAME="$1"
        echo -e "${RED}DESTROYING environment: $1 (including data volumes)${RESET}"
        read -p "  Are you sure? [y/N] " confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && exit 0
      else
        echo -e "${RED}Usage: ./deploy.sh --nuke <env-name>${RESET}"
        exit 1
      fi
      COMPOSE_TMP=""
      if podman compose version &>/dev/null 2>&1; then COMPOSE_TMP="podman compose";
      elif command -v podman-compose &>/dev/null; then COMPOSE_TMP="podman-compose";
      elif docker compose version &>/dev/null 2>&1; then COMPOSE_TMP="docker compose";
      fi
      $COMPOSE_TMP -f "$(cd "$(dirname "$0")" && pwd)/docker-compose.yml" down -v
      exit 0
      ;;
    --help|-h)
      usage
      ;;
    *)
      SERVICES+=("$1")
      shift
      ;;
  esac
done

# ─── Helpers (defined early so env setup can use them) ───
log()     { echo -e "${BLUE}==>${RESET} $1"; }
success() { echo -e "    ${GREEN}✔${RESET} $1"; }
skip()    { echo -e "    ${YELLOW}—${RESET} $1 ${DIM}(no changes)${RESET}"; }
fail()    { echo -e "    ${RED}✘${RESET} $1"; }

# ─── Resolve env file ───
if [[ -n "$ENV_NAME" ]]; then
  ENV_FILE="$PLATFORM_DIR/.env.${ENV_NAME}"
  COMPOSE_PROJECT="$ENV_NAME"
else
  ENV_FILE="$PLATFORM_DIR/.env"
  COMPOSE_PROJECT="platform"
fi

# Auto-generate or update .env.<name> with available ports
if [[ -n "$ENV_NAME" ]]; then

  # Check if a port is free
  _port_free() {
    ! ss -tlnH "sport = :$1" 2>/dev/null | grep -q ":$1 " && \
    ! grep -rh "^PORT_.*=$1$" "$PLATFORM_DIR"/.env "$PLATFORM_DIR"/.env.* 2>/dev/null | grep -qv "\.env\.${ENV_NAME}:"
  }

  # Find next free port starting from a base, skipping taken ones
  _find_free() {
    local port="$1"
    while ! _port_free "$port"; do
      port=$((port + 1))
    done
    echo "$port"
  }

  if [[ ! -f "$ENV_FILE" ]]; then
    # Create from production .env or .env.example
    if [[ -f "$PLATFORM_DIR/.env" ]]; then
      SOURCE_ENV="$PLATFORM_DIR/.env"
    elif [[ -f "$PLATFORM_DIR/.env.example" ]]; then
      SOURCE_ENV="$PLATFORM_DIR/.env.example"
    else
      echo -e "${RED}ERROR: No .env or .env.example to generate from${RESET}"
      exit 1
    fi
    log "Creating .env.${ENV_NAME} from $(basename "$SOURCE_ENV")"
    cp "$SOURCE_ENV" "$ENV_FILE"

    # Update origins/domains to include env name
    sed -i "s|^APP_ORIGIN=.*|APP_ORIGIN=https://${ENV_NAME}-app.example.com|" "$ENV_FILE"
    sed -i "s|^API_ORIGIN=.*|API_ORIGIN=https://${ENV_NAME}-api.example.com|" "$ENV_FILE"
    sed -i "s|^EMAIL_ORIGIN=.*|EMAIL_ORIGIN=https://${ENV_NAME}-email.example.com|" "$ENV_FILE"
    sed -i "s|^GOOGLE_REDIRECT_URI=.*|GOOGLE_REDIRECT_URI=https://${ENV_NAME}-email.example.com/oauth2callback|" "$ENV_FILE"

    # Set a unique database name
    sed -i "s|^MYSQL_DATABASE=.*|MYSQL_DATABASE=${ENV_NAME//-/_}|" "$ENV_FILE"
  fi

  # Update or set a port var — keep existing value if already assigned and free
  _set_port() {
    local key="$1" base="$2"
    local current=""
    # Read existing value if set
    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
      current=$(grep "^${key}=" "$ENV_FILE" | tail -1 | cut -d= -f2)
    fi
    # Keep current if it's still free
    if [[ -n "$current" ]] && _port_free "$current"; then
      return
    fi
    # Find a free port starting from the base
    local port
    port=$(_find_free "$base")
    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
      sed -i "s|^${key}=.*|${key}=${port}|" "$ENV_FILE"
    else
      echo "${key}=${port}" >> "$ENV_FILE"
    fi
  }

  log "Assigning ports for ${ENV_NAME}"

  # Start scanning from offset range so envs don't cluster on the same ports
  HASH=$(echo -n "$ENV_NAME" | cksum | awk '{print $1}')
  PORT_OFFSET=$(( (HASH % 9 + 1) * 100 ))

  _set_port PORT_MYSQL        $((6603 + PORT_OFFSET))
  _set_port PORT_MINIO_API    $((5003 + PORT_OFFSET))
  _set_port PORT_MINIO_CONSOLE $((5004 + PORT_OFFSET))
  _set_port PORT_MAIL         $((5007 + PORT_OFFSET))
  _set_port PORT_VENMO        $((5006 + PORT_OFFSET))
  _set_port PORT_EXTRACTOR    $((5010 + PORT_OFFSET))
  _set_port PORT_EMAIL        $((5008 + PORT_OFFSET))
  _set_port PORT_KIOSK        $((5009 + PORT_OFFSET))
  _set_port PORT_API          $((5002 + PORT_OFFSET))
  _set_port PORT_SMS          $((5013 + PORT_OFFSET))
  _set_port PORT_APP          $((3000 + PORT_OFFSET))
  _set_port PORT_WEB          $((5015 + PORT_OFFSET))
  _set_port PORT_HEALTH       $((5011 + PORT_OFFSET))
  _set_port PORT_MONITORING   $((5014 + PORT_OFFSET))
  _set_port PORT_HTTP         $((8100 + PORT_OFFSET))
  _set_port PORT_HTTPS        $((8443 + PORT_OFFSET))
  _set_port PORT_HEALTH_HTTP  $((8080 + PORT_OFFSET))

  # Ensure REPOS_DIR and NGINX_DIR are set (critical for compose build paths)
  _set_var() {
    local key="$1" val="$2"
    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
      : # already set, don't overwrite
    else
      echo "${key}=${val}" >> "$ENV_FILE"
    fi
  }
  _set_var REPOS_DIR ..
  _set_var NGINX_DIR ../nginx

  # Show assigned ports
  source "$ENV_FILE"
  success "ports assigned for ${ENV_NAME}"
  echo -e "    ${DIM}API: ${PORT_API}  App: ${PORT_APP}  MySQL: ${PORT_MYSQL}  HTTP: ${PORT_HTTP}${RESET}"
  echo ""
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo -e "${RED}ERROR: Missing env file: $ENV_FILE${RESET}"
  echo "  cp .env.example .env   # then fill in your secrets"
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

# Export compose project name so all containers/networks/volumes are namespaced
export COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT"

# ─── Find compose command ───
COMPOSE=""
if podman compose version &>/dev/null 2>&1; then
  COMPOSE="podman compose"
elif command -v podman-compose &>/dev/null; then
  COMPOSE="podman-compose"
elif docker compose version &>/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v docker-compose &>/dev/null; then
  COMPOSE="docker-compose"
else
  echo -e "${RED}ERROR: No compose tool found. Install podman compose or docker compose.${RESET}"
  exit 1
fi

should_deploy() {
  [[ ${#SERVICES[@]} -eq 0 ]] && return 0
  for s in "${SERVICES[@]}"; do [[ "$s" == "$1" ]] && return 0; done
  return 1
}

# ─── Header ───
echo ""
echo -e "${BLUE}Multi-Environment Compose Platform Deploy${RESET} — $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "  Environment: ${GREEN}$COMPOSE_PROJECT${RESET}"
echo -e "  Env file:    $ENV_FILE"
echo -e "  Compose:     $COMPOSE"
echo -e "  Base:        $BASE_DIR"
if $FORCE; then echo -e "  ${YELLOW}Force rebuild enabled${RESET}"; fi
if [[ ${#SERVICES[@]} -gt 0 ]]; then echo -e "  Services:    ${SERVICES[*]}"; fi
echo ""

# ─── Service → repo directory + git remote mapping ───
declare -A REPO_MAP=(
  [mail]=mail
  [payments]=payments
  [extractor]=extractor
  [email]=email
  [kiosk]=kiosk
  [api]=api
  [app]=next-app
  [web]=web
  [health]=health
  [sms]=sms
  [monitoring]=monitoring
  [nginx]=nginx
)

declare -A GIT_MAP=(
  [mail]=git@github.com:rahb3rt/mail.git
  [payments]=git@github.com:rahb3rt/payments.git
  [extractor]=git@github.com:rahb3rt/extractor.git
  [email]=git@github.com:rahb3rt/email.git
  [kiosk]=git@github.com:rahb3rt/kiosk.git
  [api]=git@github.com:rahb3rt/api.git
  [app]=git@github.com:rahb3rt/next-app.git
  [web]=git@github.com:rahb3rt/website.git
  [health]=git@github.com:rahb3rt/health.git
  [sms]=git@github.com:rahb3rt/sms.git
  [monitoring]=git@github.com:rahb3rt/monitoring.git
  [nginx]=git@github.com:rahb3rt/nginx.git
)

# ─── Clone or pull repos ───
log "Syncing repos"
CHANGED=()
for svc in "${!REPO_MAP[@]}"; do
  should_deploy "$svc" || continue
  dir="${REPO_MAP[$svc]}"
  repo="${GIT_MAP[$svc]}"

  if [[ ! -d "$BASE_DIR/$dir" ]]; then
    printf "    cloning $svc... "
    if git clone --quiet "$repo" "$BASE_DIR/$dir" 2>/dev/null; then
      echo -e "${GREEN}done${RESET}"
      CHANGED+=("$svc")
    else
      echo -e "${RED}FAILED${RESET} ($repo)"
    fi
  elif [[ -d "$BASE_DIR/$dir/.git" ]]; then
    cd "$BASE_DIR/$dir"
    before=$(git rev-parse HEAD)
    git pull --quiet
    after=$(git rev-parse HEAD)

    if [[ "$before" != "$after" ]]; then
      CHANGED+=("$svc")
      success "$svc — new changes"
    else
      skip "$svc"
    fi
  else
    skip "$svc (not a git repo)"
  fi
done
echo ""

# ─── Database backup ───
if should_deploy "backup"; then
  log "Database backup"
  mkdir -p "$BASE_DIR/backups"
  local_backup="$BASE_DIR/backups/${COMPOSE_PROJECT}-$(date +%Y-%m-%d).sql"
  if [[ -f "$local_backup" ]]; then
    skip "backup already exists for today"
  else
    if mysqldump -u"$DB_USER" -p"$DB_PASSWORD" -h127.0.0.1 -P"${MYSQL_PORT:-6603}" "${MYSQL_DATABASE:-platform}" > "$local_backup" 2>/dev/null; then
      success "saved to ${DIM}$(basename "$local_backup")${RESET}"
    else
      skip "mysql not reachable (first deploy?)"
      rm -f "$local_backup"
    fi
  fi
  echo ""
fi

# ─── Pre-build (Next.js apps need npm install + build before Docker) ───
for svc in app monitoring web; do
  should_deploy "$svc" || continue
  dir="${REPO_MAP[$svc]}"

  is_changed=false
  for c in "${CHANGED[@]+"${CHANGED[@]}"}"; do [[ "$c" == "$svc" ]] && is_changed=true; done
  if ! $is_changed && ! $FORCE; then continue; fi

  log "Pre-building $svc"
  cd "$BASE_DIR/$dir"
  printf "    npm install... "
  npm install --silent 2>&1
  echo -e "${GREEN}done${RESET}"
  printf "    npm build... "
  npm run build 2>&1
  echo -e "${GREEN}done${RESET}"
done

# ─── Generate nginx config + certs ───
if should_deploy "nginx"; then
  NGINX_SRC="${NGINX_DIR:-$BASE_DIR/nginx}"
  log "Nginx setup"
  cd "$NGINX_SRC"

  # ── Generate self-signed certs for any missing cert pairs ──
  _ensure_cert() {
    local name="$1" domains="$2"
    local cert="$NGINX_SRC/${name}.pem"
    local key="$NGINX_SRC/${name}-key.pem"

    if [[ -f "$cert" && -f "$key" ]]; then
      skip "${name} certs exist"
      return
    fi

    # Build SAN string for multiple domains
    local san=""
    local i=1
    for d in $domains; do
      san="${san}DNS.${i} = ${d}\n"
      i=$((i + 1))
    done

    printf "    generating self-signed cert for ${name}... "
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -keyout "$key" -out "$cert" \
      -subj "/CN=${domains%% *}" \
      -addext "subjectAltName = $(echo "$domains" | sed 's/ /,DNS:/g; s/^/DNS:/')" \
      2>/dev/null
    echo -e "${GREEN}done${RESET}"
  }

  _ensure_cert "certificate"  "example.com app.example.com api.example.com email.example.com kiosk.example.com s3.example.com minio.example.com monitoring.example.com payment.example.com device-api.example.com"
  _ensure_cert "nomaderealty"  "nomaderealty.com www.nomaderealty.com crm.nomaderealty.com api.nomaderealty.com"
  _ensure_cert "supnewhaven"  "supnewhaven.com www.supnewhaven.com"

  # ── Generate config from template ──
  if [[ -f default.tmp ]]; then
    cp default.tmp default
    # Long placeholders FIRST (before short ones corrupt them)
    sed -i 's|SUPNEWHAVEN_WEB|host.containers.internal:5050|g' default
    sed -i 's|NOMADE_API|host.containers.internal:5020|g' default
    sed -i 's|NOMADE_CRM|host.containers.internal:5021|g' default
    sed -i 's|NOMADE_WEB|host.containers.internal:5022|g' default
    sed -i 's|NOMADE_MINIO|host.containers.internal:5030|g' default
    # Platform placeholders → compose service names
    sed -i \
      -e 's|http://APP:|http://app:|g' \
      -e 's|http://API:|http://api:|g' \
      -e 's|http://EMAIL:|http://email:|g' \
      -e 's|http://KIOSK:|http://kiosk:|g' \
      -e 's|http://EXTRACTOR:|http://extractor:|g' \
      -e 's|http://MONITORING:|http://monitoring:|g' \
      -e 's|http://MINIO:|http://minio:|g' \
      -e 's|http://WEB:|http://web:|g' \
      default
    success "nginx config generated"
  else
    fail "default.tmp not found in $NGINX_SRC"
  fi

  # ── Ensure 502 error page ──
  mkdir -p "$NGINX_SRC/html"
  if [[ ! -f "$NGINX_SRC/html/502.html" ]]; then
    if [[ -f "$NGINX_SRC/502.html" ]]; then
      cp -f "$NGINX_SRC/502.html" "$NGINX_SRC/html/502.html"
    else
      cat > "$NGINX_SRC/html/502.html" << 'HTML'
<!DOCTYPE html>
<html><head><title>Service Unavailable</title>
<style>body{font-family:system-ui;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;background:#f5f5f5;color:#333}
.c{text-align:center}h1{font-size:48px;margin:0}p{color:#666;margin-top:8px}</style></head>
<body><div class="c"><h1>502</h1><p>Service is starting up or temporarily unavailable.</p></div></body></html>
HTML
      success "created 502.html"
    fi
  fi

  echo ""
fi

# ─── Build + deploy with compose ───
cd "$PLATFORM_DIR"

COMPOSE_SERVICES=()
for s in "${SERVICES[@]+"${SERVICES[@]}"}"; do
  [[ "$s" != "backup" ]] && COMPOSE_SERVICES+=("$s")
done

BUILD_ARGS=()
if $FORCE; then
  BUILD_ARGS+=(--no-cache)
fi

COMPOSE_CMD="$COMPOSE --env-file $ENV_FILE -f docker-compose.yml"

if [[ ${#COMPOSE_SERVICES[@]} -gt 0 ]]; then
  log "Building and deploying: ${COMPOSE_SERVICES[*]}"
  $COMPOSE_CMD up -d --build "${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"}" "${COMPOSE_SERVICES[@]}"
elif [[ ${#SERVICES[@]} -eq 0 ]]; then
  log "Building and deploying all services"
  $COMPOSE_CMD up -d --build "${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"}"
fi

# ─── Cleanup dangling images ───
RT=$(command -v podman &>/dev/null && echo podman || echo docker)
DANGLING=$($RT image prune -f 2>/dev/null | grep -c "deleted" || echo 0)
if [[ "$DANGLING" -gt 0 ]]; then
  success "pruned $DANGLING dangling images"
fi

# ─── Summary ───
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "  Environment: ${GREEN}$COMPOSE_PROJECT${RESET}"
$COMPOSE_CMD ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || $COMPOSE_CMD ps
echo ""
echo -e "  ${DIM}Logs:     COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT $COMPOSE_CMD logs -f <service>${RESET}"
echo -e "  ${DIM}Restart:  COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT $COMPOSE_CMD restart <service>${RESET}"
echo -e "  ${DIM}Stop env: COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT $COMPOSE_CMD down${RESET}"
echo -e "  ${DIM}List all: ./deploy.sh --list${RESET}"
echo ""
