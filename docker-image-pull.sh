#!/bin/bash

# Docker Image Pull Script
# This script helps pull images from Docker Hub (supports both public and private org repos)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Debug mode (can be overridden by config file)
DEBUG=false

# Config file path (defined early so we can load DEBUG setting)
CONFIG_FILE="$(dirname "$0")/.docker-credentials"

# Load DEBUG setting early if config exists
if [[ -f "$CONFIG_FILE" ]]; then
    # Extract just the DEBUG setting without loading credentials yet
    DEBUG_SETTING=$(grep "^DEBUG=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'")
    if [[ "$DEBUG_SETTING" == "true" ]]; then
        DEBUG=true
        echo -e "\033[0;35m[DEBUG]\033[0m Debug mode enabled from config file"
    fi
fi

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_debug() {
    if [[ "$DEBUG" == true ]]; then
        echo -e "${MAGENTA}[DEBUG]${NC} $1"
    fi
}

# Step 1 & 2 & 3: Check for Homebrew, then Docker
check_and_install_homebrew() {
    if ! command -v brew &> /dev/null; then
        print_warning "Homebrew is not installed."
        print_status "Installing Homebrew..."
        print_debug "Executing: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        
        # Add Homebrew to PATH for Apple Silicon Macs
        if [[ $(uname -m) == "arm64" ]]; then
            print_debug "Executing: eval \"\$(/opt/homebrew/bin/brew shellenv)\""
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
        
        print_success "Homebrew installed successfully!"
    else
        print_debug "Executing: brew --version"
        BREW_VERSION=$(brew --version 2>/dev/null | head -n 1)
        print_debug "Output: $BREW_VERSION"
        print_success "Homebrew is already installed."
    fi
}

check_and_install_docker() {
    if ! command -v docker &> /dev/null; then
        print_warning "Docker CLI is not installed."
        print_status "Installing Docker via Homebrew..."
        print_debug "Executing: brew install --cask docker"
        brew install --cask docker
        print_success "Docker installed successfully!"
        print_warning "Please start Docker Desktop from your Applications folder before continuing."
        read -p "Press Enter once Docker Desktop is running..."
    else
        print_debug "Executing: docker --version"
        DOCKER_VERSION=$(docker --version 2>/dev/null)
        print_debug "Output: $DOCKER_VERSION"
        print_success "Docker CLI is already installed."
    fi
    
    # Verify Docker daemon is running
    print_debug "Executing: docker info"
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running. Please start Docker Desktop and try again."
        exit 1
    fi
    print_debug "Output: Docker daemon responded successfully"
    
    print_success "Docker daemon is running."
}

check_and_install_trivy() {
    if ! command -v trivy &> /dev/null; then
        print_warning "Trivy is not installed."
        print_status "Installing Trivy via Homebrew..."
        print_debug "Executing: brew install trivy"
        brew install trivy
        
        if [[ $? -eq 0 ]]; then
            print_success "Trivy installed successfully!"
        else
            print_error "Failed to install Trivy."
            exit 1
        fi
    else
        print_success "Trivy is already installed."
    fi
    
    # Display Trivy version
    print_debug "Executing: trivy --version"
    TRIVY_VERSION=$(trivy --version 2>/dev/null | head -n 1)
    print_debug "Output: $TRIVY_VERSION"
    print_status "Trivy version: $TRIVY_VERSION"
}

# Step 4: Ask for Docker Hub access token and login
docker_hub_login() {
    echo ""
    print_status "Docker Hub Authentication"
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}PUBLIC images (nginx, ubuntu, python, etc.) don't require login!${NC}"
    echo -e "${GREEN}Only private repositories require authentication.${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    read -p "Do you want to login to Docker Hub? (y/n, default: n): " LOGIN_CHOICE
    
    if [[ ! "$LOGIN_CHOICE" =~ ^[Yy]$ ]]; then
        print_status "Skipping Docker Hub login. You can still pull public images."
        LOGGED_IN=false
        return
    fi
    
    # Check if config file exists
    if [[ -f "$CONFIG_FILE" ]]; then
        echo ""
        print_status "Found credentials file: $CONFIG_FILE"
        read -p "Use saved credentials? (y/n, default: y): " USE_CONFIG
        
        if [[ ! "$USE_CONFIG" =~ ^[Nn]$ ]]; then
            # Load credentials from config file
            source "$CONFIG_FILE"
            
            # Debug: show loaded config values
            print_debug "Loaded from config: TOKEN_TYPE=$TOKEN_TYPE"
            print_debug "Loaded from config: DEBUG=$DEBUG"
            print_debug "Loaded from config: DOCKER_ORG=$DOCKER_ORG"
            print_debug "Loaded from config: DOCKER_USERNAME=$DOCKER_USERNAME"
            print_debug "Loaded from config: DOCKER_TOKEN=$DOCKER_TOKEN"
            
            # Use DOCKER_ORG for OAT tokens, fall back to DOCKER_USERNAME for backward compatibility
            if [[ "$TOKEN_TYPE" == "oat" && -n "$DOCKER_ORG" ]]; then
                CONFIG_NAMESPACE="$DOCKER_ORG"
            elif [[ -n "$DOCKER_USERNAME" ]]; then
                CONFIG_NAMESPACE="$DOCKER_USERNAME"
            else
                CONFIG_NAMESPACE=""
            fi
            
            print_debug "Resolved CONFIG_NAMESPACE=$CONFIG_NAMESPACE"
            
            if [[ -n "$CONFIG_NAMESPACE" && -n "$DOCKER_TOKEN" && "$DOCKER_TOKEN" != "your-token-here" ]]; then
                print_status "Using credentials for organization: $CONFIG_NAMESPACE"
                
                # Login to Docker Hub
                # Note: We always suppress stderr because Docker Desktop's credential helper
                # produces a misleading "Cannot log into an organization account" warning
                # even when OAT login succeeds. The warning is from Docker Desktop, not our login.
                print_debug "Executing: docker login -u \"$CONFIG_NAMESPACE\" --password-stdin"
                LOGIN_OUTPUT=$(echo "$DOCKER_TOKEN" | docker login -u "$CONFIG_NAMESPACE" --password-stdin 2>/dev/null)
                LOGIN_EXIT_CODE=$?
                print_debug "Output: $LOGIN_OUTPUT"
                print_debug "Exit code: $LOGIN_EXIT_CODE"
                
                if [[ $LOGIN_EXIT_CODE -eq 0 ]]; then
                    print_success "Successfully logged in to Docker Hub!"
                    LOGGED_IN=true
                    STORED_NAMESPACE="$CONFIG_NAMESPACE"
                    STORED_TOKEN="$DOCKER_TOKEN"
                    
                    # Set ORG_MODE based on token type
                    if [[ "$TOKEN_TYPE" == "oat" ]]; then
                        ORG_MODE=true
                    fi
                    return
                else
                    print_error "Failed to login with saved credentials."
                    print_status "Falling back to manual entry..."
                fi
            else
                print_warning "Config file exists but credentials not set."
                print_status "Edit $CONFIG_FILE to save your credentials."
            fi
        fi
    fi
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Choose your token type:${NC}"
    echo -e "${BLUE}${NC}"
    echo -e "${BLUE}  [1] Organization Access Token (OAT)${NC}"
    echo -e "${BLUE}      - Token starts with: dckr_oat_${NC}"
    echo -e "${BLUE}      - Use your ORGANIZATION NAME as the username${NC}"
    echo -e "${BLUE}${NC}"
    echo -e "${BLUE}  [2] Personal Access Token (PAT)${NC}"
    echo -e "${BLUE}      - Token starts with: dckr_pat_${NC}"
    echo -e "${BLUE}      - Use your PERSONAL USERNAME (not email)${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    read -p "Select token type (1 or 2): " TOKEN_TYPE_INPUT
    
    if [[ "$TOKEN_TYPE_INPUT" == "1" ]]; then
        echo ""
        echo -e "${YELLOW}Using Organization Access Token (OAT)${NC}"
        read -p "Enter your Docker Hub organization name: " DOCKER_USERNAME
    else
        echo ""
        echo -e "${YELLOW}Using Personal Access Token (PAT)${NC}"
        echo -e "${YELLOW}To find your username: Go to hub.docker.com > Profile icon > Username at top${NC}"
        read -p "Enter your Docker Hub username (NOT your email): " DOCKER_USERNAME
    fi
    
    if [[ -z "$DOCKER_USERNAME" ]]; then
        print_warning "No username/org name provided. Skipping login."
        LOGGED_IN=false
        return
    fi
    
    read -sp "Enter your Docker Hub access token: " DOCKER_TOKEN
    echo ""
    
    if [[ -z "$DOCKER_TOKEN" ]]; then
        print_warning "No token provided. Skipping login."
        LOGGED_IN=false
        return
    fi
    
    # Login to Docker Hub
    # Note: We always suppress stderr because Docker Desktop's credential helper
    # produces a misleading "Cannot log into an organization account" warning
    # even when OAT login succeeds. The warning is from Docker Desktop, not our login.
    print_debug "Executing: docker login -u \"$DOCKER_USERNAME\" --password-stdin"
    LOGIN_OUTPUT=$(echo "$DOCKER_TOKEN" | docker login -u "$DOCKER_USERNAME" --password-stdin 2>/dev/null)
    LOGIN_EXIT_CODE=$?
    print_debug "Output: $LOGIN_OUTPUT"
    print_debug "Exit code: $LOGIN_EXIT_CODE"
    
    if [[ $LOGIN_EXIT_CODE -eq 0 ]]; then
        print_success "Successfully logged in to Docker Hub!"
        LOGGED_IN=true
        # Store credentials for API calls
        STORED_NAMESPACE="$DOCKER_USERNAME"
        STORED_TOKEN="$DOCKER_TOKEN"
        
        # Offer to save credentials
        echo ""
        read -p "Save credentials to config file for future use? (y/n): " SAVE_CREDS
        if [[ "$SAVE_CREDS" =~ ^[Yy]$ ]]; then
            if [[ "$TOKEN_TYPE_INPUT" == "1" ]]; then
                cat > "$CONFIG_FILE" << EOF
# Docker Hub Credentials
# This file is ignored by git - safe to store credentials here

# Debug mode: set to true to see detailed curl commands and responses
DEBUG=false

# Token type: "oat" for Organization Access Token, "pat" for Personal Access Token
TOKEN_TYPE="oat"

# Your Docker Hub organization name (for OAT tokens)
DOCKER_ORG="$DOCKER_USERNAME"

# Your Docker Hub access token
DOCKER_TOKEN="$DOCKER_TOKEN"
EOF
            else
                cat > "$CONFIG_FILE" << EOF
# Docker Hub Credentials
# This file is ignored by git - safe to store credentials here

# Debug mode: set to true to see detailed curl commands and responses
DEBUG=false

# Token type: "oat" for Organization Access Token, "pat" for Personal Access Token
TOKEN_TYPE="pat"

# Your Docker Hub username (for PAT tokens)
DOCKER_USERNAME="$DOCKER_USERNAME"

# Your Docker Hub access token
DOCKER_TOKEN="$DOCKER_TOKEN"
EOF
            fi
            print_success "Credentials saved to $CONFIG_FILE"
        fi
    else
        print_error "Failed to login to Docker Hub."
        print_status "Continuing without authentication. You can still pull public images."
        LOGGED_IN=false
    fi
}

# Step 5a: Check existing local images and offer to remove them
manage_existing_images() {
    echo ""
    print_status "Checking for existing Docker images on your system..."
    echo ""
    
    # Get list of local images
    print_debug "Executing: docker images --format \"{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}\""
    LOCAL_IMAGES=$(docker images --format "{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}" 2>/dev/null)
    
    if [[ -z "$LOCAL_IMAGES" ]]; then
        print_status "No local Docker images found."
        return
    fi
    
    echo -e "${BLUE}Your current Docker images:${NC}"
    echo ""
    printf "%-5s %-40s %-15s %s\n" "#" "IMAGE" "ID" "SIZE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Display images with numbers and store in arrays
    IMAGE_COUNT=0
    declare -a IMAGE_NAMES
    declare -a IMAGE_IDS
    
    while IFS=$'\t' read -r name id size; do
        ((IMAGE_COUNT++))
        IMAGE_NAMES[$IMAGE_COUNT]="$name"
        IMAGE_IDS[$IMAGE_COUNT]="$id"
        printf "%-5s %-40s %-15s %s\n" "[$IMAGE_COUNT]" "$name" "${id:0:12}" "$size"
    done <<< "$LOCAL_IMAGES"
    
    echo ""
    
    if [[ $IMAGE_COUNT -eq 0 ]]; then
        print_status "No local Docker images found."
        return
    fi
    
    echo -e "${YELLOW}To remove images, enter the numbers separated by commas (e.g., 1,3,5)${NC}"
    echo -e "${YELLOW}Press Enter to keep all images.${NC}"
    echo ""
    read -p "Enter image numbers to remove: " REMOVE_LIST
    
    if [[ -z "$REMOVE_LIST" ]]; then
        print_status "Keeping all existing images."
        return
    fi
    
    # Parse the comma-separated list
    IFS=',' read -ra NUMBERS_TO_REMOVE <<< "$REMOVE_LIST"
    
    IMAGES_REMOVED=0
    
    echo ""
    for num in "${NUMBERS_TO_REMOVE[@]}"; do
        # Trim whitespace
        num=$(echo "$num" | tr -d ' ')
        
        # Validate it's a number
        if ! [[ "$num" =~ ^[0-9]+$ ]]; then
            print_warning "Skipping invalid entry: '$num'"
            continue
        fi
        
        # Check if number is in valid range
        if [[ $num -lt 1 || $num -gt $IMAGE_COUNT ]]; then
            print_warning "Skipping out of range: $num (valid: 1-$IMAGE_COUNT)"
            continue
        fi
        
        IMAGE_NAME="${IMAGE_NAMES[$num]}"
        IMAGE_ID="${IMAGE_IDS[$num]}"
        
        echo -n "Removing [$num] $IMAGE_NAME... "
        
        # First, stop and remove any containers using this image
        print_debug "Executing: docker ps -a -q --filter ancestor=\"$IMAGE_ID\""
        CONTAINERS=$(docker ps -a -q --filter ancestor="$IMAGE_ID" 2>/dev/null)
        if [[ -n "$CONTAINERS" ]]; then
            print_debug "Executing: docker stop $CONTAINERS"
            docker stop $CONTAINERS >/dev/null 2>&1
            print_debug "Executing: docker rm $CONTAINERS"
            docker rm $CONTAINERS >/dev/null 2>&1
        fi
        
        # Remove the image (force to handle dependencies)
        print_debug "Executing: docker rmi -f \"$IMAGE_ID\""
        if docker rmi -f "$IMAGE_ID" >/dev/null 2>&1; then
            echo -e "${GREEN}Done${NC}"
            ((IMAGES_REMOVED++))
        else
            echo -e "${RED}Failed${NC}"
            print_warning "Could not remove $IMAGE_NAME. It may be in use."
        fi
    done
    
    echo ""
    if [[ $IMAGES_REMOVED -gt 0 ]]; then
        print_success "Removed $IMAGES_REMOVED image(s)."
        
        # Clean up any dangling images and build cache
        print_status "Cleaning up unused data..."
        print_debug "Executing: docker system prune -f"
        docker system prune -f >/dev/null 2>&1
        print_success "Cleanup complete."
    else
        print_status "No images were removed."
    fi
}

# Scan local images with Trivy
trivy_scan_image() {
    echo ""
    print_status "Trivy Security Scan"
    echo ""
    
    # Get list of local images
    print_debug "Executing: docker images --format \"{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}\""
    LOCAL_IMAGES=$(docker images --format "{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}" 2>/dev/null)
    
    if [[ -z "$LOCAL_IMAGES" ]]; then
        print_status "No local Docker images found to scan."
        return
    fi
    
    echo -e "${BLUE}Available images for security scan:${NC}"
    echo ""
    printf "%-5s %-40s %-15s %s\n" "#" "IMAGE" "ID" "SIZE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Display images with numbers and store in arrays
    SCAN_IMAGE_COUNT=0
    declare -a SCAN_IMAGE_NAMES
    declare -a SCAN_IMAGE_IDS
    
    while IFS=$'\t' read -r name id size; do
        ((SCAN_IMAGE_COUNT++))
        SCAN_IMAGE_NAMES[$SCAN_IMAGE_COUNT]="$name"
        SCAN_IMAGE_IDS[$SCAN_IMAGE_COUNT]="$id"
        printf "%-5s %-40s %-15s %s\n" "[$SCAN_IMAGE_COUNT]" "$name" "${id:0:12}" "$size"
    done <<< "$LOCAL_IMAGES"
    
    echo ""
    
    if [[ $SCAN_IMAGE_COUNT -eq 0 ]]; then
        print_status "No local Docker images found to scan."
        return
    fi
    
    echo -e "${YELLOW}Enter an image number to scan with Trivy, or press Enter to skip.${NC}"
    echo ""
    read -p "Select image to scan: " SCAN_SELECTION
    
    if [[ -z "$SCAN_SELECTION" ]]; then
        print_status "Skipping Trivy scan."
        return
    fi
    
    # Validate selection
    if ! [[ "$SCAN_SELECTION" =~ ^[0-9]+$ ]]; then
        print_error "Invalid selection: '$SCAN_SELECTION'"
        return
    fi
    
    if [[ $SCAN_SELECTION -lt 1 || $SCAN_SELECTION -gt $SCAN_IMAGE_COUNT ]]; then
        print_error "Invalid selection: $SCAN_SELECTION (valid: 1-$SCAN_IMAGE_COUNT)"
        return
    fi
    
    SCAN_IMAGE_NAME="${SCAN_IMAGE_NAMES[$SCAN_SELECTION]}"
    print_debug "Selected image: $SCAN_IMAGE_NAME"
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Select scan type:${NC}"
    echo -e "${BLUE}  [1] Quick scan (vulnerabilities only)${NC}"
    echo -e "${BLUE}  [2] Full scan (vulnerabilities + secrets + misconfigurations)${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    read -p "Select scan type (1 or 2, default: 1): " SCAN_TYPE
    
    echo ""
    print_status "Scanning image: $SCAN_IMAGE_NAME"
    echo ""
    
    if [[ "$SCAN_TYPE" == "2" ]]; then
        print_status "Running full Trivy scan (this may take a while)..."
        print_debug "Executing: trivy image --scanners vuln,secret,misconfig \"$SCAN_IMAGE_NAME\""
        trivy image --scanners vuln,secret,misconfig "$SCAN_IMAGE_NAME"
    else
        print_status "Running quick Trivy vulnerability scan..."
        print_debug "Executing: trivy image \"$SCAN_IMAGE_NAME\""
        trivy image "$SCAN_IMAGE_NAME"
    fi
    
    SCAN_EXIT_CODE=$?
    
    echo ""
    if [[ $SCAN_EXIT_CODE -eq 0 ]]; then
        print_success "Trivy scan completed for $SCAN_IMAGE_NAME"
    else
        print_warning "Trivy scan completed with findings for $SCAN_IMAGE_NAME"
    fi
}

# Step 5b: List available Docker images from Docker Hub
list_docker_images() {
    echo ""
    
    # Initialize the search results file
    SEARCH_RESULTS_FILE=$(mktemp)
    SEARCH_COUNT=0
    
    # If logged in, offer to show organization images
    if [[ "$LOGGED_IN" == true && -n "$STORED_NAMESPACE" ]]; then
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BLUE}Choose image source:${NC}"
        echo -e "${BLUE}  [1] Your organization's images ($STORED_NAMESPACE)${NC}"
        echo -e "${BLUE}  [2] Search public Docker Hub images${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        read -p "Select source (1 or 2): " IMAGE_SOURCE
        
        if [[ "$IMAGE_SOURCE" == "1" ]]; then
            list_org_images
            return
        fi
    fi
    
    # Search public Docker Hub images
    search_public_images
}

# List organization's private images
list_org_images() {
    echo ""
    print_status "Fetching repositories for '$STORED_NAMESPACE'..."
    echo ""
    
    # Set org mode flag for pull function
    ORG_MODE=true
    
    REPO_NAMES=""
    
    # Method 1: Try Basic Auth (works best for OAT tokens)
    # Format: curl -u "<org-name>:<oat-token>" 
    print_status "Trying Basic authentication..."
    
    BASIC_AUTH_URL="https://hub.docker.com/v2/repositories/${STORED_NAMESPACE}/?page_size=100"
    print_debug "Executing: curl -s -u \"${STORED_NAMESPACE}:${STORED_TOKEN}\" \"${BASIC_AUTH_URL}\""
    
    REPOS_RESPONSE=$(curl -s -u "${STORED_NAMESPACE}:${STORED_TOKEN}" \
        "${BASIC_AUTH_URL}" 2>/dev/null)
    
    print_debug "Response (first 500 chars): ${REPOS_RESPONSE:0:500}"
    
    REPO_NAMES=$(echo "$REPOS_RESPONSE" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | head -50)
    
    print_debug "Parsed REPO_NAMES: $REPO_NAMES"
    
    if [[ -n "$REPO_NAMES" ]]; then
        print_success "Basic authentication successful!"
    elif [[ "$TOKEN_TYPE" == "oat" ]]; then
        # OAT tokens can only use Basic auth - JWT/Bearer won't work for org accounts
        print_warning "Basic auth didn't return results for OAT token."
        print_status "Note: Docker Hub API may not support listing repos with OAT tokens."
    else
        # Method 2: Try JWT token authentication (works for PAT tokens only)
        print_warning "Basic auth didn't return results. Trying JWT authentication..."
        
        JWT_URL="https://hub.docker.com/v2/users/login/"
        print_debug "Executing: curl -s -X POST -H \"Content-Type: application/json\" -d '{\"username\": \"$STORED_NAMESPACE\", ...}' \"${JWT_URL}\""
        
        JWT_RESPONSE=$(curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "{\"username\": \"$STORED_NAMESPACE\", \"password\": \"$STORED_TOKEN\"}" \
            "${JWT_URL}" 2>/dev/null)
        
        print_debug "JWT Response (first 200 chars): ${JWT_RESPONSE:0:200}"
        
        JWT_TOKEN=$(echo "$JWT_RESPONSE" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
        
        if [[ -n "$JWT_TOKEN" ]]; then
            print_success "JWT authentication successful!"
            
            REPOS_URL="https://hub.docker.com/v2/repositories/$STORED_NAMESPACE/?page_size=100"
            print_debug "Executing: curl -s -H \"Authorization: JWT ${JWT_TOKEN}\" \"${REPOS_URL}\""
            
            REPOS_RESPONSE=$(curl -s \
                -H "Authorization: JWT $JWT_TOKEN" \
                "${REPOS_URL}" 2>/dev/null)
            
            print_debug "Response (first 500 chars): ${REPOS_RESPONSE:0:500}"
            
            REPO_NAMES=$(echo "$REPOS_RESPONSE" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | head -50)
        else
            # Method 3: Try Bearer token directly
            print_warning "JWT auth failed. Trying Bearer token..."
            
            REPOS_URL="https://hub.docker.com/v2/repositories/$STORED_NAMESPACE/?page_size=100"
            print_debug "Executing: curl -s -H \"Authorization: Bearer ${STORED_TOKEN}\" \"${REPOS_URL}\""
            
            REPOS_RESPONSE=$(curl -s \
                -H "Authorization: Bearer $STORED_TOKEN" \
                "${REPOS_URL}" 2>/dev/null)
            
            print_debug "Response (first 500 chars): ${REPOS_RESPONSE:0:500}"
            
            REPO_NAMES=$(echo "$REPOS_RESPONSE" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | head -50)
        fi
    fi
    
    if [[ -z "$REPO_NAMES" ]]; then
        # API listing failed - fall back to manual entry
        echo ""
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${YELLOW}Could not fetch repository list via API.${NC}"
        echo -e "${YELLOW}This may happen with Organization Access Tokens (OAT).${NC}"
        echo -e "${YELLOW}${NC}"
        echo -e "${YELLOW}But you CAN still pull images! Just enter the repository name.${NC}"
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "${GREEN}Example:${NC}"
        echo -e "${GREEN}  Image name:  fsai-os-frontend${NC}"
        echo -e "${GREEN}  Tag:         v1.14.1${NC}"
        echo -e "${GREEN}  Result:      ${STORED_NAMESPACE}/fsai-os-frontend:v1.14.1${NC}"
        echo ""
        
        SEARCH_COUNT=0
        
        echo -e "${BLUE}To see your organization's repositories, visit:${NC}"
        echo -e "${BLUE}https://hub.docker.com/u/${STORED_NAMESPACE}${NC}"
        echo ""
        return
    fi
    
    # Successfully got repository list - display them
    print_success "Found repositories for $STORED_NAMESPACE"
    echo ""
    
    printf "%-5s %-50s\n" "#" "REPOSITORY"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Store repos in temp file for selection
    SEARCH_RESULTS_FILE=$(mktemp)
    SEARCH_COUNT=0
    
    while IFS= read -r repo; do
        if [[ -n "$repo" ]]; then
            ((SEARCH_COUNT++))
            echo "${STORED_NAMESPACE}/${repo}" >> "$SEARCH_RESULTS_FILE"
            printf "%-5s %-50s\n" "[$SEARCH_COUNT]" "${STORED_NAMESPACE}/${repo}"
        fi
    done <<< "$REPO_NAMES"
    
    echo ""
    print_status "Found $SEARCH_COUNT repository(ies)."
    echo ""
}

# Search public Docker Hub images
search_public_images() {
    print_status "Searching public Docker Hub images..."
    echo ""
    
    read -p "Enter a search term (or press Enter for popular images like 'nginx'): " SEARCH_TERM
    
    if [[ -z "$SEARCH_TERM" ]]; then
        SEARCH_TERM="nginx"
    fi
    
    echo ""
    print_status "Searching for '$SEARCH_TERM' images..."
    echo ""
    
    printf "%-5s %-40s %s\n" "#" "NAME" "DESCRIPTION"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    print_debug "Executing: docker search \"$SEARCH_TERM\" --limit 20"
    docker search "$SEARCH_TERM" --limit 20 2>/dev/null | while IFS= read -r line; do
        # Skip the header line
        if [[ "$line" == NAME* ]]; then
            continue
        fi
        
        # Parse the name (first column)
        IMG_NAME=$(echo "$line" | awk '{print $1}')
        # Get description (everything after the name, trimmed)
        DESCRIPTION=$(echo "$line" | awk '{$1=""; print $0}' | sed 's/^[ \t]*//' | cut -c1-50)
        
        if [[ -n "$IMG_NAME" ]]; then
            echo "$IMG_NAME" >> "$SEARCH_RESULTS_FILE"
            CURRENT_COUNT=$(wc -l < "$SEARCH_RESULTS_FILE" | tr -d ' ')
            printf "%-5s %-40s %s\n" "[$CURRENT_COUNT]" "$IMG_NAME" "$DESCRIPTION"
        fi
    done
    
    SEARCH_COUNT=$(wc -l < "$SEARCH_RESULTS_FILE" | tr -d ' ')
    
    echo ""
}

# Step 6 & 7: Ask user which image to pull and pull it
pull_docker_image() {
    if [[ "$ORG_MODE" == true ]]; then
        echo -e "${YELLOW}Enter the repository name (org prefix will be added automatically)${NC}"
        echo -e "${YELLOW}Press Enter to skip pulling.${NC}"
        echo ""
        read -p "Image name (e.g., fsai-os-frontend): " IMAGE_SELECTION
    elif [[ $SEARCH_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}Enter a number from the list above, or type a custom image name (e.g., ubuntu:22.04)${NC}"
        echo -e "${YELLOW}Press Enter to skip pulling.${NC}"
        echo ""
        read -p "Select image to pull: " IMAGE_SELECTION
    else
        echo -e "${YELLOW}Enter an image name to pull (e.g., nginx, ubuntu:22.04)${NC}"
        echo -e "${YELLOW}Press Enter to skip pulling.${NC}"
        echo ""
        read -p "Enter image to pull: " IMAGE_SELECTION
    fi
    
    if [[ -z "$IMAGE_SELECTION" ]]; then
        print_status "No image selected for pulling. Exiting."
        # Cleanup temp file
        [[ -f "$SEARCH_RESULTS_FILE" ]] && rm -f "$SEARCH_RESULTS_FILE"
        return
    fi
    
    # Check if input is a number (selecting from list)
    if [[ "$IMAGE_SELECTION" =~ ^[0-9]+$ ]]; then
        if [[ $IMAGE_SELECTION -lt 1 || $IMAGE_SELECTION -gt $SEARCH_COUNT ]]; then
            print_error "Invalid selection: $IMAGE_SELECTION (valid: 1-$SEARCH_COUNT)"
            [[ -f "$SEARCH_RESULTS_FILE" ]] && rm -f "$SEARCH_RESULTS_FILE"
            exit 1
        fi
        # Get image name from temp file by line number
        IMAGE_NAME=$(sed -n "${IMAGE_SELECTION}p" "$SEARCH_RESULTS_FILE")
        print_status "Selected: $IMAGE_NAME"
    else
        # User typed a custom image name
        IMAGE_NAME="$IMAGE_SELECTION"
        
        # In org mode, auto-prepend org name if not included
        if [[ "$ORG_MODE" == true && "$IMAGE_NAME" != *"/"* ]]; then
            IMAGE_NAME="${STORED_NAMESPACE}/${IMAGE_NAME}"
            print_status "Using full image name: $IMAGE_NAME"
        fi
    fi
    
    # Cleanup temp file
    [[ -f "$SEARCH_RESULTS_FILE" ]] && rm -f "$SEARCH_RESULTS_FILE"
    
    # For org mode, skip tag lookup if user already specified a tag
    if [[ "$ORG_MODE" == true && "$IMAGE_NAME" == *":"* ]]; then
        # User already specified tag, skip lookup
        :
    elif [[ "$ORG_MODE" == true ]]; then
        # Org mode without tag - just ask for tag directly
        echo ""
        read -p "Tag (e.g., v1.14.1, or press Enter for 'latest'): " IMAGE_TAG
        if [[ -z "$IMAGE_TAG" ]]; then
            IMAGE_TAG="latest"
        fi
        IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"
    else
        # Fetch and display available tags for the selected image
        echo ""
        print_status "Fetching available tags for '$IMAGE_NAME'..."
        echo ""
        
        # Determine API URL based on whether it's an official image or user image
        if [[ "$IMAGE_NAME" == *"/"* ]]; then
            # User/org image (e.g., nginx/nginx-ingress)
            API_URL="https://hub.docker.com/v2/repositories/${IMAGE_NAME}/tags?page_size=20"
        else
            # Official image (e.g., nginx, ubuntu)
            API_URL="https://hub.docker.com/v2/repositories/library/${IMAGE_NAME}/tags?page_size=20"
        fi
        
        # Fetch tags from Docker Hub API
        print_debug "Executing: curl -s \"$API_URL\""
        TAGS_RESPONSE=$(curl -s "$API_URL" 2>/dev/null)
        print_debug "Response (first 300 chars): ${TAGS_RESPONSE:0:300}"
        
        # Parse and display tags
        TAGS_FILE=$(mktemp)
        TAG_COUNT=0
        
        # Extract tag names from JSON response
        echo "$TAGS_RESPONSE" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | while read -r tag; do
            if [[ -n "$tag" ]]; then
                ((TAG_COUNT++))
                echo "$tag" >> "$TAGS_FILE"
            fi
        done
        
        TAG_COUNT=$(wc -l < "$TAGS_FILE" | tr -d ' ')
        
        if [[ $TAG_COUNT -gt 0 ]]; then
            echo -e "${BLUE}Available tags for $IMAGE_NAME:${NC}"
            echo ""
            printf "%-5s %s\n" "#" "TAG"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            
            LINE_NUM=0
            while read -r tag; do
                ((LINE_NUM++))
                printf "%-5s %s\n" "[$LINE_NUM]" "$tag"
            done < "$TAGS_FILE"
            
            echo ""
            echo -e "${YELLOW}Enter a number, type a tag name, or press Enter for 'latest'${NC}"
            read -p "Select tag: " TAG_SELECTION
            
            if [[ -z "$TAG_SELECTION" ]]; then
                IMAGE_TAG="latest"
            elif [[ "$TAG_SELECTION" =~ ^[0-9]+$ ]]; then
                if [[ $TAG_SELECTION -ge 1 && $TAG_SELECTION -le $TAG_COUNT ]]; then
                    IMAGE_TAG=$(sed -n "${TAG_SELECTION}p" "$TAGS_FILE")
                else
                    print_warning "Invalid selection, using 'latest'"
                    IMAGE_TAG="latest"
                fi
            else
                IMAGE_TAG="$TAG_SELECTION"
            fi
            
            rm -f "$TAGS_FILE"
        else
            print_warning "Could not fetch tags. Using 'latest' or enter a custom tag."
            read -p "Enter tag (or press Enter for 'latest'): " IMAGE_TAG
            if [[ -z "$IMAGE_TAG" ]]; then
                IMAGE_TAG="latest"
            fi
        fi
        
        # Append tag if not already included
        if [[ "$IMAGE_NAME" != *":"* ]]; then
            IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"
        fi
    fi
    
    echo ""
    print_status "Pulling image: $IMAGE_NAME"
    print_debug "Executing: docker pull \"$IMAGE_NAME\""
    docker pull "$IMAGE_NAME"
    
    if [[ $? -eq 0 ]]; then
        print_success "Successfully pulled $IMAGE_NAME!"
        echo ""
        print_status "Your local Docker images:"
        print_debug "Executing: docker images"
        docker images
        
        # Open Docker Desktop GUI
        echo ""
        print_status "Opening Docker Desktop..."
        print_debug "Executing: open -a Docker"
        open -a Docker
        print_success "Docker Desktop launched! You can view your images in the GUI."
    else
        print_error "Failed to pull $IMAGE_NAME"
        exit 1
    fi
}

# Main execution
main() {
    echo ""
    echo "=========================================="
    echo "       Docker Image Pull Script"
    echo "=========================================="
    echo ""
    
    # Initialize status variables
    LOGGED_IN=false
    ORG_MODE=false
    
    # Step 1-3: Ensure Homebrew, Docker, and Trivy are installed
    check_and_install_homebrew
    check_and_install_docker
    check_and_install_trivy
    
    # Step 4: Manage existing local images (before login)
    manage_existing_images
    
    # Step 4b: Offer Trivy security scan of local images
    trivy_scan_image
    
    # Step 5: Docker Hub authentication (optional)
    docker_hub_login
    
    if [[ "$LOGGED_IN" == false ]]; then
        echo ""
        print_status "Running without authentication - only public images are available."
    fi
    
    # Step 6: List available images from Docker Hub
    list_docker_images
    
    # Step 7: Pull selected image
    pull_docker_image
    
    echo ""
    print_success "Script completed!"
}

main

