#!/bin/bash
# Docker Compose Health Validation Script
# Tests all services and provides detailed status

set -e

echo "======================================"
echo "SynQc Docker Health Check"
echo "======================================"
echo ""

# Function to check if a service is running
check_service() {
    local service=$1
    local status=$(docker compose ps $service --format json 2>/dev/null | grep -o '"State":"[^"]*"' | cut -d'"' -f4)
    
    if [ "$status" == "running" ]; then
        echo "✓ $service is running"
        return 0
    else
        echo "✗ $service is not running (state: $status)"
        return 1
    fi
}

# Function to check service health
check_health() {
    local service=$1
    local health=$(docker compose ps $service --format json 2>/dev/null | grep -o '"Health":"[^"]*"' | cut -d'"' -f4)
    
    if [ "$health" == "healthy" ] || [ -z "$health" ]; then
        echo "  ✓ Health check: ${health:-no health check configured}"
        return 0
    else
        echo "  ✗ Health check: $health"
        return 1
    fi
}

# Check if docker-compose is running
if ! docker compose ps >/dev/null 2>&1; then
    echo "❌ Docker Compose services not found"
    echo "   Run './docker-start.sh' first"
    exit 1
fi

echo "Checking services..."
echo ""

# Check each service
services=("redis" "api" "web")
failed=0

for service in "${services[@]}"; do
    echo "[$service]"
    if check_service $service; then
        check_health $service
    else
        failed=$((failed + 1))
    fi
    echo ""
done

# Test connectivity
echo "Testing connectivity..."
echo ""

# Test Redis
echo "[Redis Ping]"
if docker compose exec -T redis redis-cli ping >/dev/null 2>&1; then
    echo "  ✓ Redis responds to PING"
else
    echo "  ✗ Redis not responding"
    failed=$((failed + 1))
fi
echo ""

# Test API health endpoint
echo "[API Health]"
if curl -f -s http://localhost:8001/health >/dev/null 2>&1; then
    echo "  ✓ API health endpoint responding"
    echo "  Response:"
    curl -s http://localhost:8001/health | python3 -m json.tool 2>/dev/null || echo "  (JSON formatting unavailable)"
else
    echo "  ✗ API health endpoint not responding"
    failed=$((failed + 1))
fi
echo ""

# Test Web
echo "[Web Service]"
if curl -f -s http://localhost:8080 >/dev/null 2>&1; then
    echo "  ✓ Web server responding"
else
    echo "  ✗ Web server not responding"
    failed=$((failed + 1))
fi
echo ""

# Summary
echo "======================================"
if [ $failed -eq 0 ]; then
    echo "✓ All checks passed!"
    echo "======================================"
    echo ""
    echo "Services are healthy and ready:"
    echo "  - API:  http://localhost:8001"
    echo "  - Docs: http://localhost:8001/docs"
    echo "  - Web:  http://localhost:8080"
    exit 0
else
    echo "✗ $failed check(s) failed"
    echo "======================================"
    echo ""
    echo "View logs with:"
    echo "  docker compose logs -f"
    echo ""
    echo "See DOCKER_TROUBLESHOOTING.md for help"
    exit 1
fi
