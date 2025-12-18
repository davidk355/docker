# Docker Image Pull Script

A bash script that simplifies pulling Docker images from Docker Hub, with support for both public images and private organization repositories.

## Features

- ✅ **Auto-installs dependencies** - Installs Homebrew and Docker if not present
- ✅ **Manages local images** - Review and remove existing Docker images before pulling new ones
- ✅ **Supports Organization Access Tokens (OAT)** - Pull from private org repositories
- ✅ **Supports Personal Access Tokens (PAT)** - For personal Docker Hub accounts
- ✅ **Credential storage** - Save credentials locally (git-ignored) for convenience
- ✅ **Tag selection** - Browse available tags or enter custom ones
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
TOKEN_TYPE="oat"
DOCKER_ORG="your-org-name"
DOCKER_TOKEN="dckr_oat_xxxxx"
```

```bash
# For Personal Access Token (PAT)
TOKEN_TYPE="pat"
DOCKER_USERNAME="your-username"
DOCKER_TOKEN="dckr_pat_xxxxx"
```

### Getting a Docker Hub Access Token

1. Go to [Docker Hub Security Settings](https://hub.docker.com/settings/security)
2. Click **New Access Token**
3. Give it a name and select permissions
4. Copy the token (it won't be shown again)

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

## Security Notes

- `.docker-credentials` is automatically git-ignored
- Never commit access tokens to version control
- Rotate tokens periodically at [Docker Hub Security Settings](https://hub.docker.com/settings/security)

## Requirements

- macOS (uses Homebrew for Docker installation)
- Internet connection

## Troubleshooting

### "unauthorized: incorrect username or password"

- **For OAT**: Make sure you're using the **organization name**, not your personal username
- **For PAT**: Make sure you're using your **Docker Hub username**, not your email
- Verify your token hasn't expired

### "Cannot log into an organization account" warning

This is normal when using Organization Access Tokens. It's a Docker Desktop GUI limitation - the CLI login still works.

### Can't list organization repositories

Docker Hub's API doesn't support listing private repos with OAT tokens. Just enter the image name directly - you can view your repos at `https://hub.docker.com/u/YOUR_ORG_NAME`.

