#!/bin/bash

CYAN="\033[1;36m"
BOLD="\033[1m"
WHITE="\033[97m"
RESET="\033[0m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"

show_header() {
    clear
    printf "${CYAN}${BOLD}"
    cat <<'EOF'
 _____ _   _       _                   _     _____       _                       _          
/  ___| | | |     | |                 | |   |  ___|     | |                     (_)         
\ `--.| |_| | __ _| |_ ___   ___  ___ | |_  | |__ _ __ | |_ ___ _ __ _ __  _ __ _ ___  ___   
 `--. \  _  |/ _` | __/ __| / _ \/ _ \| __| |  __| '_ \| __/ _ \ '__| '_ \| '__| / __|/ _ \  
/\__/ / | | | (_| | |_\__ \|  __/ (_) | |_  | |__| | | | ||  __/ |  | |_) | |  | \__ \  __/  
\____/\_| |_/\__,_|\__|___/ \___|\___/ \__| \____/_| |_|\__\___|_|  | .__/|_|  |_|___/\___|  
                                                                   | |                     
                                                                   |_|                     
EOF
    printf "${RESET}\n"
    printf "${WHITE}${BOLD}Chatwoot Enterprise Unlocker - Instalador${RESET}\n"
    printf "${GREEN}Transforme seu Chatwoot Community em Enterprise completo${RESET}\n"
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
    esac
}

check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        log ERROR "Docker não está instalado."
        log INFO "Por favor, instale o Docker primeiro: https://docs.docker.com/get-docker/"
        exit 1
    fi

    if ! docker info >/dev/null 2>&1; then
        log ERROR "Docker não está rodando ou você não tem permissão para acessá-lo."
        log INFO "Certifique-se de que o Docker está rodando e que seu usuário está no grupo 'docker'."
        exit 1
    fi

    log SUCCESS "Docker detectado e funcionando."
}

check_chatwoot() {
    log INFO "Verificando instalações do Chatwoot..."
    
    STACK_NAME=$(docker stack ls --format '{{.Name}}' 2>/dev/null | grep -i chatwoot | head -n1)
    
    if [ -z "$STACK_NAME" ]; then
        log ERROR "Nenhuma instalação do Chatwoot encontrada."
        log INFO "Certifique-se de que o Chatwoot está rodando via Docker Swarm."
        log INFO "Esta ferramenta suporta apenas Docker Swarm com Portainer."
        exit 1
    fi

    log SUCCESS "Chatwoot encontrado via Docker Swarm: $STACK_NAME"
}

download_cli() {
    log INFO "Baixando Chatwoot Enterprise CLI..."
    
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # URL direta para o CLI (sem verificação de licença)
    CLI_URL="https://raw.githubusercontent.com/example/chatwoot-enterprise/main/cli.sh"
    
    if curl -fsS -o chatwoot_enterprise_cli.sh "$CLI_URL"; then
        chmod +x chatwoot_enterprise_cli.sh
        log SUCCESS "CLI baixado com sucesso!"
        
        # Executar o CLI
        ./chatwoot_enterprise_cli.sh
        
    else
        log ERROR "Falha ao baixar o CLI."
        exit 1
    fi
    
    cd /
    rm -rf "$TEMP_DIR"
}

main() {
    show_header
    
    log INFO "Bem-vindo ao Chatwoot Enterprise Unlocker!"
    echo
    log INFO "Este CLI irá transformar seu Chatwoot Community em Enterprise"
    log INFO "desbloqueando todas as funcionalidades premium sem limitações."
    echo
    
    printf "${YELLOW}${BOLD}[IMPORTANTE] Requisitos: Docker Swarm + Portainer${RESET}\n\n"
    
    check_docker
    check_chatwoot
    
    echo
    log INFO "Tudo pronto! Iniciando o processo de desbloqueio..."
    sleep 2
    
    download_cli
}

main
