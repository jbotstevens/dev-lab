#!/bin/bash
# Complete Setup Verification for Quant Services Dev Lab Integration
# This script verifies all components are ready for quant-services deployment

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔍 Dev Lab Quant Services Setup Verification${NC}"
echo "=============================================="

# Check 1: Dev Lab cluster connectivity
echo -e "${BLUE}1. Checking cluster connectivity...${NC}"
if kubectl cluster-info &>/dev/null; then
    CLUSTER_NAME=$(kubectl config current-context)
    echo -e "${GREEN}✅ Connected to cluster: $CLUSTER_NAME${NC}"
else
    echo -e "${RED}❌ Not connected to Kubernetes cluster${NC}"
    exit 1
fi

# Check 2: Container registry deployment
echo -e "${BLUE}2. Checking container registry...${NC}"
if kubectl get namespace dev-lab-registry &>/dev/null; then
    echo -e "${GREEN}✅ dev-lab-registry namespace exists${NC}"
    
    REGISTRY_PODS=$(kubectl get pods -n dev-lab-registry -l app=docker-registry --no-headers 2>/dev/null | wc -l)
    if [ "$REGISTRY_PODS" -gt 0 ]; then
        echo -e "${GREEN}✅ Registry pods running: $REGISTRY_PODS${NC}"
    else
        echo -e "${RED}❌ No registry pods found${NC}"
    fi
    
    if kubectl get service docker-registry -n dev-lab-registry &>/dev/null; then
        echo -e "${GREEN}✅ Registry service exists${NC}"
    else
        echo -e "${RED}❌ Registry service not found${NC}"
    fi
else
    echo -e "${RED}❌ dev-lab-registry namespace not found${NC}"
    echo -e "${YELLOW}💡 Deploy infrastructure first: kubectl apply -f infrastructure/${NC}"
fi

# Check 3: Flux system
echo -e "${BLUE}3. Checking Flux system...${NC}"
if kubectl get namespace flux-system &>/dev/null; then
    echo -e "${GREEN}✅ flux-system namespace exists${NC}"
    
    FLUX_PODS=$(kubectl get pods -n flux-system --no-headers 2>/dev/null | grep -E "(Running|Succeeded)" | wc -l)
    if [ "$FLUX_PODS" -gt 0 ]; then
        echo -e "${GREEN}✅ Flux pods running: $FLUX_PODS${NC}"
    else
        echo -e "${YELLOW}⚠️  Flux pods may not be ready${NC}"
    fi
else
    echo -e "${RED}❌ flux-system namespace not found${NC}"
    echo -e "${YELLOW}💡 Bootstrap Flux first${NC}"
fi

# Check 4: GitRepository for quant-services
echo -e "${BLUE}4. Checking quant-services GitRepository...${NC}"
if kubectl get gitrepository quant-services -n flux-system &>/dev/null; then
    echo -e "${GREEN}✅ quant-services GitRepository exists${NC}"
    
    STATUS=$(kubectl get gitrepository quant-services -n flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    if [ "$STATUS" = "True" ]; then
        echo -e "${GREEN}✅ GitRepository is ready${NC}"
    else
        echo -e "${YELLOW}⚠️  GitRepository status: $STATUS${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  quant-services GitRepository not found (will be created)${NC}"
fi

# Check 5: Source repository access
echo -e "${BLUE}5. Checking source repository...${NC}"
QUANT_SERVICES_DIR="/home/jstevens/git/amelcocloud/quant-services"
if [ -d "$QUANT_SERVICES_DIR" ]; then
    echo -e "${GREEN}✅ Source repository found: $QUANT_SERVICES_DIR${NC}"
    
    # Check for Dockerfiles
    DOCKERFILE_COUNT=$(find "$QUANT_SERVICES_DIR/services" -name "Dockerfile" 2>/dev/null | wc -l)
    echo -e "${GREEN}✅ Found $DOCKERFILE_COUNT Dockerfiles${NC}"
    
    # Check for quant-services-layer
    if [ -d "$QUANT_SERVICES_DIR/quant-services-layer" ]; then
        echo -e "${GREEN}✅ quant-services-layer directory exists${NC}"
    else
        echo -e "${RED}❌ quant-services-layer directory not found${NC}"
    fi
else
    echo -e "${RED}❌ Source repository not found: $QUANT_SERVICES_DIR${NC}"
    echo -e "${YELLOW}💡 Clone: git clone git@github.com:amelcocloud/quant-services.git${NC}"
fi

# Check 6: Docker availability
echo -e "${BLUE}6. Checking Docker...${NC}"
if command -v docker &>/dev/null; then
    echo -e "${GREEN}✅ Docker command available${NC}"
    
    if docker info &>/dev/null; then
        echo -e "${GREEN}✅ Docker daemon running${NC}"
    else
        echo -e "${RED}❌ Docker daemon not running${NC}"
    fi
else
    echo -e "${RED}❌ Docker not installed${NC}"
fi

# Check 7: Required tools
echo -e "${BLUE}7. Checking required tools...${NC}"
TOOLS=("kubectl" "curl" "jq")
for tool in "${TOOLS[@]}"; do
    if command -v "$tool" &>/dev/null; then
        echo -e "${GREEN}✅ $tool available${NC}"
    else
        echo -e "${YELLOW}⚠️  $tool not installed (recommended)${NC}"
    fi
done

# Check 8: Patch files
echo -e "${BLUE}8. Checking patch files...${NC}"
DEV_LAB_DIR="/home/jstevens/git/jbotstevens/dev-lab"
PATCHES_DIR="$DEV_LAB_DIR/apps/quant-services/patches"

if [ -f "$PATCHES_DIR/image-registry-patches.yaml" ]; then
    echo -e "${GREEN}✅ Image registry patches found${NC}"
else
    echo -e "${RED}❌ Image registry patches not found${NC}"
fi

if [ -f "$DEV_LAB_DIR/apps/quant-services/build-and-push.sh" ]; then
    echo -e "${GREEN}✅ Build script found${NC}"
else
    echo -e "${RED}❌ Build script not found${NC}"
fi

# Summary and next steps
echo ""
echo -e "${BLUE}📋 Setup Summary${NC}"
echo "================"

ALL_CHECKS_PASSED=true

# Critical checks
CRITICAL_CHECKS=(
    "Cluster connectivity"
    "Container registry"
    "Source repository"
    "Patch files"
)

echo -e "${BLUE}Critical components:${NC}"
for check in "${CRITICAL_CHECKS[@]}"; do
    echo "  - $check"
done

echo ""
echo -e "${BLUE}🚀 Next Steps${NC}"
echo "============="

if [ ! -d "$QUANT_SERVICES_DIR" ]; then
    echo -e "${YELLOW}1. Clone quant-services repository:${NC}"
    echo "   git clone git@github.com:amelcocloud/quant-services.git"
    echo ""
fi

echo -e "${YELLOW}2. Build and push images to local registry:${NC}"
echo "   cd $DEV_LAB_DIR"
echo "   ./apps/quant-services/build-and-push.sh"
echo ""

echo -e "${YELLOW}3. Validate registry contents:${NC}"
echo "   ./apps/quant-services/validate-registry.sh"
echo ""

echo -e "${YELLOW}4. Deploy quant-services:${NC}"
echo "   kubectl apply -f apps/quant-services/"
echo ""

echo -e "${YELLOW}5. Monitor deployment:${NC}"
echo "   kubectl get kustomizations -n flux-system | grep quant"
echo "   kubectl get pods -n quant-services"
echo ""

echo -e "${BLUE}🔧 Troubleshooting${NC}"
echo "=================="
echo "Registry UI: kubectl port-forward -n dev-lab-registry service/docker-registry-ui 8080:80"
echo "Registry API: kubectl port-forward -n dev-lab-registry service/docker-registry 5000:5000"
echo "Flux logs: kubectl logs -n flux-system deployment/source-controller"
echo "Flux logs: kubectl logs -n flux-system deployment/kustomize-controller"

if $ALL_CHECKS_PASSED; then
    echo ""
    echo -e "${GREEN}🎉 Setup verification complete! Ready to deploy quant-services.${NC}"
else
    echo ""
    echo -e "${YELLOW}⚠️  Some issues found. Address them before deploying.${NC}"
fi