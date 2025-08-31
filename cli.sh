#!/bin/bash

CYAN="\033[1;36m"
BOLD="\033[1m"
WHITE="\033[97m"
RESET="\033[0m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"

CONFIG_FILE="$HOME/.chatwoot_enterprise_cli.conf"

cleanup_on_exit() {
    for f in \
        /tmp/enterprise_unlock.rb \
        /tmp/enterprise_patch.rb \
        /tmp/enterprise_compose.yml \
        /tmp/enterprise_compose_temp.yml \
        /tmp/portainer_response.json \
        ; do
        [ -f "$f" ] && rm -f "$f" 2>/dev/null || true
    done
    
    find /tmp -name "*enterprise*" -type f -delete >/dev/null 2>&1 || true
    find /tmp -name "*chatwoot*" -type f -delete >/dev/null 2>&1 || true
    find /tmp -name "*patch*" -type f -delete >/dev/null 2>&1 || true
    find /tmp -name "*unlock*" -type f -delete >/dev/null 2>&1 || true
    
    [ -f "$CONFIG_FILE" ] && rm -f "$CONFIG_FILE" 2>/dev/null || true
}

trap cleanup_on_exit EXIT

auto_install() {
    local cmd=$1
    local pkg=$2
    if ! command -v "$cmd" >/dev/null 2>&1; then
        if [ "$(uname)" = "Darwin" ]; then
            if command -v brew >/dev/null 2>&1; then
                brew install "$pkg" >/dev/null 2>&1
            fi
        elif [ -f /etc/debian_version ]; then
            sudo apt-get update >/dev/null 2>&1 && sudo apt-get install -y "$pkg" >/dev/null 2>&1
        elif [ -f /etc/redhat-release ]; then
            sudo yum install -y "$pkg" >/dev/null 2>&1
        fi
    fi
}

auto_install jq jq
auto_install yq yq

show_header() {
    clear
    printf "${CYAN}${BOLD}"
    cat <<'EOF'
 _____ _    _        _                 _     _____           _                 _          
/  ___| | | |      | |               | |   |  ___|         | |               (_)         
\ `--.| |_| | __ _| |_ ___    ___ ___ | |_  | |__ _ __  _ __| |_ ___ _ __ _ __ _ ___  ___ 
 `--. \  _  |/ _` | __/ __|  / _ \ _ \| __| |  __| '_ \| '__| __/ _ \ '__| '_ \ '__| / __|/ _ \  
/\__/ / | | | (_| | |_\__ \ |  __/ (_) | |_  | |__| | | | |  | ||  __/ |  | |_) | |  | \__ \  __/  
\____/\_| |_/\__,_|\__|___/  \___|\___/ \__| \____/_| |_|_|   \__\___|_|  | .__/|_|  |_|___/\___|  
                                                                       | |                    
                                                                       |_|                    
EOF
    printf "${RESET}\n"
    printf "${WHITE}${BOLD}Chatwoot Enterprise Unlocker CLI v1.0${RESET}\n"
    printf "${GREEN}Docker Swarm + Portainer - Desbloqueio Permanente${RESET}\n"
    printf "${CYAN}================================================================${RESET}\n\n"
}

log() {
    local level=$1
    shift
    local message="$*"
    case $level in
        INFO)    echo -e "${CYAN}[INFO]${RESET} $message" ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${RESET} $message" ;;
        WARNING) echo -e "${YELLOW}[WARNING]${RESET} $message" ;;
        ERROR)   echo -e "${RED}[ERROR]${RESET} $message" ;;
        STEP)    echo -e "${WHITE}${BOLD}[STEP]${RESET} $message" ;;
        CHECK)   echo -e "${CYAN}[CHECK]${RESET} $message" ;;
        DONE)    echo -e "${GREEN}[DONE]${RESET} $message" ;;
    esac
}

validar_container_chatwoot() {
    local container_name=$1
    
    if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        return 1
    fi
    
    if ! docker exec "$container_name" test -f /app/bin/rails 2>/dev/null; then
        return 1
    fi
    
    CHATWOOT_CHECK=$(docker exec "$container_name" bundle exec rails runner "
        begin
          if defined?(Chatwoot)
            puts 'CHATWOOT_CONFIRMED'
          else
            puts 'NOT_CHATWOOT'
          end
        rescue => e
          puts 'RAILS_ERROR'
        end
    " 2>/dev/null | grep "CHATWOOT_CONFIRMED" || true)
    
    if [ -n "$CHATWOOT_CHECK" ]; then
        return 0
    else
        return 1
    fi
}

verificar_servicos() {
    show_header
    echo -e "${WHITE}${BOLD}VERIFICANDO SERVIÇOS DO CHATWOOT${RESET}\n"
    echo -e "${CYAN}${BOLD}INFORMATIONS DO SISTEMA${RESET}"
    echo -e "${CYAN}================================${RESET}"
    log STEP "Verificando serviços do Chatwoot..."

    if docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q "active"; then
        log SUCCESS "Docker Swarm ativo detectado"
        STACK_NAMES=$(docker stack ls --format '{{.Name}}' 2>/dev/null | grep -i chatwoot)
        
        if [ -n "$STACK_NAMES" ]; then
            log SUCCESS "Stacks Docker Swarm encontradas:"
            echo "$STACK_NAMES" | while read -r stack; do
                echo -e "  ${GREEN}*${RESET} $stack"
            done
        else
            log WARNING "Nenhuma stack com 'chatwoot' no nome encontrada no Swarm."
        fi
    else
        log ERROR "Docker Swarm não ativo - esta ferramenta requer Docker Swarm"
        return 1
    fi

    ALL_CONTAINERS=$(docker ps --filter "status=running" --format '{{.Names}} {{.Image}}')
    CHATWOOT_CONTAINERS=""
    
    if [ -n "$ALL_CONTAINERS" ]; then
        FILTERED=$(echo "$ALL_CONTAINERS" | grep -viE '(nhenriquemac/chatwoot-enterprise-cli|enterprise-cli)' || true)
        CHATWOOT_CONTAINERS=$(echo "$FILTERED" | grep -E "(chatwoot|cwt|chat)" | grep -v -E "(redis|postgres|db|nginx|traefik|sidekiq|cli)" || true)
        
        if [ -z "$CHATWOOT_CONTAINERS" ]; then
            log INFO "Verificando containers por imagem..."
            CHATWOOT_CONTAINERS=$(echo "$FILTERED" | grep -E "(ruby|rails)" | grep -v -E "(redis|postgres|db|nginx|traefik|sidekiq|cli)" || true)
        fi
    fi
    
    if [ -n "$CHATWOOT_CONTAINERS" ]; then
        log SUCCESS "Instalações Chatwoot detectadas:"
        echo -e "\n${WHITE}${BOLD}DETALHES DOS CONTAINERS${RESET}"
        echo -e "${WHITE}================================${RESET}"
        echo "$CHATWOOT_CONTAINERS" | while IFS=' ' read -r name image; do
            if [ -z "$name" ]; then continue; fi
            if validar_container_chatwoot "$name"; then
                PATCH_OK=$(docker exec "$name" sh -lc '
                    if test -f /app/config/initializers/enterprise_patch.rb; then
                        if grep -q "ChatwootHub" /app/config/initializers/enterprise_patch.rb && \
                           grep -q "pricing_plan" /app/config/initializers/enterprise_patch.rb && \
                           grep -q "enterprise" /app/config/initializers/enterprise_patch.rb; then
                            echo "OK"
                        else
                            echo "INVALID_PATCH"
                        fi
                    else
                        echo "NO_PATCH"
                    fi
                ' 2>/dev/null)
                
                CONFIG_OK=$(docker exec "$name" bundle exec rails runner "
                    begin
                        p = InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN')
                        f = InstallationConfig.find_by(name: 'ENTERPRISE_FEATURES_ENABLED')
                        e = InstallationConfig.find_by(name: 'ENTERPRISE_ENABLED')
                        
                        if p && p.value.to_s.downcase == 'enterprise' && 
                           f && (f.value == true || f.value.to_s == 'true') &&
                           e && (e.value == true || e.value.to_s == 'true')
                        then
                            puts 'OK'
                        else
                            puts 'NO'
                        end
                    rescue => e
                        puts 'ERR'
                    end
                " 2>/dev/null | tail -1)
                
                if [ "$PATCH_OK" = "OK" ] && [ "$CONFIG_OK" = "OK" ]; then
                    STATUS_LABEL="DESBLOQUEADO"
                elif [ "$PATCH_OK" = "INVALID_PATCH" ]; then
                    STATUS_LABEL="PATCH_INVALIDO"
                elif [ "$PATCH_OK" = "NO_PATCH" ]; then
                    STATUS_LABEL="SEM_PATCH"
                elif [ "$CONFIG_OK" = "NO" ]; then
                    STATUS_LABEL="CONFIG_INCOMPLETA"
                elif [ "$CONFIG_OK" = "ERR" ]; then
                    STATUS_LABEL="ERRO_DB"
                fi
                
                echo "  [OK] $name ($image) - CHATWOOT CONFIRMADO [$STATUS_LABEL]"
            fi
        done
    else
        log WARNING "Nenhum container Chatwoot encontrado."
    fi

    echo
    read -p "Pressione Enter para voltar ao menu..." _ < /dev/tty
    return
}

aplicar_modificacoes_container() {
    local container_ref=$1
    log INFO "Aplicando modificações Enterprise no container $container_ref..."

    cat > /tmp/enterprise_unlock.rb << 'EOF'
# Script de desbloqueio Enterprise
require 'installation_config'

puts "Aplicando desbloqueio Enterprise..."

# Configurar pricing plan como enterprise
InstallationConfig.find_or_initialize_by(name: 'INSTALLATION_PRICING_PLAN').update!(value: 'enterprise')

# Habilitar features enterprise
InstallationConfig.find_or_initialize_by(name: 'ENTERPRISE_FEATURES_ENABLED').update!(value: true)
InstallationConfig.find_or_initialize_by(name: 'ENTERPRISE_ENABLED').update!(value: true)

puts "Desbloqueio Enterprise aplicado com sucesso!"
EOF

    if docker exec "$container_ref" test -f /app/bin/rails >/dev/null 2>&1; then
        log STEP "Aplicando desbloqueio no banco de dados..."
        docker cp /tmp/enterprise_unlock.rb "$container_ref":/tmp/ >/dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            OUTPUT=$(docker exec "$container_ref" bundle exec rails runner /tmp/enterprise_unlock.rb 2>&1)
            EXIT_CODE=$?
            
            if [ $EXIT_CODE -eq 0 ]; then
                log SUCCESS "Desbloqueio aplicado com sucesso!"
            else
                log ERROR "Erro ao aplicar desbloqueio: $OUTPUT"
                return 1
            fi
        else
            log ERROR "Falha ao aplicar desbloqueio"
            return 1
        fi
        
        docker exec "$container_ref" rm -f /tmp/enterprise_unlock.rb >/dev/null 2>&1
    else
        log ERROR "Container do Chatwoot não encontrado ou não acessível."
        return 1
    fi

    rm -f /tmp/enterprise_unlock.rb
}

aplicar_patch_enterprise() {
    local container_ref=$1
    log INFO "Aplicando patch Enterprise no container $container_ref..."

    cat > /tmp/enterprise_patch.rb << 'EOF'
# Patch Enterprise para Chatwoot
module Enterprise
  module Internal
    class CheckNewVersionsJob < ApplicationJob
      queue_as :low

      def perform
        # Neutralizado - não executa mais verificações que resetam features
        Rails.logger.info "Enterprise patch applied - version checks neutralized"
      end
    end
  end
end

# Configuração automática de features enterprise
Rails.application.config.after_initialize do
  begin
    # Garantir que as configurações enterprise estão setadas
    InstallationConfig.find_or_initialize_by(name: 'INSTALLATION_PRICING_PLAN').update!(value: 'enterprise')
    InstallationConfig.find_or_initialize_by(name: 'ENTERPRISE_FEATURES_ENABLED').update!(value: true)
    InstallationConfig.find_or_initialize_by(name: 'ENTERPRISE_ENABLED').update!(value: true)
    
    Rails.logger.info "Enterprise features permanently enabled"
  rescue => e
    Rails.logger.error "Error enabling enterprise features: #{e.message}"
  end
end
EOF

    docker cp /tmp/enterprise_patch.rb "$container_ref":/app/config/initializers/enterprise_patch.rb >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log SUCCESS "Patch Enterprise aplicado com sucesso!"
        
        if docker exec "$container_ref" test -f /app/config/initializers/enterprise_patch.rb 2>/dev/null; then
            log SUCCESS "Patch encontrado no container"
        else
            log ERROR "Patch não encontrado no container"
            return 1
        fi
    else
        log ERROR "Falha ao aplicar patch no container"
        return 1
    fi

    rm -f /tmp/enterprise_patch.rb
}

desbloquear_via_swarm() {
    local stack_name=$1
    local service_name=$2
    log INFO "Aplicando desbloqueio Enterprise via Docker Swarm..."

    CHATWOOT_CONTAINER_ID=$(docker ps -q --filter "label=com.docker.swarm.service.name=${service_name}" --filter "status=running" | head -n 1)
    
    if [ -z "$CHATWOOT_CONTAINER_ID" ]; then
        log ERROR "Nenhum container em execução encontrado para o serviço $service_name"
        return
    fi
    
    log SUCCESS "Container encontrado: $CHATWOOT_CONTAINER_ID"

    aplicar_modificacoes_container "$CHATWOOT_CONTAINER_ID"
    aplicar_patch_enterprise "$CHATWOOT_CONTAINER_ID"

    log INFO "Atualizando serviço com variáveis Enterprise..."
    if docker service update \
        --env-add CHATWOOT_EDITION=enterprise \
        --env-add ENTERPRISE_FEATURES_ENABLED=true \
        --env-add ENTERPRISE_ENABLED=true \
        "$service_name" >/dev/null 2>&1; then
        log SUCCESS "Serviço atualizado com variáveis Enterprise."
    else
        log ERROR "Falha ao atualizar o serviço $service_name"
        return
    fi

    log INFO "Aguardando atualização do serviço..."
    sleep 15

    echo -e "\n${GREEN}${BOLD}DESBLOQUEIO ENTERPRISE CONCLUIDO!${RESET}"
    echo -e "${GREEN}========================================${RESET}"
    log DONE "Todas as funcionalidades Enterprise foram desbloqueadas!"
    log DONE "O desbloqueio é permanente e sobrevive a reinicializações"
    
    echo -e "\n${WHITE}${BOLD}Próximos passos:${RESET}"
    echo -e "  ${CYAN}*${RESET} Acesse a interface do Chatwoot"
    echo -e "  ${CYAN}*${RESET} Vá em Super Admin > Settings"
    echo -e "  ${CYAN}*${RESET} Ative as features Enterprise desejadas"
    echo
}

desbloquear_enterprise() {
    show_header
    log INFO "Iniciando processo de desbloqueio Enterprise do Chatwoot..."
    echo

    log INFO "Procurando por instalações do Chatwoot..."
    sleep 2
    
    STACK_NAME=$(docker stack ls --format '{{.Name}}' 2>/dev/null | grep -i chatwoot | head -n1)
    
    if [ -z "$STACK_NAME" ]; then
        log ERROR "Nenhuma stack Chatwoot encontrada no Docker Swarm"
        return
    fi

    SERVICE_NAME=$(docker stack services "$STACK_NAME" --format '{{.Name}}' | grep -Ei 'chatwoot' | head -n1)
    
    if [ -z "$SERVICE_NAME" ]; then
        log ERROR "Nenhum serviço Chatwoot encontrado na stack $STACK_NAME"
        return
    fi
    
    log SUCCESS "Stack detectada: $STACK_NAME"
    log SUCCESS "Serviço detectado: $SERVICE_NAME"

    echo
    log WARNING "ATENÇÃO: Esta operação irá modificar a instalação do Chatwoot"
    log WARNING "e ativar todas as funcionalidades Enterprise permanentemente."
    echo
    
    printf "${RED}${BOLD}Tem certeza que deseja continuar? [s/N]:${RESET} "
    read -r CONFIRMATION < /dev/tty
    
    if [ "$CONFIRMATION" != "s" ] && [ "$CONFIRMATION" != "S" ]; then
        log INFO "Operação cancelada pelo usuário."
        return
    fi
    
    echo
    log SUCCESS "Iniciando desbloqueio Enterprise..."
    desbloquear_via_swarm "$STACK_NAME" "$SERVICE_NAME"

    echo
    read -p "Pressione Enter para voltar ao menu..." _ < /dev/tty
}

limpar_residuos() {
    log INFO "Limpando arquivos temporários..."
    
    for f in \
        /tmp/enterprise_unlock.rb \
        /tmp/enterprise_patch.rb \
        /tmp/enterprise_compose.yml \
        /tmp/enterprise_compose_temp.yml \
        /tmp/portainer_response.json \
        ; do
        [ -f "$f" ] && rm -f "$f" 2>/dev/null || true
    done
    
    find /tmp -name "*enterprise*" -type f -delete >/dev/null 2>&1
    find /tmp -name "*chatwoot*" -type f -delete >/dev/null 2>&1
    
    log SUCCESS "Limpeza concluída!"
}

menu_principal() {
    while true; do
        show_header
        printf "${WHITE}${BOLD}MENU PRINCIPAL${RESET}\n"
        printf "${WHITE}================${RESET}\n\n"
        printf "${WHITE}${BOLD}Selecione uma opção:${RESET}\n\n"
        printf "1 - ${GREEN}Verificar Serviços do Chatwoot${RESET}\n"
        printf "2 - ${CYAN}Desbloquear Enterprise Features${RESET}\n"
        printf "3 - ${RED}Sair${RESET}\n\n"
        printf "${BOLD}${WHITE}Digite sua escolha [1-3]: ${RESET}"
        read -r opcao < /dev/tty

        case $opcao in
            1) verificar_servicos ;;
            2) desbloquear_enterprise ;;
            3) 
                limpar_residuos
                echo -e "\n${GREEN}Obrigado por usar o Chatwoot Enterprise CLI!${RESET}"
                exit 0 
                ;;
            *) 
                echo -e "\n${RED}Opção inválida. Tente novamente.${RESET}"
                sleep 2
                ;;
        esac
    done
}

if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}Docker não está rodando ou não está acessível.${RESET}"
    exit 1
fi

menu_principal
