#!/bin/bash

# Docker Image Pull Script
# This script helps pull images from Docker Hub (supports both public and private org repos)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Step 1 & 2 & 3: Check for Homebrew, then Docker
check_and_install_homebrew() {
    if ! command -v brew &> /dev/null; then
        print_warning "Homebrew is not installed."
        print_status "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        
        # Add Homebrew to PATH for Apple Silicon Macs
        if [[ $(uname -m) == "arm64" ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
        
        print_success "Homebrew installed successfully!"
    else
        print_success "Homebrew is already installed."
    fi
}

check_and_install_docker() {
    if ! command -v docker &> /dev/null; then
        print_warning "Docker CLI is not installed."
        print_status "Installing Docker via Homebrew..."
        brew install --cask docker
        print_success "Docker installed successfully!"
        print_warning "Please start Docker Desktop from your Applications folder before continuing."
        read -p "Press Enter once Docker Desktop is running..."
    else
        print_success "Docker CLI is already installed."
    fi
    
    # Verify Docker daemon is running
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running. Please start Docker Desktop and try again."
        exit 1
    fi
    
    print_success "Docker daemon is running."
}

# Config file path
CONFIG_FILE="$(dirname "$0")/.docker-credentials"

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
            
            # Use DOCKER_ORG for OAT tokens, fall back to DOCKER_USERNAME for backward compatibility
            if [[ "$TOKEN_TYPE" == "oat" && -n "$DOCKER_ORG" ]]; then
                CONFIG_USERNAME="$DOCKER_ORG"
            elif [[ -n "$DOCKER_USERNAME" ]]; then
                CONFIG_USERNAME="$DOCKER_USERNAME"
            else
                CONFIG_USERNAME=""
            fi
            
            if [[ -n "$CONFIG_USERNAME" && -n "$DOCKER_TOKEN" && "$DOCKER_TOKEN" != "your-token-here" ]]; then
                print_status "Using credentials for organization: $CONFIG_USERNAME"
                
                # Login to Docker Hub
                echo "$DOCKER_TOKEN" | docker login -u "$CONFIG_USERNAME" --password-stdin
                
                if [[ $? -eq 0 ]]; then
                    print_success "Successfully logged in to Docker Hub!"
                    LOGGED_IN=true
                    STORED_USERNAME="$CONFIG_USERNAME"
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
    echo "$DOCKER_TOKEN" | docker login -u "$DOCKER_USERNAME" --password-stdin
    
    if [[ $? -eq 0 ]]; then
        print_success "Successfully logged in to Docker Hub!"
        LOGGED_IN=true
        # Store credentials for API calls
        STORED_USERNAME="$DOCKER_USERNAME"
        STORED_TOKEN="$DOCKER_TOKEN"
        
        # Offer to save credentials
        echo ""
        read -p "Save credentials to config file for future use? (y/n): " SAVE_CREDS
        if [[ "$SAVE_CREDS" =~ ^[Yy]$ ]]; then
            if [[ "$TOKEN_TYPE_INPUT" == "1" ]]; then
                cat > "$CONFIG_FILE" << EOF
# Docker Hub Credentials
# This file is ignored by git - safe to store credentials here

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
        CONTAINERS=$(docker ps -a -q --filter ancestor="$IMAGE_ID" 2>/dev/null)
        if [[ -n "$CONTAINERS" ]]; then
            docker stop $CONTAINERS >/dev/null 2>&1
            docker rm $CONTAINERS >/dev/null 2>&1
        fi
        
        # Remove the image (force to handle dependencies)
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
        docker system prune -f >/dev/null 2>&1
        print_success "Cleanup complete."
    else
        print_status "No images were removed."
    fi
}

# Step 5b: List available Docker images from Docker Hub
list_docker_images() {
    echo ""
    
    # Initialize the search results file
    SEARCH_RESULTS_FILE=$(mktemp)
    SEARCH_COUNT=0
    
    # If logged in, offer to show organization images
    if [[ "$LOGGED_IN" == true && -n "$STORED_USERNAME" ]]; then
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BLUE}Choose image source:${NC}"
        echo -e "${BLUE}  [1] Your organization's images ($STORED_USERNAME)${NC}"
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
    print_status "Organization image mode for '$STORED_USERNAME'"
    echo ""
    
    # Docker Hub API limitation: Organization Access Tokens can't list repos via API
    # But they CAN pull images. So we let the user enter the image name directly.
    
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Note: Docker Hub's API doesn't support listing private repos${NC}"
    echo -e "${YELLOW}with Organization Access Tokens.${NC}"
    echo -e "${YELLOW}${NC}"
    echo -e "${YELLOW}But you CAN pull images! Just enter the repository name.${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${GREEN}Example:${NC}"
    echo -e "${GREEN}  Image name:  fsai-os-frontend${NC}"
    echo -e "${GREEN}  Tag:         v1.14.1${NC}"
    echo -e "${GREEN}  Result:      ${STORED_USERNAME}/fsai-os-frontend:v1.14.1${NC}"
    echo ""
    
    # Set org mode flag for pull function
    ORG_MODE=true
    SEARCH_COUNT=0
    
    echo -e "${BLUE}To see your organization's repositories, visit:${NC}"
    echo -e "${BLUE}https://hub.docker.com/u/${STORED_USERNAME}${NC}"
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
            IMAGE_NAME="${STORED_USERNAME}/${IMAGE_NAME}"
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
        TAGS_RESPONSE=$(curl -s "$API_URL" 2>/dev/null)
        
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
    docker pull "$IMAGE_NAME"
    
    if [[ $? -eq 0 ]]; then
        print_success "Successfully pulled $IMAGE_NAME!"
        echo ""
        print_status "Your local Docker images:"
        docker images
        
        # Open Docker Desktop GUI
        echo ""
        print_status "Opening Docker Desktop..."
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
    
    # Step 1-3: Ensure Homebrew and Docker are installed
    check_and_install_homebrew
    check_and_install_docker
    
    # Step 4: Manage existing local images (before login)
    manage_existing_images
    
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

