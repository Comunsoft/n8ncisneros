#!/bin/bash
set -e

# ========================== CONFIG ==========================
N8N_IMAGE="n8nio/n8n:latest"
N8N_DIR="/root/n8n"
SCRIPT_DIR="/root/scripts"
BACKUP_DIR="$N8N_DIR/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/var/log/n8n-auto-update.log"
COMPOSE_FILE="$N8N_DIR/docker-compose.yml"
CRON_TAG="# n8n-auto-update"

mkdir -p "$SCRIPT_DIR" "$BACKUP_DIR"
echo "\n================ $(date) ================\n" >> "$LOG_FILE"

# ========================== DEPENDENCIAS ==========================
echo "🔧 Verificando dependencias..." | tee -a "$LOG_FILE"
if ! command -v docker &>/dev/null; then
  echo "🐳 Instalando Docker..." | tee -a "$LOG_FILE"
  apt update && apt install -y docker.io
  systemctl enable docker --now
fi

if ! docker compose version &>/dev/null; then
  echo "📦 Instalando Docker Compose Plugin..." | tee -a "$LOG_FILE"
  apt install -y docker-compose-plugin
fi

# ========================== DETECTAR INSTALACIÓN ACTIVA ==========================
echo "🔍 Buscando contenedor n8n..." | tee -a "$LOG_FILE"
N8N_CONTAINER=$(docker ps --filter ancestor=$N8N_IMAGE --format "{{.Names}}" | head -n 1)

if [[ -n "$N8N_CONTAINER" ]]; then
  echo "✅ Instalación detectada: $N8N_CONTAINER" | tee -a "$LOG_FILE"
  BACKUP_PATH="$BACKUP_DIR/backup_$TIMESTAMP.tar.gz"
  echo "💾 Haciendo backup en $BACKUP_PATH..." | tee -a "$LOG_FILE"
  mkdir -p "/tmp/n8n_backup_$TIMESTAMP"
  docker cp "$N8N_CONTAINER":/home/node/.n8n "/tmp/n8n_backup_$TIMESTAMP/config"
  tar -czf "$BACKUP_PATH" -C "/tmp" "n8n_backup_$TIMESTAMP"
  rm -rf "/tmp/n8n_backup_$TIMESTAMP"

  echo "⬇️ Actualizando imagen..." | tee -a "$LOG_FILE"
  CURRENT_ID=$(docker inspect --format='{{.Image}}' "$N8N_CONTAINER")
  docker pull $N8N_IMAGE > /dev/null
  NEW_ID=$(docker image inspect $N8N_IMAGE --format='{{.Id}}')

  if [[ "$CURRENT_ID" != "$NEW_ID" ]]; then
    echo "🔁 Imagen nueva detectada. Actualizando..." | tee -a "$LOG_FILE"
    cd "$N8N_DIR"
    docker compose down
    docker compose up -d
  else
    echo "⚠️ Ya tienes la última versión. No se actualiza." | tee -a "$LOG_FILE"
  fi
else
  echo "🚫 No se detectó instalación activa. Buscando backup para restaurar..." | tee -a "$LOG_FILE"
  LAST_BACKUP=$(ls -t $BACKUP_DIR/*.tar.gz 2>/dev/null | head -n 1)

  if [[ -f "$LAST_BACKUP" ]]; then
    echo "🗂️ Restaurando desde backup: $LAST_BACKUP" | tee -a "$LOG_FILE"
    mkdir -p "$N8N_DIR"
    echo "🧱 Generando docker-compose.yml..." | tee -a "$LOG_FILE"
    cat <<EOF2 > "$COMPOSE_FILE"
version: '3.7'
services:
  n8n:
    image: $N8N_IMAGE
    ports:
      - "5678:5678"
    volumes:
      - $N8N_DIR/data:/home/node/.n8n
    restart: always
EOF2

    echo "🚀 Levantando servicio por primera vez..." | tee -a "$LOG_FILE"
    docker compose -f "$COMPOSE_FILE" up -d
    sleep 5
    docker compose -f "$COMPOSE_FILE" down

    echo "📦 Restaurando backup..." | tee -a "$LOG_FILE"
    tar -xzf "$LAST_BACKUP" -C "/tmp"
    cp -r "/tmp/n8n_backup_"*/config/* "$N8N_DIR/data/"
    rm -rf "/tmp/n8n_backup_"*

    echo "🔁 Levantando instancia restaurada..." | tee -a "$LOG_FILE"
    docker compose -f "$COMPOSE_FILE" up -d
  else
    echo "📦 No se encontró backup. Instalando limpio..." | tee -a "$LOG_FILE"
    mkdir -p "$N8N_DIR/data"
    cat <<EOF3 > "$COMPOSE_FILE"
version: '3.7'
services:
  n8n:
    image: $N8N_IMAGE
    ports:
      - "5678:5678"
    volumes:
      - $N8N_DIR/data:/home/node/.n8n
    restart: always
EOF3
    docker compose -f "$COMPOSE_FILE" up -d
  fi
fi

# ========================== PROGRAMAR CRON ==========================
echo "📅 Verificando programación en cron..." | tee -a "$LOG_FILE"
if ! crontab -l 2>/dev/null | grep -q "$CRON_TAG"; then
  echo "🧠 Agregando tarea en cron para actualización cada 3 días..." | tee -a "$LOG_FILE"
  (crontab -l 2>/dev/null; echo "0 4 * * * [[ \$(( (\$(date +\%-d) - 1) % 3 )) -eq 0 ]] && $SCRIPT_DIR/$(basename $0) >> $LOG_FILE 2>&1 $CRON_TAG") | crontab -
else
  echo "📌 Cron ya configurado." | tee -a "$LOG_FILE"
fi

# ========================== FINAL ==========================
echo "✅ Proceso terminado. Verifica en http://localhost:5678" | tee -a "$LOG_FILE"
