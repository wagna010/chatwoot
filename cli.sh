#!/bin/bash

# Chatwoot Enterprise CLI
# Parte do instalador automático

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

CONFIG_DIR="$HOME/.chatwoot-enterprise"
LOG_FILE="$CONFIG_DIR/install.log"

log() {
    local level=$1
    local message=$2
    case $level in
        INFO) echo -e "${BLUE}[INFO]${NC} $message" ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        WARNING) echo -e "${YELLOW}[WARNING]${NC} $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
        *) echo -e "[$level] $message" ;;
    esac
    echo "$(date): [$level] $message" >> "$LOG_FILE"
}

setup_directories() {
    mkdir -p "$CONFIG_DIR"
}

show_header() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'
  ____ _               _          _   _           _____           _        
 / ___| |__   ___  ___| | _______| | | |_ __ ___ | ____|_ __   __| | _____ 
| |   | '_ \ / _ \/ __| |/ / _ \ | | | | '_ ` _ \|  _| | '_ \ / _` |/ / _ \
| |___| | | |  __/ (__|   <  __/ | |_| | | | | | | |___| | | | (_|   <  __/
 \____|_| |_|\___|\___|_|\_\___|  \___/|_| |_| |_|_____|_| |_|\__,_|\_\___|
EOF
    echo -e "${NC}"
    echo -e "${BOLD}Chatwoot Enterprise CLI${NC}"
    echo -e "${GREEN}Desbloqueio de Funcionalidades Premium${NC}"
    echo -e "${BLUE}=============================================${NC}"
    echo
}

validar_container_chatwoot() {
    local container_name=$1
    
    if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        return 1
    fi
    
    if ! docker exec "$container_name" test -f /app/bin/rails 2>/dev/null; then
        return 1
    fi
    
    return 0
}

verificar_servicos() {
    show_header
    echo -e "${BOLD}Verificando Serviços do Chatwoot${NC}"
    echo -e "${BLUE}================================${NC}"
    
    log INFO "Verificando Docker Swarm..."
    if docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q "active"; then
        log SUCCESS "Docker Swarm ativo"
    else
        log ERROR "Docker Swarm não ativo"
        return 1
    fi

    log INFO "Buscando stacks Chatwoot..."
    STACKS=$(docker stack ls --format '{{.Name}}' 2>/dev/null | grep -i chatwoot || true)
    
    if [ -n "$STACKS" ]; then
        log SUCCESS "Stacks encontradas:"
        echo "$STACKS" | while read stack; do
            echo -e "  ${GREEN}•${NC} $stack"
        done
    else
        log WARNING "Nenhuma stack Chatwoot encontrada"
    fi

    log INFO "Buscando containers Chatwoot..."
    CONTAINERS=$(docker ps --format '{{.Names}}' | grep -i chatwoot | grep -v sidekiq || true)
    
    if [ -n "$CONTAINERS" ]; then
        log SUCCESS "Containers encontrados:"
        echo "$CONTAINERS" | while read container; do
            if validar_container_chatwoot "$container"; then
                echo -e "  ${GREEN}•${NC} $container (VALIDADO)"
            else
                echo -e "  ${YELLOW}•${NC} $container (NÃO VALIDADO)"
            fi
        done
    else
        log WARNING "Nenhum container Chatwoot encontrado"
    fi

    echo
    read -p "Pressione Enter para continuar..." _
}

aplicar_modificacoes_banco() {
    local container=$1
    log INFO "Aplicando modificações no banco de dados..."
    
    cat > /tmp/enterprise_db.rb << 'EOF'
# Script de desbloqueio do banco
require 'installation_config'

puts "Iniciando desbloqueio Enterprise..."

begin
  # Configurar pricing plan
  InstallationConfig.find_or_initialize_by(name: 'INSTALLATION_PRICING_PLAN').update!(value: 'enterprise')
  
  # Habilitar features
  InstallationConfig.find_or_initialize_by(name: 'ENTERPRISE_FEATURES_ENABLED').update!(value: true)
  InstallationConfig.find_or_initialize_by(name: 'ENTERPRISE_ENABLED').update!(value: true)
  
  puts "Banco de dados configurado com sucesso!"
rescue => e
  puts "Erro: #{e.message}"
  exit 1
end
EOF

    docker cp /tmp/enterprise_db.rb "$container":/tmp/
    docker exec "$container" bundle exec rails runner /tmp/enterprise_db.rb
    docker exec "$container" rm -f /tmp/enterprise_db.rb
    rm -f /tmp/enterprise_db.rb
}

aplicar_patch_enterprise() {
    local container=$1
    log INFO "Aplicando patch Enterprise..."
    
    cat > /tmp/enterprise_patch.rb << 'EOF'
# Chatwoot Enterprise Patch
module Enterprise
  module Internal
    class CheckNewVersionsJob < ApplicationJob
      queue_as :low
      def perform; end # Neutralizado
    end
  end
end

# Configuração automática
Rails.application.config.after_initialize do
  begin
    InstallationConfig.find_or_initialize_by(name: 'INSTALLATION_PRICING_PLAN').update!(value: 'enterprise')
    InstallationConfig.find_or_initialize_by(name: 'ENTERPRISE_FEATURES_ENABLED').update!(value: true)
    InstallationConfig.find_or_initialize_by(name: 'ENTERPRISE_ENABLED').update!(value: true)
  rescue => e
    Rails.logger.error "Enterprise patch error: #{e.message}"
  end
end
EOF

    docker cp /tmp/enterprise_patch.rb "$container":/app/config/initializers/enterprise_patch.rb
    rm -f /tmp/enterprise_patch.rb
}

desbloquear_enterprise() {
    show_header
    echo -e "${BOLD}Desbloqueio Enterprise${NC}"
    echo -e "${BLUE}========================${NC}"
    
    log INFO "Localizando instalação do Chatwoot..."
    
    # Encontrar container principal
    CONTAINER=$(docker ps --format '{{.Names}}' | grep -i chatwoot | grep -v sidekiq | head -n1)
    
    if [ -z "$CONTAINER" ]; then
        log ERROR "Nenhum container Chatwoot encontrado"
        return 1
    fi
    
    if ! validar_container_chatwoot "$CONTAINER"; then
        log ERROR "Container $CONTAINER não é uma instalação válida do Chatwoot"
        return 1
    fi
    
    log SUCCESS "Container encontrado: $CONTAINER"
    
    echo
    echo -e "${YELLOW}ATENÇÃO: Esta operação modificará permanentemente sua instalação${NC}"
    echo -e "${YELLOW}e habilitará todas as funcionalidades Enterprise.${NC}"
    echo
    read -p "Deseja continuar? (s/N): " confirm
    
    if [ "$confirm" != "s" ] && [ "$confirm" != "S" ]; then
        log INFO "Operação cancelada"
        return
    fi
    
    # Aplicar modificações
    aplicar_modificacoes_banco "$CONTAINER"
    aplicar_patch_enterprise "$CONTAINER"
    
    # Atualizar serviço
    SERVICE_NAME=$(docker inspect "$CONTAINER" --format '{{index .Config.Labels "com.docker.swarm.service.name"}}' 2>/dev/null || true)
    
    if [ -n "$SERVICE_NAME" ]; then
        log INFO "Atualizando serviço Docker..."
        docker service update \
            --env-add CHATWOOT_EDITION=enterprise \
            --env-add ENTERPRISE_FEATURES_ENABLED=true \
            --env-add ENTERPRISE_ENABLED=true \
            "$SERVICE_NAME" >/dev/null 2>&1 || true
    fi
    
    log SUCCESS "Desbloqueio Enterprise concluído!"
    echo
    echo -e "${GREEN}Próximos passos:${NC}"
    echo -e "  • Acesse o Chatwoot"
    echo -e "  • Vá em Super Admin > Settings"
    echo -e "  • Ative as features Enterprise desejadas"
    echo
    read -p "Pressione Enter para continuar..." _
}

menu_principal() {
    while true; do
        show_header
        echo -e "${BOLD}Menu Principal${NC}"
        echo -e "${BLUE}=============${NC}"
        echo
        echo -e "1. Verificar Serviços"
        echo -e "2. Desbloquear Enterprise"
        echo -e "3. Sair"
        echo
        read -p "Selecione uma opção [1-3]: " opcao
        
        case $opcao in
            1) verificar_servicos ;;
            2) desbloquear_enterprise ;;
            3) 
                echo -e "${GREEN}Saindo...${NC}"
                exit 0
                ;;
            *) 
                echo -e "${RED}Opção inválida${NC}"
                sleep 1
                ;;
        esac
    done
}

# Configuração inicial
setup_directories
log INFO "Chatwoot Enterprise CLI iniciado"

# Verificar Docker
if ! docker info >/dev/null 2>&1; then
    log ERROR "Docker não está disponível"
    exit 1
fi

# Executar menu
menu_principal
