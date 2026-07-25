# Updating LibreChat custom image

## 1. Pull Fresh Upstream Code

Navigate to your local repository workspace and pull the latest changes from the official LibreChat upstream repository:

```bash
git remote add upstream https://github.com/danny-avila/LibreChat.git
git fetch upstream
git merge upstream/main
```

## 2. Update Dependencies

Run the package update command to pull in the latest dependency updates:

```bash
npm update
```

## 3. Verify and Re-apply Custom Logic

* Check your manual patches and custom code (stored locally in the `patches/` folder and your custom `Dockerfile.custom`) against any upstream code changes.
* Confirm that the modified file paths, Docker build instructions, and custom `$all` filter validation logic still align with the current codebase structure.

## 4. Rebuild the Custom Docker Image Locally

Rebuild your local container image using your custom Dockerfile to bake in the updated code and your verified custom patches:

```bash
docker build -f Dockerfile.custom -t yvchenko/librechat-custom-tagging:latest .
```

## 5. Push to the Image Registry

Push your newly built, patched image up to your container registry so your production server can access it:

```bash
docker push yvchenko/librechat-custom-tagging:latest
```

## 6. Deploy on Production Server

SSH into your remote Ubuntu server, navigate to your deployment directory, and execute the rollout sequence:

```bash
docker compose pull api && docker compose up -d --force-recreate
```