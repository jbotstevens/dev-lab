#!/bin/bash
# Tag Synchronization Demo and Verification
# This script demonstrates the complete tag synchronization workflow

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔄 Tag Synchronization Demo for Quant Services${NC}"
echo "=============================================="
echo ""

echo -e "${YELLOW}📋 Current Workflow Overview:${NC}"
echo "1. Extract image tags from upstream amelcocloud/quant-services HelmReleases"
echo "2. Update build-and-push.sh to use extracted tags instead of 'latest'"
echo "3. Update image-registry-patches.yaml to preserve upstream tags"
echo "4. Build and push images with correct tags to local registry"
echo "5. Deploy with exact same tags as upstream"
echo ""

echo -e "${BLUE}🔍 Step 1: Current Upstream Tags${NC}"
echo "================================="
if [ -f "upstream-tags.yaml" ]; then
    echo -e "${GREEN}✅ Found upstream-tags.yaml${NC}"
    echo ""
    echo -e "${YELLOW}📄 Current tag mappings:${NC}"
    grep "_tag:" upstream-tags.yaml | while IFS=': ' read -r service_tag tag_value; do
        service_name=${service_tag%_tag}
        clean_tag=$(echo "$tag_value" | tr -d '"')
        echo "  - $service_name: $clean_tag"
    done
else
    echo -e "${RED}❌ upstream-tags.yaml not found${NC}"
    echo "Run: ./extract-upstream-tags.sh"
fi
echo ""

echo -e "${BLUE}🔨 Step 2: Build Script Verification${NC}"
echo "====================================="
if grep -q "SERVICE_TAGS\[" build-and-push.sh; then
    echo -e "${GREEN}✅ Build script has upstream tag mappings${NC}"
    echo ""
    echo -e "${YELLOW}📄 Sample tag mappings in build script:${NC}"
    grep "SERVICE_TAGS\[" build-and-push.sh | head -3 | while read line; do
        echo "  $line"
    done
else
    echo -e "${RED}❌ Build script missing tag mappings${NC}"
    echo "Run: ./sync-tags.sh"
fi
echo ""

echo -e "${BLUE}🔧 Step 3: Image Registry Patches Verification${NC}"
echo "==============================================="
if grep -q "# Preserving upstream tag" patches/image-registry-patches.yaml; then
    echo -e "${GREEN}✅ Image patches preserve upstream tags${NC}"
    echo ""
    echo -e "${YELLOW}📄 Sample patches with tags:${NC}"
    grep -A 2 "tag:" patches/image-registry-patches.yaml | head -6 | while read line; do
        if [[ ! -z "$line" && "$line" != "--" ]]; then
            echo "  $line"
        fi
    done
else
    echo -e "${RED}❌ Image patches missing upstream tags${NC}"
    echo "Run: ./sync-tags.sh"
fi
echo ""

echo -e "${BLUE}🎯 Step 4: Tag Consistency Check${NC}"
echo "================================="
echo -e "${YELLOW}Checking if build script tags match patch file tags...${NC}"

# Extract tags from different sources
declare -A BUILD_TAGS
declare -A PATCH_TAGS

# Extract from build script
while read line; do
    if [[ $line =~ SERVICE_TAGS\[\"([^\"]+)\"\]=\"([^\"]+)\" ]]; then
        service="${BASH_REMATCH[1]}"
        tag="${BASH_REMATCH[2]}"
        BUILD_TAGS["$service"]="$tag"
    fi
done < build-and-push.sh

# Extract from patches
current_service=""
while read line; do
    if [[ $line =~ name:\ ([^\ ]+) ]]; then
        current_service="${BASH_REMATCH[1]}"
    elif [[ $line =~ tag:\ \"([^\"]+)\" ]] && [[ ! -z "$current_service" ]]; then
        tag="${BASH_REMATCH[1]}"
        PATCH_TAGS["$current_service"]="$tag"
        current_service=""
    fi
done < patches/image-registry-patches.yaml

# Compare tags
CONSISTENT=true
for service in "${!BUILD_TAGS[@]}"; do
    build_tag="${BUILD_TAGS[$service]}"
    patch_tag="${PATCH_TAGS[$service]}"
    
    if [[ "$build_tag" == "$patch_tag" ]]; then
        echo -e "${GREEN}  ✅ $service: $build_tag == $patch_tag${NC}"
    else
        echo -e "${RED}  ❌ $service: BUILD($build_tag) != PATCH($patch_tag)${NC}"
        CONSISTENT=false
    fi
done

echo ""
if $CONSISTENT; then
    echo -e "${GREEN}🎉 All tags are consistent between build script and patches!${NC}"
else
    echo -e "${RED}❌ Tag inconsistencies found. Run: ./sync-tags.sh${NC}"
fi

echo ""
echo -e "${BLUE}🚀 Step 5: Deployment Readiness${NC}"
echo "==============================="
echo -e "${YELLOW}Ready to deploy with upstream tag synchronization:${NC}"
echo ""
echo "1. Sync tags (if needed):     ./sync-tags.sh"
echo "2. Build with upstream tags:  ./build-and-push.sh"
echo "3. Deploy services:           kubectl apply -f ."
echo "4. Verify deployment:         ./validate-registry.sh"
echo ""

echo -e "${BLUE}💡 Key Benefits:${NC}"
echo "- ✅ Local images use exact same tags as upstream HelmReleases"
echo "- ✅ No more 'latest' tag confusion in development"
echo "- ✅ Easy to sync when upstream tags change"
echo "- ✅ Automated tag extraction and synchronization"
echo "- ✅ Maintains both upstream tags and 'latest' for compatibility"
echo ""

echo -e "${GREEN}🎯 Tag synchronization system is ready!${NC}"