#!/bin/bash
# Build and Push Quant Services to Dev Lab Registry with Upstream Tags
# This script builds all quant services from Dockerfiles and pushes to local registry
# using the same image tags as defined in the upstream HelmReleases
# Auto-generated - DO NOT EDIT MANUALLY, use sync-tags.sh instead

set -e

# Configuration
QUANT_SERVICES_DIR="/home/jstevens/git/amelcocloud/quant-services/services"
LOCAL_REGISTRY="docker-registry.dev-lab-registry.svc.cluster.local:5000"
LOCAL_REGISTRY_EXTERNAL="localhost:5000"  # For external access during build

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Building and pushing quant services with upstream tags to dev-lab registry${NC}"
echo "========================================================================"

# Check if quant-services directory exists
if [ ! -d "$QUANT_SERVICES_DIR" ]; then
    echo -e "${RED}❌ Quant services directory not found: $QUANT_SERVICES_DIR${NC}"
    exit 1
fi

# Service to tag mapping (from upstream HelmReleases)
declare -A SERVICE_TAGS
SERVICE_TAGS["dash-ws"]="1.0.0"
SERVICE_TAGS["external-prices-gather"]="1.0.0"
SERVICE_TAGS["adh-consumer"]="1.0.0"
SERVICE_TAGS["nba-livescores"]="1.0.0"
SERVICE_TAGS["wnba-reports"]="1.0.1"
SERVICE_TAGS["dash-auth"]="1.0.0"
SERVICE_TAGS["unabated-news-feeder"]="1.0.0"
SERVICE_TAGS["betticker-ws"]="1.0.0"
SERVICE_TAGS["rw-proj-min"]="1.0.0"
SERVICE_TAGS["news-gather"]="1.0.0"
SERVICE_TAGS["rw-proj-min-store"]="1.0.0"
SERVICE_TAGS["rapid-pini-feeder"]="1.0.0"

# List of services to build (based on the services with Dockerfiles)
SERVICES=(
    "dash-ws"
    "external-prices-gather"
    "adh-consumer"
    "nba-livescores"
    "wnba-reports"
    "dash-auth"
    "unabated-news-feeder"
    "betticker-ws"
    "rw-proj-min"
    "news-gather"
    "rw-proj-min-store"
    "rapid-pini-feeder"
)

echo -e "${YELLOW}📋 Services to build with upstream tags: ${#SERVICES[@]}${NC}"
for service in "${SERVICES[@]}"; do
    tag=${SERVICE_TAGS[$service]}
    echo "  - $service:$tag"
done
echo ""

# Setup registry port forwarding
echo -e "${BLUE}🔧 Setting up registry port forwarding...${NC}"
kubectl port-forward -n dev-lab-registry service/docker-registry 5000:5000 &
PORT_FORWARD_PID=$!
sleep 5

# Cleanup function
cleanup() {
    echo -e "${YELLOW}🧹 Cleaning up port forward...${NC}"
    kill $PORT_FORWARD_PID 2>/dev/null || true
}
trap cleanup EXIT

# Build and push each service
SUCCESS_COUNT=0
FAILED_SERVICES=()

for service in "${SERVICES[@]}"; do
    SERVICE_DIR="$QUANT_SERVICES_DIR/$service"
    TAG=${SERVICE_TAGS[$service]}
    
    echo -e "${BLUE}🔨 Building $service with tag $TAG...${NC}"
    
    if [ ! -d "$SERVICE_DIR" ]; then
        echo -e "${RED}❌ Service directory not found: $SERVICE_DIR${NC}"
        FAILED_SERVICES+=("$service (directory not found)")
        continue
    fi
    
    if [ ! -f "$SERVICE_DIR/Dockerfile" ]; then
        echo -e "${RED}❌ Dockerfile not found for $service${NC}"
        FAILED_SERVICES+=("$service (no Dockerfile)")
        continue
    fi
    
    # Build the image with upstream tag
    IMAGE_TAG="$LOCAL_REGISTRY_EXTERNAL/$service:$TAG"
    
    echo "  Building: $IMAGE_TAG"
    if docker build -t "$IMAGE_TAG" "$SERVICE_DIR"; then
        echo -e "${GREEN}  ✅ Build successful for $service:$TAG${NC}"
        
        # Also tag with latest for backward compatibility
        LATEST_TAG="$LOCAL_REGISTRY_EXTERNAL/$service:latest"
        docker tag "$IMAGE_TAG" "$LATEST_TAG"
        echo "  Tagged as: $LATEST_TAG (backward compatibility)"
        
        # Push both tags
        echo "  Pushing: $IMAGE_TAG"
        if docker push "$IMAGE_TAG"; then
            echo -e "${GREEN}  ✅ Push successful for $service:$TAG${NC}"
            
            echo "  Pushing: $LATEST_TAG"
            if docker push "$LATEST_TAG"; then
                echo -e "${GREEN}  ✅ Push successful for $service:latest${NC}"
                ((SUCCESS_COUNT++))
            else
                echo -e "${RED}  ❌ Latest tag push failed for $service${NC}"
                FAILED_SERVICES+=("$service (latest tag push failed)")
            fi
        else
            echo -e "${RED}  ❌ Push failed for $service:$TAG${NC}"
            FAILED_SERVICES+=("$service (push failed)")
        fi
    else
        echo -e "${RED}  ❌ Build failed for $service${NC}"
        FAILED_SERVICES+=("$service (build failed)")
    fi
    
    echo ""
done

# Summary
echo -e "${BLUE}📊 Build Summary${NC}"
echo "================"
echo -e "${GREEN}✅ Successful: $SUCCESS_COUNT/${#SERVICES[@]}${NC}"

if [ ${#FAILED_SERVICES[@]} -gt 0 ]; then
    echo -e "${RED}❌ Failed services:${NC}"
    for failed in "${FAILED_SERVICES[@]}"; do
        echo "  - $failed"
    done
fi

echo ""
echo -e "${BLUE}🔍 Checking registry contents...${NC}"
curl -s http://localhost:5000/v2/_catalog | jq '.repositories[]' 2>/dev/null || echo "Registry catalog check failed (jq might not be installed)"

echo ""
echo -e "${BLUE}🏷️  Image Tag Summary:${NC}"
echo "====================="
for service in "${SERVICES[@]}"; do
    tag=${SERVICE_TAGS[$service]}
    echo -e "${GREEN}  ✅ $service: $tag (+ latest)${NC}"
done

echo ""
if [ $SUCCESS_COUNT -eq ${#SERVICES[@]} ]; then
    echo -e "${GREEN}🎉 All services built and pushed successfully with upstream tags!${NC}"
    echo -e "${YELLOW}💡 Images now use the same tags as defined in their HelmReleases${NC}"
    echo -e "${YELLOW}💡 Both upstream tags and 'latest' tags are available for flexibility${NC}"
    echo -e "${YELLOW}💡 You can now deploy the quant-services-layer to your dev-lab cluster${NC}"
    echo -e "${YELLOW}💡 Registry UI available at: http://registry.dev-lab.local${NC}"
else
    echo -e "${YELLOW}⚠️  Some services failed to build/push. Check the errors above.${NC}"
fi
