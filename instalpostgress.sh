#!/bin/bash

# Script de instalación completa de PostgreSQL en contenedor Docker
# Versión mejorada con validaciones adicionales y mejor manejo de errores
# Autor: Script automático interactivo

set -euo pipefail  # Salir en error, variables no definidas, o error en pipe

# Colores para output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Funciones de utilidad
print_header() {
    echo -e "${PURPLE}================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}================================${NC}"
}

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[ÉXITO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[ADVERTENCIA]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${CYAN}[PASO $1]${NC} $2"
}

# Función para limpiar en caso de error
cleanup() {
    print_error "Script interrumpido. Limpiando..."
    cd "$HOME" 2>/dev/null || true
    exit 1
}

# Configurar trap para cleanup
trap cleanup INT TERM

# Función para verificar si un puerto está libre
is_port_free() {
    local port=$1
    if command -v ss >/dev/null 2>&1; then
        ! ss -tuln | grep -q ":$port "
    elif command -v netstat >/dev/null 2>&1; then
        ! netstat -tuln | grep -q ":$port "
    else
        # Fallback usando lsof si está disponible
        if command -v lsof >/dev/null 2>&1; then
            ! lsof -i ":$port" >/dev/null 2>&1
        else
            return 0  # Asumir que está libre si no hay herramientas
        fi
    fi
}

# Función para encontrar un puerto libre
find_free_port() {
    local start_port=$1
    local current_port=$start_port
    
    while [ $current_port -le 65535 ]; do
        if is_port_free $current_port; then
            echo $current_port
            return 0
        fi
        current_port=$((current_port + 1))
    done
    
    return 1
}

# Función para verificar si un comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Función para validar entrada de usuario
validate_input() {
    local input="$1"
    local type="$2"
    
    case "$type" in
        "username")
            if [[ ! "$input" =~ ^[a-zA-Z][a-zA-Z0-9_]{2,31}$ ]]; then
                print_error "El usuario debe comenzar con letra, tener 3-32 caracteres y solo contener letras, números y guiones bajos"
                return 1
            fi
            ;;
        "password")
            if [[ ${#input} -lt 8 ]]; then
                print_error "La contraseña debe tener al menos 8 caracteres"
                return 1
            fi
            ;;
        "database")
            if [[ ! "$input" =~ ^[a-zA-Z][a-zA-Z0-9_]{2,63}$ ]]; then
                print_error "El nombre de la BD debe comenzar con letra, tener 3-64 caracteres y solo contener letras, números y guiones bajos"
                return 1
            fi
            ;;
    esac
    return 0
}

# Función para solicitar datos del usuario con validación
get_user_input() {
    local prompt="$1"
    local type="$2"
    local var_name="$3"
    local input=""
    local is_password=false
    
    if [[ "$type" == "password" ]]; then
        is_password=true
    fi
    
    while true; do
        if $is_password; then
            read -s -p "$prompt" input
            echo ""
        else
            read -p "$prompt" input
        fi
        
        if [[ -z "$input" ]]; then
            print_error "Este campo no puede estar vacío"
            continue
        fi
        
        if validate_input "$input" "$type"; then
            eval "$var_name='$input'"
            break
        fi
    done
}

# Función para detectar instalaciones previas
detect_previous_installation() {
    local found_previous=false
    local containers_found=()
    local projects_found=()
    
    print_status "Detectando instalaciones previas de PostgreSQL..."
    
    # Buscar contenedores PostgreSQL existentes
    if command_exists docker; then
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                containers_found+=("$line")
                found_previous=true
            fi
        done < <(docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | grep postgres | grep -v NAMES || true)
    fi
    
    # Buscar directorios de proyectos PostgreSQL
    local common_dirs=("$HOME/postgres-container" "$HOME/postgresql-docker" "$HOME/postgres-docker" "/opt/postgres-container")
    for dir in "${common_dirs[@]}"; do
        if [[ -d "$dir" && (-f "$dir/docker-compose.yml" || -f "$dir/.env") ]]; then
            projects_found+=("$dir")
            found_previous=true
        fi
    done
    
    # Buscar PostgreSQL nativo instalado
    local native_postgres=false
    if command_exists psql || systemctl is-active --quiet postgresql 2>/dev/null; then
        native_postgres=true
        found_previous=true
    fi
    
    if $found_previous; then
        print_warning "Se detectaron instalaciones previas de PostgreSQL:"
        echo ""
        
        if [[ ${#containers_found[@]} -gt 0 ]]; then
            echo "🐳 Contenedores Docker encontrados:"
            printf '%s\n' "${containers_found[@]}"
            echo ""
        fi
        
        if [[ ${#projects_found[@]} -gt 0 ]]; then
            echo "📁 Proyectos encontrados:"
            printf '   %s\n' "${projects_found[@]}"
            echo ""
        fi
        
        if $native_postgres; then
            echo "💾 PostgreSQL nativo detectado en el sistema"
            echo ""
        fi
        
        echo "⚠️  OPCIONES:"
        echo "   1) Limpiar todo y hacer instalación nueva"
        echo "   2) Continuar sin limpiar (puede causar conflictos)"
        echo "   3) Cancelar instalación"
        echo ""
        
        while true; do
            read -p "Selecciona una opción [1-3]: " choice
            case $choice in
                1)
                    clean_previous_installations "${containers_found[@]}" "${projects_found[@]}" $native_postgres
                    break
                    ;;
                2)
                    print_warning "Continuando sin limpiar instalaciones previas..."
                    break
                    ;;
                3)
                    print_warning "Instalación cancelada por el usuario"
                    exit 0
                    ;;
                *)
                    print_error "Opción inválida. Selecciona 1, 2 o 3."
                    ;;
            esac
        done
    else
        print_success "No se detectaron instalaciones previas"
    fi
}

# Función para limpiar instalaciones previas
clean_previous_installations() {
    local containers=("$@")
    local native_postgres=false
    
    # El último argumento indica si hay PostgreSQL nativo
    if [[ "${!#}" == "true" ]]; then
        native_postgres=true
        # Remover el último elemento del array
        unset 'containers[${#containers[@]}-1]'
    fi
    
    print_header "LIMPIANDO INSTALACIONES PREVIAS"
    
    # Limpiar contenedores Docker
    if command_exists docker && [[ ${#containers[@]} -gt 0 ]]; then
        print_status "Deteniendo y eliminando contenedores PostgreSQL..."
        
        # Obtener nombres de contenedores PostgreSQL
        local container_names
        container_names=$(docker ps -a --format "{{.Names}}" | grep -i postgres || true)
        
        if [[ -n "$container_names" ]]; then
            echo "$container_names" | while read -r container; do
                if [[ -n "$container" ]]; then
                    print_status "Eliminando contenedor: $container"
                    docker stop "$container" 2>/dev/null || true
                    docker rm "$container" 2>/dev/null || true
                fi
            done
        fi
        
        # Limpiar volúmenes PostgreSQL
        print_status "Limpiando volúmenes PostgreSQL..."
        docker volume ls -q | grep -i postgres | while read -r volume; do
            if [[ -n "$volume" ]]; then
                print_status "Eliminando volumen: $volume"
                docker volume rm "$volume" 2>/dev/null || true
            fi
        done
        
        # Limpiar imágenes PostgreSQL no utilizadas
        print_status "Limpiando imágenes PostgreSQL no utilizadas..."
        docker image prune -f >/dev/null 2>&1 || true
        
        print_success "Contenedores y volúmenes PostgreSQL eliminados"
    fi
    
    # Limpiar directorios de proyectos
    local common_dirs=("$HOME/postgres-container" "$HOME/postgresql-docker" "$HOME/postgres-docker" "/opt/postgres-container")
    for dir in "${common_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            print_status "¿Eliminar directorio $dir? (s/N): "
            read -p "" delete_dir
            if [[ "$delete_dir" =~ ^[sS]$ ]]; then
                print_status "Eliminando directorio: $dir"
                rm -rf "$dir"
                print_success "Directorio eliminado: $dir"
            else
                print_warning "Directorio conservado: $dir"
            fi
        fi
    done
    
    # Manejar PostgreSQL nativo
    if $native_postgres; then
        print_warning "PostgreSQL nativo detectado"
        echo "⚠️  Se detectó una instalación nativa de PostgreSQL en el sistema."
        echo "   Esto puede causar conflictos de puertos con el contenedor."
        echo ""
        echo "   Opciones:"
        echo "   1) Detener PostgreSQL nativo (recomendado)"
        echo "   2) Desinstalar PostgreSQL nativo completamente"
        echo "   3) Continuar sin cambios (usar puerto diferente)"
        echo ""
        
        while true; do
            read -p "Selecciona una opción [1-3]: " pg_choice
            case $pg_choice in
                1)
                    print_status "Deteniendo PostgreSQL nativo..."
                    systemctl stop postgresql 2>/dev/null || true
                    systemctl disable postgresql 2>/dev/null || true
                    print_success "PostgreSQL nativo detenido"
                    break
                    ;;
                2)
                    print_warning "⚠️  Esto eliminará completamente PostgreSQL y todos sus datos"
                    read -p "¿Estás seguro? (escriba 'SI' para confirmar): " confirm_remove
                    if [[ "$confirm_remove" == "SI" ]]; then
                        print_status "Desinstalando PostgreSQL nativo..."
                        systemctl stop postgresql 2>/dev/null || true
                        apt remove --purge postgresql* -y 2>/dev/null || true
                        rm -rf /var/lib/postgresql/ 2>/dev/null || true
                        rm -rf /etc/postgresql/ 2>/dev/null || true
                        print_success "PostgreSQL nativo desinstalado"
                    else
                        print_warning "Desinstalación cancelada"
                    fi
                    break
                    ;;
                3)
                    print_warning "PostgreSQL nativo conservado. Se usará un puerto diferente."
                    break
                    ;;
                *)
                    print_error "Opción inválida. Selecciona 1, 2 o 3."
                    ;;
            esac
        done
    fi
    
    # Limpiar configuraciones de red si existen
    if command_exists docker; then
        print_status "Limpiando redes Docker PostgreSQL..."
        docker network ls --format "{{.Name}}" | grep -i postgres | while read -r network; do
            if [[ -n "$network" ]]; then
                docker network rm "$network" 2>/dev/null || true
            fi
        done
    fi
    
    print_success "Limpieza de instalaciones previas completada"
    echo ""
    sleep 2
}

# Función para confirmar instalación
confirm_installation() {
    local postgres_user="$1"
    local postgres_db="$2"
    
    echo ""
    print_header "RESUMEN DE CONFIGURACIÓN"
    echo -e "   Usuario: ${CYAN}$postgres_user${NC}"
    echo -e "   Contraseña: ${CYAN}$(echo "$POSTGRES_PASSWORD" | sed 's/./*/g')${NC}"
    echo -e "   Base de datos: ${CYAN}$postgres_db${NC}"
    echo ""
    
    read -p "¿Continuar con la instalación? (s/N): " confirm
    if [[ ! "$confirm" =~ ^[sS]$ ]]; then
        print_warning "Instalación cancelada por el usuario"
        exit 0
    fi
}

# Función principal de instalación
main() {
    print_header "INSTALACIÓN DE POSTGRESQL EN CONTENEDOR"
    echo ""
    echo "📝 Por favor, proporciona los siguientes datos:"
    echo ""

    # Solicitar datos del usuario con validación
    get_user_input "👤 Nombre de usuario para PostgreSQL: " "username" "POSTGRES_USER"
    get_user_input "🔒 Contraseña para PostgreSQL (mín. 8 caracteres): " "password" "POSTGRES_PASSWORD"
    get_user_input "🗄️ Nombre de la base de datos: " "database" "POSTGRES_DB"

    # Detectar y limpiar instalaciones previas
    detect_previous_installation

    # Confirmar instalación
    confirm_installation "$POSTGRES_USER" "$POSTGRES_DB"

    print_header "INICIANDO INSTALACIÓN"

    # PASO 1: Verificar permisos
    print_step "1" "Verificando permisos de administrador..."
    if [[ $EUID -ne 0 ]]; then
        print_error "Este script debe ejecutarse como root (sudo)"
        exit 1
    fi
    print_success "Permisos verificados"

    # PASO 2: Actualizar sistema
    print_step "2" "Actualizando sistema..."
    if apt update && apt upgrade -y; then
        print_success "Sistema actualizado correctamente"
    else
        print_error "Error al actualizar el sistema"
        exit 1
    fi

    # PASO 3: Instalar dependencias
    print_step "3" "Instalando dependencias..."
    apt install -y curl wget gnupg2 software-properties-common apt-transport-https ca-certificates lsb-release

    # PASO 4: Instalar Docker
    print_step "4" "Verificando Docker..."
    if command_exists docker; then
        print_warning "Docker ya está instalado"
        docker --version
    else
        print_status "Instalando Docker desde el repositorio oficial..."
        
        # Agregar clave GPG oficial de Docker
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        
        # Agregar repositorio de Docker
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Instalar Docker
        apt update
        apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        
        # Iniciar y habilitar Docker
        systemctl start docker
        systemctl enable docker
        
        print_success "Docker instalado correctamente"
        docker --version
    fi

    # PASO 5: Instalar Docker Compose (standalone)
    print_step "5" "Verificando Docker Compose..."
    if command_exists docker-compose; then
        print_warning "Docker Compose ya está instalado"
    else
        print_status "Instalando Docker Compose..."
        DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'"' -f4)
        curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        print_success "Docker Compose instalado correctamente"
    fi

    # PASO 6: Verificar que Docker esté corriendo
    print_step "6" "Verificando estado de Docker..."
    if systemctl is-active --quiet docker; then
        print_success "Docker está corriendo"
    else
        print_warning "Iniciando Docker..."
        systemctl start docker
        sleep 3
        if systemctl is-active --quiet docker; then
            print_success "Docker iniciado correctamente"
        else
            print_error "No se pudo iniciar Docker"
            exit 1
        fi
    fi

    # PASO 7: Crear directorio del proyecto
    print_step "7" "Creando directorio del proyecto..."
    readonly PROJECT_DIR="$HOME/postgres-container"
    mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR"
    print_success "Directorio creado: $PROJECT_DIR"

    # PASO 8: Verificar disponibilidad del puerto (mejorado)
    print_step "8" "Verificando disponibilidad del puerto..."
    POSTGRES_PORT=5432

    # Si hay PostgreSQL nativo corriendo, usar puerto diferente automáticamente
    if systemctl is-active --quiet postgresql 2>/dev/null || is_port_free 5432; then
        if ! is_port_free 5432; then
            print_warning "Puerto 5432 está ocupado (posiblemente PostgreSQL nativo)"
            if NEW_PORT=$(find_free_port 5433); then
                POSTGRES_PORT=$NEW_PORT
                print_success "Puerto libre encontrado: $POSTGRES_PORT"
            else
                print_error "No se pudo encontrar un puerto libre"
                exit 1
            fi
        else
            print_success "Puerto 5432 está libre"
        fi
    fi

    # PASO 9: Crear docker-compose.yml
    print_step "9" "Creando configuración Docker Compose..."
    cat > docker-compose.yml << EOF
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: postgres-${POSTGRES_DB}
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_INITDB_ARGS: "--encoding=UTF-8 --lc-collate=C --lc-ctype=C"
    ports:
      - "${POSTGRES_PORT}:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./init-scripts:/docker-entrypoint-initdb.d
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - postgres-network

volumes:
  postgres_data:
    driver: local

networks:
  postgres-network:
    driver: bridge
EOF
    print_success "Archivo docker-compose.yml creado con puerto $POSTGRES_PORT"

    # PASO 10: Crear directorio de scripts de inicialización
    print_step "10" "Creando scripts de inicialización..."
    mkdir -p init-scripts
    
    cat > init-scripts/01-create-tables.sql << 'EOF'
-- Script de inicialización de la base de datos
-- Se ejecuta automáticamente al crear el contenedor

-- Crear extensiones útiles
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Crear tabla de ejemplo: contactos
CREATE TABLE IF NOT EXISTS contactos (
    id SERIAL PRIMARY KEY,
    uuid UUID DEFAULT uuid_generate_v4() UNIQUE NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    correo VARCHAR(100) UNIQUE NOT NULL,
    telefono VARCHAR(20) NOT NULL,
    activo BOOLEAN DEFAULT TRUE,
    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Crear índices para mejorar rendimiento
CREATE INDEX IF NOT EXISTS idx_contactos_correo ON contactos(correo);
CREATE INDEX IF NOT EXISTS idx_contactos_nombre ON contactos USING GIN(nombre gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_contactos_activo ON contactos(activo);

-- Crear función para actualizar fecha de modificación
CREATE OR REPLACE FUNCTION update_fecha_actualizacion()
RETURNS TRIGGER AS $$
BEGIN
    NEW.fecha_actualizacion = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Crear trigger para actualizar automáticamente fecha_actualizacion
DROP TRIGGER IF EXISTS trigger_update_contactos_fecha ON contactos;
CREATE TRIGGER trigger_update_contactos_fecha
    BEFORE UPDATE ON contactos
    FOR EACH ROW
    EXECUTE FUNCTION update_fecha_actualizacion();

-- Insertar datos de ejemplo
INSERT INTO contactos (nombre, correo, telefono) VALUES 
('Juan Pérez', 'juan.perez@email.com', '+52-33-1234-5678'),
('María García', 'maria.garcia@email.com', '+52-33-8765-4321'),
('Carlos López', 'carlos.lopez@email.com', '+52-33-5555-1234'),
('Ana Martínez', 'ana.martinez@email.com', '+52-33-9999-8888'),
('Luis Rodríguez', 'luis.rodriguez@email.com', '+52-33-7777-6666')
ON CONFLICT (correo) DO NOTHING;

-- Crear vista para contactos activos
CREATE OR REPLACE VIEW contactos_activos AS
SELECT id, uuid, nombre, correo, telefono, fecha_creacion, fecha_actualizacion
FROM contactos 
WHERE activo = TRUE
ORDER BY fecha_creacion DESC;

-- Mostrar estadísticas de la tabla creada
DO $$
DECLARE
    total_contactos INTEGER;
BEGIN
    SELECT COUNT(*) INTO total_contactos FROM contactos;
    RAISE NOTICE 'Base de datos inicializada correctamente';
    RAISE NOTICE 'Tabla contactos creada con % registros', total_contactos;
    RAISE NOTICE 'Extensiones instaladas: uuid-ossp, pg_trgm';
    RAISE NOTICE 'Índices creados para optimizar consultas';
    RAISE NOTICE 'Triggers configurados para auditoría';
END $$;
EOF

    print_success "Scripts de inicialización creados"

    # PASO 11: Crear archivo de configuración
    print_step "11" "Creando archivo de configuración..."
    cat > .env << EOF
# Configuración PostgreSQL
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_PORT=${POSTGRES_PORT}

# Información del servidor
SERVER_IP=$(hostname -I | awk '{print $1}' || echo "localhost")
CONTAINER_NAME=postgres-${POSTGRES_DB}
PROJECT_DIR=${PROJECT_DIR}

# Configuración de backup
BACKUP_DIR=${PROJECT_DIR}/backups
BACKUP_RETENTION_DAYS=7
EOF
    print_success "Archivo de configuración creado"

    # PASO 12: Limpiar y levantar contenedor PostgreSQL
    print_step "12" "Preparando y levantando contenedor PostgreSQL..."
    
    # Limpiar contenedores con el mismo nombre si existen
    if docker ps -a --format "{{.Names}}" | grep -q "postgres-${POSTGRES_DB}"; then
        print_status "Eliminando contenedor existente con el mismo nombre..."
        docker stop "postgres-${POSTGRES_DB}" 2>/dev/null || true
        docker rm "postgres-${POSTGRES_DB}" 2>/dev/null || true
    fi
    
    # Limpiar configuración anterior si existe
    docker-compose down 2>/dev/null || true
    
    if docker-compose up -d; then
        print_success "Contenedor PostgreSQL iniciado correctamente"
    else
        print_error "Error al levantar el contenedor"
        print_status "Intentando obtener más información del error..."
        docker-compose logs
        exit 1
    fi

    # PASO 13: Esperar a que PostgreSQL esté listo
    print_step "13" "Esperando a que PostgreSQL esté listo..."
    local timeout=60
    local count=0
    
    while [ $count -lt $timeout ]; do
        if docker-compose exec -T postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; then
            print_success "PostgreSQL está listo y funcionando"
            break
        fi
        
        echo -n "."
        sleep 2
        count=$((count + 2))
    done
    
    if [ $count -ge $timeout ]; then
        print_error "Timeout esperando a PostgreSQL"
        docker-compose logs postgres
        exit 1
    fi

    # PASO 14: Configurar firewall
    print_step "14" "Configurando firewall..."
    if command_exists ufw; then
        print_status "Configurando UFW..."
        ufw allow "$POSTGRES_PORT/tcp" 2>/dev/null || true
        print_success "Puerto $POSTGRES_PORT abierto en UFW"
    elif command_exists iptables; then
        print_status "Configurando iptables..."
        iptables -A INPUT -p tcp --dport "$POSTGRES_PORT" -j ACCEPT 2>/dev/null || true
        print_success "Puerto $POSTGRES_PORT abierto en iptables"
    else
        print_warning "No se detectó firewall, podrías necesitar abrir el puerto $POSTGRES_PORT manualmente"
    fi

    # PASO 15: Crear scripts de gestión
    print_step "15" "Creando scripts de gestión..."
    create_management_scripts
    print_success "Scripts de gestión creados"

    # PASO 16: Crear directorio de backups
    print_step "16" "Configurando sistema de backups..."
    mkdir -p backups
    create_backup_scripts
    print_success "Sistema de backups configurado"

    # PASO 17: Mostrar información final
    show_final_info
}

# Función para crear scripts de gestión
create_management_scripts() {
    # Script para conectar a la base de datos
    cat > conectar.sh << EOF
#!/bin/bash
source .env
echo "Conectando a PostgreSQL..."
docker exec -it \${CONTAINER_NAME} psql -U \${POSTGRES_USER} -d \${POSTGRES_DB}
EOF

    # Script para ver logs
    cat > logs.sh << 'EOF'
#!/bin/bash
source .env
case "${1:-all}" in
    "tail"|"follow")
        echo "Siguiendo logs en tiempo real (Ctrl+C para salir)..."
        docker logs -f ${CONTAINER_NAME}
        ;;
    "error")
        echo "Mostrando solo errores..."
        docker logs ${CONTAINER_NAME} 2>&1 | grep -i error
        ;;
    "last")
        lines=${2:-100}
        echo "Mostrando últimas $lines líneas..."
        docker logs --tail $lines ${CONTAINER_NAME}
        ;;
    *)
        echo "Mostrando todos los logs..."
        docker logs ${CONTAINER_NAME}
        ;;
esac
EOF

    # Script para gestionar el contenedor
    cat > gestionar.sh << 'EOF'
#!/bin/bash
source .env

show_status() {
    echo "Estado del contenedor PostgreSQL:"
    if docker ps | grep -q ${CONTAINER_NAME}; then
        echo "✅ Contenedor está corriendo"
        docker ps | grep ${CONTAINER_NAME}
        echo ""
        echo "Uso de recursos:"
        docker stats ${CONTAINER_NAME} --no-stream
    else
        echo "❌ Contenedor no está corriendo"
        if docker ps -a | grep -q ${CONTAINER_NAME}; then
            echo "🔍 Contenedor existe pero está parado"
            docker ps -a | grep ${CONTAINER_NAME}
        else
            echo "🚫 Contenedor no existe"
        fi
    fi
}

case "$1" in
    "parar"|"stop")
        echo "Parando contenedor PostgreSQL..."
        docker-compose down
        ;;
    "iniciar"|"start")
        echo "Iniciando contenedor PostgreSQL..."
        docker-compose up -d
        ;;
    "reiniciar"|"restart")
        echo "Reiniciando contenedor PostgreSQL..."
        docker-compose restart
        ;;
    "estado"|"status")
        show_status
        ;;
    "limpiar"|"clean")
        echo "⚠️  ADVERTENCIA: Esto eliminará el contenedor y sus datos"
        read -p "¿Estás seguro? (escriba 'SI' para confirmar): " confirm
        if [[ "$confirm" == "SI" ]]; then
            docker-compose down -v
            docker volume prune -f
            echo "✅ Limpieza completada"
        else
            echo "❌ Operación cancelada"
        fi
        ;;
    *)
        echo "Uso: $0 {parar|iniciar|reiniciar|estado|limpiar}"
        echo ""
        echo "Comandos disponibles:"
        echo "  parar     - Detener el contenedor"
        echo "  iniciar   - Iniciar el contenedor"
        echo "  reiniciar - Reiniciar el contenedor"
        echo "  estado    - Mostrar estado y estadísticas"
        echo "  limpiar   - Eliminar contenedor y datos (¡CUIDADO!)"
        exit 1
        ;;
esac
EOF

    # Script de información de conexión
    cat > info_conexion.sh << 'EOF'
#!/bin/bash
source .env

echo "🗄️ INFORMACIÓN DE CONEXIÓN POSTGRESQL"
echo "====================================="
echo ""
echo "📊 Datos de la base de datos:"
echo "   Usuario: ${POSTGRES_USER}"
echo "   Base de datos: ${POSTGRES_DB}"
echo "   Puerto: ${POSTGRES_PORT}"
echo "   IP del servidor: ${SERVER_IP}"
echo ""
echo "🏠 CONEXIÓN DESDE EL SERVIDOR (localhost):"
echo "   psql -h localhost -U ${POSTGRES_USER} -d ${POSTGRES_DB} -p ${POSTGRES_PORT}"
echo ""
echo "🌐 CONEXIÓN DESDE FUERA DEL SERVIDOR:"
echo "   psql -h ${SERVER_IP} -U ${POSTGRES_USER} -d ${POSTGRES_DB} -p ${POSTGRES_PORT}"
echo ""
echo "📱 STRING DE CONEXIÓN (aplicaciones):"
echo "   postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${SERVER_IP}:${POSTGRES_PORT}/${POSTGRES_DB}"
echo ""
echo "🐳 CONEXIÓN A TRAVÉS DEL CONTENEDOR:"
echo "   docker exec -it ${CONTAINER_NAME} psql -U ${POSTGRES_USER} -d ${POSTGRES_DB}"
echo ""
echo "🔧 CONFIGURACIÓN PARA APLICACIONES:"
echo "   Host: ${SERVER_IP}"
echo "   Puerto: ${POSTGRES_PORT}"
echo "   Usuario: ${POSTGRES_USER}"
echo "   Contraseña: ${POSTGRES_PASSWORD}"
echo "   Base de datos: ${POSTGRES_DB}"
echo ""
echo "📈 HERRAMIENTAS DE MONITOREO:"
echo "   Ver logs:           ./logs.sh [tail|error|last]"
echo "   Estado contenedor:  ./gestionar.sh estado"
echo "   Conectar a BD:      ./conectar.sh"
echo "   Backup manual:      ./backup.sh"
echo ""
EOF

    # Hacer ejecutables los scripts
    chmod +x conectar.sh logs.sh gestionar.sh info_conexion.sh
}

# Función para crear scripts de backup
create_backup_scripts() {
    # Script de backup manual
    cat > backup.sh << 'EOF'
#!/bin/bash
source .env

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/backup_${POSTGRES_DB}_${TIMESTAMP}.sql"

echo "🔄 Iniciando backup de la base de datos..."
echo "Base de datos: ${POSTGRES_DB}"
echo "Archivo: ${BACKUP_FILE}"

# Crear directorio de backup si no existe
mkdir -p "${BACKUP_DIR}"

# Realizar backup
if docker exec ${CONTAINER_NAME} pg_dump -U ${POSTGRES_USER} -d ${POSTGRES_DB} > "${BACKUP_FILE}"; then
    echo "✅ Backup completado exitosamente"
    echo "📁 Archivo guardado: ${BACKUP_FILE}"
    echo "📊 Tamaño: $(du -h "${BACKUP_FILE}" | cut -f1)"
    
    # Comprimir backup
    gzip "${BACKUP_FILE}"
    echo "🗜️  Backup comprimido: ${BACKUP_FILE}.gz"
    
    # Limpiar backups antiguos
    find "${BACKUP_DIR}" -name "backup_${POSTGRES_DB}_*.sql.gz" -mtime +${BACKUP_RETENTION_DAYS} -delete
    echo "🧹 Backups antiguos limpiados (retención: ${BACKUP_RETENTION_DAYS} días)"
    
else
    echo "❌ Error al realizar el backup"
    exit 1
fi
EOF

    # Script para restaurar backup
    cat > restore.sh << 'EOF'
#!/bin/bash
source .env

if [ -z "$1" ]; then
    echo "Uso: $0 <archivo_backup.sql.gz>"
    echo ""
    echo "Backups disponibles:"
    ls -la "${BACKUP_DIR}/"backup_*.sql.gz 2>/dev/null || echo "No hay backups disponibles"
    exit 1
fi

BACKUP_FILE="$1"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "❌ El archivo $BACKUP_FILE no existe"
    exit 1
fi

echo "⚠️  ADVERTENCIA: Esta operación eliminará todos los datos actuales"
echo "Base de datos: ${POSTGRES_DB}"
echo "Backup a restaurar: ${BACKUP_FILE}"
echo ""
read -p "¿Continuar? (escriba 'SI' para confirmar): " confirm

if [[ "$confirm" != "SI" ]]; then
    echo "❌ Operación cancelada"
    exit 0
fi

echo "🔄 Restaurando backup..."

# Descomprimir si es necesario
if [[ "$BACKUP_FILE" == *.gz ]]; then
    TEMP_FILE="/tmp/restore_$(basename "$BACKUP_FILE" .gz)"
    gunzip -c "$BACKUP_FILE" > "$TEMP_FILE"
    BACKUP_FILE="$TEMP_FILE"
fi

# Restaurar
if docker exec -i ${CONTAINER_NAME} psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} < "$BACKUP_FILE"; then
    echo "✅ Backup restaurado exitosamente"
else
    echo "❌ Error al restaurar el backup"
    exit 1
fi

# Limpiar archivo temporal
if [ -f "$TEMP_FILE" ]; then
    rm "$TEMP_FILE"
fi
EOF

    # Hacer ejecutables los scripts
    chmod +x backup.sh restore.sh
}

# Función para mostrar información final
show_final_info() {
    local server_ip
    server_ip=$(hostname -I | awk '{print $1}' || echo "localhost")
    
    echo ""
    print_header "🎉 INSTALACIÓN COMPLETADA EXITOSAMENTE"
    echo ""
    print_success "PostgreSQL está corriendo en el contenedor 'postgres-${POSTGRES_DB}'"
    echo ""
    echo "📋 CONFIGURACIÓN:"
    echo "   Base de datos: ${POSTGRES_DB}"
    echo "   Usuario: ${POSTGRES_USER}"
    echo "   Puerto: ${POSTGRES_PORT}"
    echo "   IP del servidor: ${server_ip}"
    echo ""
    echo "📁 ARCHIVOS GENERADOS:"
    echo "   - docker-compose.yml (configuración del contenedor)"
    echo "   - .env (variables de entorno)"
    echo "   - init-scripts/ (scripts de inicialización)"
    echo "   - conectar.sh (conectar a la BD)"
    echo "   - logs.sh (ver logs del contenedor)"
    echo "   - gestionar.sh (gestionar el contenedor)"
    echo "   - info_conexion.sh (información de conexión)"
    echo "   - backup.sh (crear backup manual)"
    echo "   - restore.sh (restaurar backup)"
    echo ""
    echo "🔧 COMANDOS ÚTILES:"
    echo "   ./conectar.sh           - Conectar a la base de datos"
    echo "   ./info_conexion.sh      - Ver información de conexión"
    echo "   ./logs.sh [tail|error]  - Ver logs del contenedor"
    echo "   ./gestionar.sh estado   - Ver estado del contenedor"
    echo "   ./backup.sh             - Crear backup manual"
    echo ""
    echo "🌐 CONEXIÓN REMOTA:"
    echo "   psql -h ${server_ip} -U ${POSTGRES_USER} -d ${POSTGRES_DB} -p ${POSTGRES_PORT}"
    echo ""
    echo "📱 STRING DE CONEXIÓN:"
    echo "   postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${server_ip}:${POSTGRES_PORT}/${POSTGRES_DB}"
    echo ""
    print_success "¡PostgreSQL está listo para usar!"
    print_warning "Ejecuta './info_conexion.sh' para ver toda la información de conexión"
}

# Ejecutar función principal
main "$@"
