# Docker Troubleshooting Guide

## Common Issues and Solutions

### 1. Docker Compose Build Failures

**Symptom**: Error during `docker compose up --build`

**Solutions**:
- Ensure Docker Desktop is running
- Check that WSL 2 is installed and configured (Windows)
- Verify all required files exist:
  - `backend/Dockerfile`
  - `backend/pyproject.toml`
  - `web/Dockerfile`
  - `web/nginx.conf`
  - `docker-compose.yml`

**Quick Fix**:
```bash
# Clean rebuild
docker compose down -v
docker compose up --build
```

### 2. Health Check Failures

**Symptom**: Services restart repeatedly or show as unhealthy

**Solutions**:
- Check if ports 8001, 8080, or 6379 are already in use
- Review logs: `docker compose logs api`
- Ensure the backend starts before health checks begin

**Check ports**:
```bash
# Windows
netstat -ano | findstr ":8001"
netstat -ano | findstr ":8080"
netstat -ano | findstr ":6379"

# Linux/Mac
lsof -i :8001
lsof -i :8080
lsof -i :6379
```

### 3. Missing Module Errors

**Symptom**: `ModuleNotFoundError: No module named 'synqc_backend'`

**Solution**:
The `ops` directory was renamed to `_ops` to fix package discovery issues. Ensure:
1. The directory is named `_ops` not `ops`
2. It's excluded in `.dockerignore`
3. Rebuild the container: `docker compose up --build -d api`

### 4. Redis Connection Errors

**Symptom**: API logs show Redis connection failures

**Solutions**:
- Verify Redis is running: `docker compose ps redis`
- Check Redis health: `docker compose exec redis redis-cli ping`
- Restart Redis: `docker compose restart redis`

### 5. Web Service Cannot Connect to API

**Symptom**: Web UI shows connection errors

**Solutions**:
- Ensure API is healthy: `docker compose ps api`
- Check nginx configuration in `web/nginx.conf`
- Verify the proxy_pass points to `http://api:8001`

### 6. Permission Errors

**Symptom**: Cannot write to volumes or directories

**Solutions**:
```bash
# Linux/Mac: Fix volume permissions
docker compose down
docker volume rm synqc_data synqc_redis_data
docker compose up
```

### 7. Slow Build Times

**Solution**: Use BuildKit for faster builds
```bash
# Windows PowerShell
$env:DOCKER_BUILDKIT=1
docker compose build

# Linux/Mac/Git Bash
export DOCKER_BUILDKIT=1
docker compose build
```

## Health Check Commands

### Check all services status
```bash
docker compose ps
```

### Check specific service logs
```bash
docker compose logs -f api
docker compose logs -f redis
docker compose logs -f web
```

### Test API health endpoint
```bash
curl http://localhost:8001/health
```

### Test Redis
```bash
docker compose exec redis redis-cli ping
```

### Restart specific service
```bash
docker compose restart api
docker compose restart redis
docker compose restart web
```

## Complete Reset

If all else fails, perform a complete reset:

```bash
# Stop everything
docker compose down -v

# Remove all containers and images (optional)
docker system prune -a

# Rebuild from scratch
docker compose up --build
```

## Git Bash Specific Issues

When using Git Bash on Windows:

1. **Path issues**: Use forward slashes `/` or escape backslashes `\\`
2. **Line endings**: Ensure scripts use LF, not CRLF
   ```bash
   git config core.autocrlf input
   ```
3. **Script execution**: Make scripts executable
   ```bash
   chmod +x docker-start.sh
   ./docker-start.sh
   ```

## Environment Variables

Create a `.env` file in the root directory for custom configuration:

```env
# Redis
SYNQC_REDIS_URL=redis://redis:6379/0

# API
SYNQC_REQUIRE_API_KEY=false
SYNQC_HEALTH_CACHE_TTL_SECONDS=3

# Worker
UVICORN_WORKERS=1
```

## Getting Help

1. Check logs: `docker compose logs -f`
2. Inspect container: `docker compose exec api sh`
3. Review this guide
4. Check the main README.md for additional documentation
