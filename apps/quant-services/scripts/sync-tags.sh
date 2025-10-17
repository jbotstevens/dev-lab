#!/bin/bash
# Sync Tags with Upstream HelmReleases
# This script automatically updates build scripts and patches to match upstream tags

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPSTREAM_SERVICES_DIR="/home/jstevens/git/amelcocloud/quant-services/quant-services-layer/components/apps/services"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔄 Syncing tags with upstream HelmReleases${NC}"
echo "============================================="

# Step 1: Extract upstream tags
echo -e "${YELLOW}📡 Step 1: Extracting upstream tags...${NC}"
"$SCRIPT_DIR/extract-upstream-tags.sh"

# Check if extraction was successful
if [ ! -f "$SCRIPT_DIR/upstream-tags.yaml" ]; then
    echo -e "${RED}❌ Tag extraction failed!${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Tags extracted successfully${NC}"
echo ""

# Step 2: Parse the tag mapping
echo -e "${YELLOW}🔧 Step 2: Parsing tag mapping...${NC}"

# Read tags into associative array
declare -A SERVICE_TAGS
while IFS=': ' read -r service_tag tag_value; do
    if [[ $service_tag == *"_tag" ]]; then
        # Remove _tag suffix to get service name
        service_name=${service_tag%_tag}
        # Remove quotes from tag value
        clean_tag=$(echo "$tag_value" | tr -d '"')
        SERVICE_TAGS["$service_name"]="$clean_tag"
        echo "  📋 $service_name: $clean_tag"
    fi
done < <(grep "_tag:" "$SCRIPT_DIR/upstream-tags.yaml")

echo -e "${GREEN}✅ Parsed ${#SERVICE_TAGS[@]} service tags${NC}"
echo ""

# Step 3: Update build script
echo -e "${YELLOW}🔨 Step 3: Updating build script with new tags...${NC}"

# Create updated build script content
cat > "$SCRIPT_DIR/build-and-push-updated.sh" << 'EOF'
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
EOF

# Add the tag mappings to the build script
for service in "${!SERVICE_TAGS[@]}"; do
    echo "SERVICE_TAGS[\"$service\"]=\"${SERVICE_TAGS[$service]}\"" >> "$SCRIPT_DIR/build-and-push-updated.sh"
done

# Continue with the rest of the build script
cat >> "$SCRIPT_DIR/build-and-push-updated.sh" << 'EOF'

# List of services to build (based on the services with Dockerfiles)
SERVICES=(
EOF

# Add services array
for service in "${!SERVICE_TAGS[@]}"; do
    echo "    \"$service\"" >> "$SCRIPT_DIR/build-and-push-updated.sh"
done

cat >> "$SCRIPT_DIR/build-and-push-updated.sh" << 'EOF'
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
EOF

chmod +x "$SCRIPT_DIR/build-and-push-updated.sh"
echo -e "${GREEN}✅ Build script updated${NC}"

# Step 4: Update image registry patches
echo -e "${YELLOW}🔧 Step 4: Updating image registry patches...${NC}"

cat > "$SCRIPT_DIR/patches/image-registry-patches-updated.yaml" << 'EOF'
# Image Registry Patches for Dev Lab with Upstream Tags
# This file contains strategic merge patches to redirect all quant-services images
# from ECR (406289901644.dkr.ecr.eu-west-1.amazonaws.com) to local dev-lab registry
# while preserving the original image tags from the upstream HelmReleases
# Auto-generated - DO NOT EDIT MANUALLY, use sync-tags.sh instead

EOF

# Generate patches for each service
for service in "${!SERVICE_TAGS[@]}"; do
    tag="${SERVICE_TAGS[$service]}"
    cat >> "$SCRIPT_DIR/patches/image-registry-patches-updated.yaml" << EOF
---
# Patch for $service
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: $service
spec:
  values:
    image:
      repository: docker-registry.dev-lab-registry.svc.cluster.local:5000/$service
      tag: "$tag"  # Preserving upstream tag

EOF
done

echo -e "${GREEN}✅ Image registry patches updated${NC}"

# Step 5: Summary and next steps
echo ""
echo -e "${BLUE}📋 Sync Summary${NC}"
echo "==============="
echo -e "${GREEN}✅ Extracted tags from ${#SERVICE_TAGS[@]} upstream HelmReleases${NC}"
echo -e "${GREEN}✅ Updated build-and-push-updated.sh with upstream tags${NC}"
echo -e "${GREEN}✅ Updated image-registry-patches-updated.yaml with upstream tags${NC}"

echo ""
echo -e "${YELLOW}📝 Tag mapping:${NC}"
for service in "${!SERVICE_TAGS[@]}"; do
    echo "  - $service: ${SERVICE_TAGS[$service]}"
done

echo ""
echo -e "${BLUE}🚀 Next Steps:${NC}"
echo "1. Review the updated files:"
echo "   - build-and-push-updated.sh"
echo "   - patches/image-registry-patches-updated.yaml"
echo ""
echo "2. Replace the old files when ready:"
echo "   mv build-and-push-updated.sh build-and-push.sh"
echo "   mv patches/image-registry-patches-updated.yaml patches/image-registry-patches.yaml"
echo ""
echo "3. Update kustomization.yaml to reference the new patches file"
echo ""
echo "4. Build and push images with: ./build-and-push.sh"

echo ""
echo -e "${GREEN}🎉 Tag synchronization completed successfully!${NC}"