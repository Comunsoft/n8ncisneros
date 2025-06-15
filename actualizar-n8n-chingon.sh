#!/bin/bash
set -e

logfile="/var/log/actualizar-n8n.log"
exec > >(tee -a "$logfile") 2>&1

echo "🧠 [$(date)] Iniciando script de actualización de n8n nivel Chuck Norris..."

# Verifica Docker
if ! command -v docker &>/dev/null; then
  echo "🐳 Docker no está instalado. Instalando Docker..."
  apt update -y
  apt install -y ca-certificates curl gnupg lsb-release
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt update -y
  apt install -y docker-ce docker-ce-cli containerd.io
else
  echo "✅ Docker ya está instalado."
fi

# Verifica Docker Compose plugin
if ! docker compose version &>/dev/null; then
  echo "🧩 Docker Compose plugin no encontrado. Instalando..."
  mkdir -p ~/.docker/cli-plugins
  curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
    -o ~/.docker/cli-plugins/docker-compose
  chmod +x ~/.docker/cli-plugins/docker-compose
else
  echo "✅ Docker Compose plugin ya está disponible."
fi

# Validar carpeta con docker-compose.yml
if [ ! -f /opt/n8n/docker-compose.yml ]; then
  echo "❌ No se encontró docker-compose.yml en /opt/n8n. Abortando."
  exit 1
fi

cd /opt/n8n
echo "📁 Entrando a /opt/n8n..."

# Backup del volumen de n8n
container_name=$(docker ps -qf "name=n8n")
if [ -z "$container_name" ]; then
  echo "⚠️ Contenedor n8n no está corriendo. Continuando con precaución..."
  container_name="n8n-app"
fi

echo "💾 Haciendo backup del volumen de n8n..."
mkdir -p ~/backups-n8n
docker run --rm --volumes-from "$container_name" -v ~/backups-n8n:/backup ubuntu \
  tar czf /backup/n8n-backup-$(date +%F_%H-%M).tar.gz /home/node/.n8n || echo "⚠️ Backup falló pero continuamos."

# Actualizar imagen de n8n
echo "⬇️ Descargando nueva imagen de n8n..."
docker compose pull

# Reiniciar contenedor
echo "🛑 Apagando contenedor antiguo..."
docker compose down

echo "🚀 Levantando nueva versión de n8n..."
docker compose up -d

# Verificar versión actual
echo "🔍 Verificando versión instalada de n8n..."
docker exec -it $(docker ps -qf "name=n8n") n8n --version || echo "⚠️ No se pudo obtener versión."

# Mostrar estado
echo "📦 Estado actual del contenedor:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo "✅ Actualización completa. Revisa el log: $logfile"
