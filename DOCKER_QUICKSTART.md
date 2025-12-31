# Docker Quick Start Guide

This guide helps you run the SynQc application using Docker Compose.

## Prerequisites

- Docker Desktop installed and running
- WSL 2 enabled (Windows only)
- Git Bash (optional, for running .sh scripts on Windows)

## Quick Start

### Windows (PowerShell or Command Prompt)

```cmd
docker-start.bat
```

### Linux/Mac/Git Bash

```bash
chmod +x docker-start.sh
./docker-start.sh
```

This will:
1. Validate your Docker setup
2. Check for required files
3. Build and start all services
4. Display service URLs

## Services

Once started, you can access:

- **API**: http://localhost:8001
- **API Docs**: http://localhost:8001/docs  
- **Web UI**: http://localhost:8080
- **Redis**: localhost:6379 (from host only)

## Common Commands

### Start services
```bash
docker compose up -d
```

### Start with rebuild
```bash
docker compose up --build -d
```

### View logs
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f api
docker compose logs -f redis
docker compose logs -f web
```

### Stop services
```bash
docker compose down
```

### Stop and remove volumes
```bash
docker compose down -v
```

### Check service status
```bash
docker compose ps
```

### Health check
```bash
# Linux/Mac/Git Bash
chmod +x docker-health-check.sh
./docker-health-check.sh

# Manual checks
curl http://localhost:8001/health
docker compose exec redis redis-cli ping
```

## Troubleshooting

### Services won't start

1. **Check Docker is running**:
   ```bash
   docker info
   ```

2. **Check for port conflicts**:
   ```bash
   # Windows
   netstat -ano | findstr ":8001"
   netstat -ano | findstr ":8080"
   
   # Linux/Mac
   lsof -i :8001
   lsof -i :8080
   ```

3. **Clean rebuild**:
   ```bash
   docker compose down -v
   docker compose up --build
   ```

### Health checks failing

1. **View logs**:
   ```bash
   docker compose logs api
   ```

2. **Increase timeout**: Edit `docker-compose.yml` and increase `start_period` in healthcheck

3. **Test manually**:
   ```bash
   docker compose exec api python /app/backend/healthcheck.py
   ```

### Module not found errors

The `ops` directory has been renamed to `_ops` to fix package discovery issues. If you see module errors:

1. Ensure `_ops` directory exists (not `ops`)
2. Rebuild containers:
   ```bash
   docker compose build --no-cache api
   docker compose up -d
   ```

### Redis connection errors

```bash
# Check Redis is running
docker compose ps redis

# Test Redis
docker compose exec redis redis-cli ping

# Restart Redis
docker compose restart redis
```

## Advanced Usage

### Custom environment variables

Create a `.env` file in the project root:

```env
# Redis configuration
SYNQC_REDIS_URL=redis://redis:6379/0

# API configuration  
SYNQC_REQUIRE_API_KEY=false
SYNQC_HEALTH_CACHE_TTL_SECONDS=3

# Worker configuration
UVICORN_WORKERS=1
```

### Development workflow

1. **Make code changes** in `backend/` or `web/`

2. **Rebuild affected service**:
   ```bash
   # Backend only
   docker compose up --build -d api
   
   # Frontend only
   docker compose up --build -d web
   ```

3. **View logs**:
   ```bash
   docker compose logs -f api
   ```

### Accessing containers

```bash
# API container
docker compose exec api bash

# Redis CLI
docker compose exec redis redis-cli

# View API environment
docker compose exec api env
```

### Data persistence

Data is persisted in Docker volumes:
- `synqc_data`: Application data
- `synqc_redis_data`: Redis persistence

To inspect:
```bash
docker volume ls
docker volume inspect synqc_data
```

To backup:
```bash
docker run --rm -v synqc_data:/data -v $(pwd):/backup alpine tar czf /backup/synqc-backup.tar.gz /data
```

## Architecture

```
┌─────────────────┐
│   Web (nginx)   │  :8080
│   Reverse Proxy │
└────────┬────────┘
         │ /api/*
         ↓
┌─────────────────┐
│   API (FastAPI) │  :8001
│   uvicorn       │
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│   Redis         │  :6379
│   (internal)    │
└─────────────────┘
```

## More Help

- See [DOCKER_TROUBLESHOOTING.md](DOCKER_TROUBLESHOOTING.md) for detailed troubleshooting
- View Docker logs: `docker compose logs -f`
- Check main [README.md](README.md) for project documentation
- Test API at http://localhost:8001/docs

## Cleaning Up

### Remove all containers and volumes
```bash
docker compose down -v
```

### Remove Docker images
```bash
docker compose down --rmi all
```

### Complete system cleanup
```bash
docker system prune -a
docker volume prune
```

**Warning**: This removes all unused Docker resources, not just this project!
