#!/bin/bash
# Validate Quant Services in Dev Lab Registry
# This script checks if all required images are available in the local registry

set -o pipefail  # More permissive than set -e but still catches pipeline failures

LOCAL_REGISTRY_EXTERNAL="localhost:5000"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Validating quant services in dev-lab registry${NC}"
echo "=============================================="

# Expected services
SERVICES=(
    "adh-consumer"
    "betticker-ws" 
    "dash-auth"
    "dash-ws"
    "external-prices-gather"
    "nba-livescores"
    "news-gather"
    "rapid-pini-feeder"
    "rw-proj-min"
    "rw-proj-min-store"
    "unabated-news-feeder"
    "wnba-reports"
)

# Smart port forwarding setup - detect existing port forwards
echo -e "${BLUE}🔧 Setting up registry connectivity...${NC}"

# Check if registry is already accessible (existing port forward)
if curl -s http://localhost:5000/v2/ > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Registry already accessible at localhost:5000 (existing port forward detected)${NC}"
    PORT_FORWARD_PID=""
    CREATED_PORT_FORWARD=false
else
    echo -e "${YELLOW}📡 Creating new port forward...${NC}"
    kubectl port-forward -n dev-lab-registry service/docker-registry 5000:5000 &
    PORT_FORWARD_PID=$!
    CREATED_PORT_FORWARD=true
    
    # Wait for port forward to be ready
    echo -e "${YELLOW}⏳ Waiting for port forward to be ready...${NC}"
    for i in {1..10}; do
        if curl -s http://localhost:5000/v2/ > /dev/null 2>&1; then
            echo -e "${GREEN}✅ Port forward ready${NC}"
            break
        elif [ $i -eq 10 ]; then
            echo -e "${RED}❌ Port forward failed to become ready${NC}"
            exit 1
        else
            sleep 1
        fi
    done
fi

# Cleanup function - only kill port forward if we created it
cleanup() {
    if [ "$CREATED_PORT_FORWARD" = true ]; then
        echo -e "${YELLOW}🧹 Cleaning up port forward...${NC}"
        kill $PORT_FORWARD_PID 2>/dev/null || true
    else
        echo -e "${BLUE}ℹ️  Leaving existing port forward active${NC}"
    fi
}
trap cleanup EXIT

# Verify registry is accessible
echo -e "${BLUE}📡 Verifying registry connectivity...${NC}"
if curl -s http://localhost:5000/v2/ > /dev/null; then
    echo -e "${GREEN}✅ Registry is accessible and responding${NC}"
else
    echo -e "${RED}❌ Registry is not accessible${NC}"
    exit 1
fi

# Get catalog
echo -e "${BLUE}📋 Fetching registry catalog...${NC}"
CATALOG=$(curl -s http://localhost:5000/v2/_catalog)
echo "Registry catalog: $CATALOG"

# Check each service
AVAILABLE_COUNT=0
MISSING_SERVICES=()

for service in "${SERVICES[@]}"; do
    echo -e "${BLUE}🔍 Checking $service...${NC}"
    
    # Check if repository exists
    if echo "$CATALOG" | grep -q "\"$service\""; then
        # Get tags for the service
        TAGS=$(curl -s "http://localhost:5000/v2/$service/tags/list" | jq -r '.tags[]?' 2>/dev/null || echo "")
        
        if [ -n "$TAGS" ]; then
            echo -e "${GREEN}  ✅ $service available with tags: $TAGS${NC}"
            ((AVAILABLE_COUNT++))
        else
            echo -e "${YELLOW}  ⚠️  $service repository exists but no tags found${NC}"
            MISSING_SERVICES+=("$service (no tags)")
        fi
    else
        echo -e "${RED}  ❌ $service not found in registry${NC}"
        MISSING_SERVICES+=("$service (not found)")
    fi
done

echo ""
echo -e "${BLUE}📊 Validation Summary${NC}"
echo "==================="
echo -e "${GREEN}✅ Available: $AVAILABLE_COUNT/${#SERVICES[@]}${NC}"

if [ ${#MISSING_SERVICES[@]} -gt 0 ]; then
    echo -e "${RED}❌ Missing services:${NC}"
    for missing in "${MISSING_SERVICES[@]}"; do
        echo "  - $missing"
    done
    echo ""
    echo -e "${YELLOW}💡 Run the build-and-push.sh script to build missing services${NC}"
else
    echo -e "${GREEN}🎉 All services are available in the registry!${NC}"
    echo -e "${YELLOW}💡 You can now deploy the quant-services-layer${NC}"
fi

echo ""
echo -e "${BLUE}🌐 Registry Info${NC}"
echo "==============="
echo "Internal URL: docker-registry.dev-lab-registry.svc.cluster.local:5000"
echo "External URL: localhost:5000 (via port-forward)"
echo "Registry UI: http://registry.dev-lab.local"

# Show sample deployment command
echo ""
echo -e "${BLUE}📦 Sample Deployment Commands${NC}"
echo "============================="
echo "Deploy quant-services:"
echo "  kubectl apply -f apps/quant-services/"
echo ""
echo "Monitor deployment:"
echo "  kubectl get kustomizations -n flux-system | grep quant"
echo "  kubectl get pods -n quant-services"