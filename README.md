# Docker Image Pull Script

A bash script that simplifies pulling Docker images from Docker Hub, with support for both public images and private organization repositories. Includes security scanning with Trivy.

## Features

- ✅ **Auto-installs dependencies** - Installs Homebrew, Docker, and Trivy if not present
- ✅ **Manages local images** - Review and remove existing Docker images before pulling new ones
- ✅ **Security scanning with Trivy** - Scan local images for vulnerabilities, secrets, and misconfigurations
- ✅ **Supports Organization Access Tokens (OAT)** - Pull from private org repositories
- ✅ **Supports Personal Access Tokens (PAT)** - For personal Docker Hub accounts
- ✅ **Credential storage** - Save credentials locally (git-ignored) for convenience
- ✅ **Tag selection** - Browse available tags or enter custom ones
- ✅ **Debug mode** - See all CLI commands being executed for troubleshooting
- ✅ **Auto-launches Docker Desktop** - Opens the GUI after pulling images

## Quick Start

```bash
./docker-image-pull.sh
```

## Configuration

### Saving Credentials

You can save your Docker Hub credentials to avoid entering them each time:

1. **Option A**: Let the script save them after successful login
2. **Option B**: Edit `.docker-credentials` directly:

```bash
# For Organization Access Token (OAT)
DEBUG=false
TOKEN_TYPE="oat"
DOCKER_ORG="your-org-name"
DOCKER_TOKEN="dckr_oat_xxxxx"
```

```bash
# For Personal Access Token (PAT)
DEBUG=false
TOKEN_TYPE="pat"
DOCKER_USERNAME="your-username"
DOCKER_TOKEN="dckr_pat_xxxxx"
```

### Debug Mode

Enable debug mode to see all CLI commands being executed:

```bash
# In .docker-credentials
DEBUG=true
```

When enabled, you'll see output like:
```
[DEBUG] Executing: docker images --format "{{.Repository}}:{{.Tag}}..."
[DEBUG] Executing: curl -s -u "org-name:token" "https://hub.docker.com/v2/..."
[DEBUG] Response (first 500 chars): {"count":5,"results":[...]}
[DEBUG] Executing: trivy image "nginx:latest"
```

### Getting a Docker Hub Access Token

1. Go to [Docker Hub Security Settings](https://hub.docker.com/settings/security)
2. Click **New Access Token**
3. Give it a name and select permissions
4. Copy the token (it won't be shown again)

## Script Flow

1. **Check Dependencies** - Installs Homebrew, Docker, and Trivy if needed
2. **Manage Local Images** - Shows existing images, offers to remove unwanted ones
3. **Security Scan** - Offers to scan local images with Trivy
4. **Docker Hub Login** - Optional authentication for private repos
5. **Browse/Search Images** - List org repos or search public images
6. **Pull Image** - Download the selected image with chosen tag
7. **Launch Docker Desktop** - Opens the GUI to view your images

## Usage Examples

### Pulling a Public Image

```
Do you want to login to Docker Hub? (y/n, default: n): n

[INFO] Searching for 'nginx' images...

#     NAME                                     DESCRIPTION
[1]   nginx                                    Official build of Nginx.
[2]   nginx/nginx-ingress                      NGINX Ingress Controller

Select image to pull: 1
Tag (e.g., latest, alpine): latest

[INFO] Pulling image: nginx:latest
```

### Pulling a Private Organization Image

```
Do you want to login to Docker Hub? (y/n, default: n): y
Use saved credentials? (y/n, default: y): y

[INFO] Using credentials for organization: futuresecureai
[SUCCESS] Successfully logged in to Docker Hub!

Choose image source:
  [1] Your organization's images (futuresecureai)
  [2] Search public Docker Hub images

Select source (1 or 2): 1

Example:
  Image name:  fsai-os-frontend
  Tag:         v1.14.1
  Result:      futuresecureai/fsai-os-frontend:v1.14.1

Image name (e.g., fsai-os-frontend): fsai-os-frontend
Tag (e.g., v1.14.1, or press Enter for 'latest'): v1.14.1

[INFO] Pulling image: futuresecureai/fsai-os-frontend:v1.14.1
```

### Security Scanning with Trivy

```
[INFO] Trivy Security Scan

Available images for security scan:

#     IMAGE                                    ID              SIZE
[1]   nginx:latest                             fb01117203ff    244MB
[2]   futuresecureai/fsai-os-frontend:v1.14.1  66f0bd02b801    335MB

Enter an image number to scan with Trivy, or press Enter to skip.

Select image to scan: 1

Select scan type:
  [1] Quick scan (vulnerabilities only)
  [2] Full scan (vulnerabilities + secrets + misconfigurations)

Select scan type (1 or 2, default: 1): 1

[INFO] Running quick Trivy vulnerability scan...

nginx:latest (debian 12.4)
===========================
Total: 142 (UNKNOWN: 0, LOW: 85, MEDIUM: 45, HIGH: 10, CRITICAL: 2)
```

### Managing Local Images

```
[INFO] Checking for existing Docker images on your system...

#     IMAGE                                    ID              SIZE
[1]   nginx:latest                             fb01117203ff    244MB
[2]   ubuntu:22.04                             e4c58958181a    77.8MB

To remove images, enter the numbers separated by commas (e.g., 1,3,5)
Press Enter to keep all images.

Enter image numbers to remove: 1

Removing [1] nginx:latest... Done
[SUCCESS] Removed 1 image(s).
```

## Files

| File | Description |
|------|-------------|
| `docker-image-pull.sh` | Main script |
| `.docker-credentials` | Your saved credentials (git-ignored) |
| `.gitignore` | Ensures credentials aren't committed |
| `README.md` | This documentation |

## Security Notes

- `.docker-credentials` is automatically git-ignored
- Never commit access tokens to version control
- Rotate tokens periodically at [Docker Hub Security Settings](https://hub.docker.com/settings/security)
- Use Trivy to scan images for vulnerabilities before deploying

## Requirements

- macOS (uses Homebrew for Docker installation)
- Internet connection

## Installed Tools

The script automatically installs these tools if not present:

| Tool | Purpose |
|------|---------|
| Homebrew | Package manager for macOS |
| Docker Desktop | Container runtime |
| Trivy | Security scanner for containers |

## Troubleshooting

### "unauthorized: incorrect username or password"

- **For OAT**: Make sure you're using the **organization name**, not your personal username
- **For PAT**: Make sure you're using your **Docker Hub username**, not your email
- Verify your token hasn't expired

### "Cannot log into an organization account" warning

This warning from Docker Desktop's credential helper is suppressed by the script. The CLI login still works correctly - it's just Docker Desktop's background sync feature that doesn't support org accounts.

### Can't list organization repositories

Docker Hub's API has limited support for listing repositories with OAT tokens. The script tries multiple authentication methods:
1. Basic auth (`-u org:token`)
2. JWT authentication (PAT only)
3. Bearer token

If listing fails, just enter the image name directly - you can view your repos at `https://hub.docker.com/u/YOUR_ORG_NAME`.

### Debug mode not showing output

Make sure `DEBUG=true` is set in your `.docker-credentials` file. The debug setting is loaded at script startup.

### Trivy scan shows many vulnerabilities

This is normal - most base images have known vulnerabilities. Focus on:
- **CRITICAL** and **HIGH** severity issues
- Vulnerabilities with available fixes
- Consider using minimal base images (e.g., `alpine` variants)
