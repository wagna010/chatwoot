#!/bin/bash

# Chatwoot Enterprise Installer
# Execução direta: bash -c "$(curl -fsSL https://raw.githubusercontent.com/wagna010/chatwoot/main/install.sh)"

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# URLs do repositório
REPO_URL="https://github.com/wagna010/chatwoot.git"
CLI_URL="https://raw.githubusercontent.com/wagna010/chatwoot/main/cli.sh"
INSTALL_DIR="/tmp/chatwoot-enterprise-installer"

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
    echo -e "${BOLD}Chatwoot Enterprise Installer${NC}"
    echo -e "${GREEN}Instalação direta via GitHub${NC}"
    echo -e "${BLUE}=============================================${NC}"
    echo
}

check_dependencies() {
    log INFO "Verificando dependências..."
    
    # Verificar curl
    if ! command -v curl &> /dev/null; then
        log ERROR "curl não encontrado. Instale com:"
        echo "  Ubuntu/Debian: sudo apt-get install curl"
        echo "  CentOS/RHEL: sudo yum install curl"
        exit 1
    fi
    
    # Verificar docker
    if ! command -v docker &> /dev/null; then
        log ERROR "Docker não encontrado. Instale primeiro:"
        echo "  https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    # Verificar se docker está rodando
    if ! docker info &> /dev/null; then
        log ERROR "Docker não está rodando. Inicie o Docker:"
        echo "  sudo systemctl start docker"
        exit 1
    fi
    
    log SUCCESS "Todas dependências verificadas"
}

download_installer() {
    log INFO "Baixando instalador do Chatwoot Enterprise..."
    
    # Criar diretório temporário
    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    # Baixar o script CLI diretamente
    if curl -fsSL -o chatwoot-cli.sh "$CLI_URL"; then
        chmod +x chatwoot-cli.sh
        log SUCCESS "Instalador baixado com sucesso"
    else
        log ERROR "Falha ao baixar o instalador"
        exit 1
    fi
}

check_chatwoot() {
    log INFO "Verificando instalações do Chatwoot..."
    
    # Verificar Docker Swarm
    if ! docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q "active"; then
        log ERROR "Docker Swarm não está ativo"
        log INFO "Esta ferramenta requer Docker Swarm"
        exit 1
    fi
    
    # Verificar stacks Chatwoot
    STACK_NAME=$(docker stack ls --format '{{.Name}}' 2>/dev/null | grep -i chatwoot | head -n1)
    
    if [ -z "$STACK_NAME" ]; then
        log ERROR "Nenhuma stack Chatwoot encontrada"
        log INFO "Certifique-se de que o Chatwoot está instalado via Docker Swarm"
        exit 1
    fi
    
    log SUCCESS "Chatwoot encontrado: $STACK_NAME"
}

run_installer() {
    log INFO "Iniciando instalador Chatwoot Enterprise..."
    echo
    
    # Executar o CLI
    cd "$INSTALL_DIR"
    ./chatwoot-cli.sh
}

cleanup() {
    log INFO "Limpando arquivos temporários..."
    rm -rf "$INSTALL_DIR"
    log SUCCESS "Limpeza concluída"
}

main() {
    show_header
    check_dependencies
    check_chatwoot
    download_installer
    run_installer
    cleanup
}

# Tratamento de interrupção
trap 'cleanup; exit 1' INT TERM

# Executar principal
main "$@"
