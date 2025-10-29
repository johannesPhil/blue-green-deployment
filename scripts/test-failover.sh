#!/bin/bash
set -e

NGINX_URL="${NGINX_URL:-http://localhost:8080}"
BLUE_URL="${BLUE_URL:-http://localhost:8081}"
GREEN_URL="${GREEN_URL:-http://localhost:8082}"

echo "🧪 Blue/Green Failover Test"
echo "============================"
echo ""

# Test 1: Baseline - Blue is active
echo "📊 Test 1: Baseline (Blue Active)"
for i in {1..5}; do
    response=$(curl -s -w "\nHTTP_CODE:%{http_code}" "$NGINX_URL/version")
    http_code=$(echo "$response" | grep HTTP_CODE | cut -d: -f2)
    body=$(echo "$response" | grep -v HTTP_CODE)
    
    pool=$(echo "$body" | jq -r '.headers["x-app-pool"] // .headers["X-App-Pool"] // "unknown"')
    release=$(echo "$body" | jq -r '.headers["x-release-id"] // .headers["X-Release-Id"] // "unknown"')
    
    echo "  Request $i: HTTP $http_code | Pool: $pool | Release: $release"
    
    if [ "$http_code" != "200" ]; then
        echo "❌ FAIL: Expected 200, got $http_code"
        exit 1
    fi
    
    if [ "$pool" != "blue" ]; then
        echo "❌ FAIL: Expected blue, got $pool"
        exit 1
    fi
done

echo "✅ All requests served by Blue"
echo ""

# Test 2: Induce chaos on Blue
echo "💥 Test 2: Inducing Chaos on Blue"
chaos_response=$(curl -s -X POST "$BLUE_URL/chaos/start?mode=error" || echo "FAILED")
echo "  Chaos response: $chaos_response"
sleep 2
echo ""

# Test 3: Verify automatic failover to Green
echo "🔄 Test 3: Automatic Failover (10 requests)"
green_count=0
error_count=0

for i in {1..10}; do
    response=$(curl -s -w "\nHTTP_CODE:%{http_code}" "$NGINX_URL/version" 2>/dev/null || echo "HTTP_CODE:000")
    http_code=$(echo "$response" | grep HTTP_CODE | cut -d: -f2)
    body=$(echo "$response" | grep -v HTTP_CODE)
    
    pool=$(echo "$body" | jq -r '.headers["x-app-pool"] // .headers["X-App-Pool"] // "unknown"' 2>/dev/null || echo "unknown")
    
    echo "  Request $i: HTTP $http_code | Pool: $pool"
    
    if [ "$http_code" != "200" ]; then
        ((error_count++))
        echo "    ⚠️  Non-200 response"
    fi
    
    if [ "$pool" = "green" ]; then
        ((green_count++))
    fi
    
    sleep 0.5
done

echo ""
echo "Results:"
echo "Green responses: $green_count/10 ($((green_count * 10))%)"
echo "Failed requests: $error_count/10"
echo ""

# Validation
if [ $error_count -gt 0 ]; then
    echo "❌ FAIL: Found $error_count non-200 responses (expected 0)"
    exit 1
fi

green_percentage=$((green_count * 100 / 10))
if [ $green_percentage -lt 95 ]; then
    echo "❌ FAIL: Only $green_percentage% from Green (need ≥95%)"
    exit 1
fi

# Test 4: Stop chaos
echo "🛑 Stopping Chaos..."
curl -s -X POST "$BLUE_URL/chaos/stop" > /dev/null 2>&1 || true
echo ""

echo "✅ ALL TESTS PASSED!"
echo "============================"