#!/bin/bash
# Extract Image Tags from Upstream HelmReleases
# This script extracts the actual image tags used in the amelcocloud/quant-services
# HelmRelease definitions and creates a tag mapping file for local builds

set -e

# Configuration
UPSTREAM_SERVICES_DIR="/home/jstevens/git/amelcocloud/quant-services/quant-services-layer/components/apps/services"
OUTPUT_FILE="upstream-tags.yaml"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Extracting upstream image tags from HelmReleases${NC}"
echo "=================================================="

# Check if upstream directory exists
if [ ! -d "$UPSTREAM_SERVICES_DIR" ]; then
    echo -e "${RED}❌ Upstream services directory not found: $UPSTREAM_SERVICES_DIR${NC}"
    exit 1
fi

# Initialize the output file
cat > "$OUTPUT_FILE" << 'EOF'
# Upstream Image Tags
# Auto-generated from amelcocloud/quant-services HelmRelease definitions
# This file maps service names to their upstream image tags

EOF

echo -e "${YELLOW}📋 Scanning HelmRelease files...${NC}"

# Track services and their tags
declare -A SERVICE_TAGS
SERVICES_FOUND=0

# Scan all YAML files in the services directory
for helmrelease_file in "$UPSTREAM_SERVICES_DIR"/*.yaml; do
    if [ -f "$helmrelease_file" ]; then
        # Extract service name from filename
        service_name=$(basename "$helmrelease_file" .yaml)
        
        # Extract image tag using yq or fallback to grep/awk
        if command -v yq >/dev/null 2>&1; then
            tag=$(yq eval '.spec.values.image.tag' "$helmrelease_file" 2>/dev/null)
        else
            # Fallback to grep/awk if yq is not available
            tag=$(grep -A 10 "image:" "$helmrelease_file" | grep "tag:" | head -1 | awk '{print $2}' | tr -d '"')
        fi
        
        if [ -n "$tag" ] && [ "$tag" != "null" ]; then
            SERVICE_TAGS["$service_name"]="$tag"
            echo "  ✅ $service_name: $tag"
            SERVICES_FOUND=$((SERVICES_FOUND + 1))
            
            # Add to output file
            echo "${service_name}_tag: \"$tag\"" >> "$OUTPUT_FILE"
        else
            echo -e "${YELLOW}  ⚠️  $service_name: tag not found or invalid${NC}"
        fi
    fi
done

echo ""
echo -e "${GREEN}📊 Found tags for $SERVICES_FOUND services${NC}"

# Add summary section to output file
cat >> "$OUTPUT_FILE" << EOF

# Tag Summary (for reference)
# Total services: $SERVICES_FOUND
EOF

for service in "${!SERVICE_TAGS[@]}"; do
    echo "# $service: ${SERVICE_TAGS[$service]}" >> "$OUTPUT_FILE"
done

echo ""
echo -e "${BLUE}💾 Tag mapping saved to: $OUTPUT_FILE${NC}"

# Display the generated mapping
echo -e "${YELLOW}📄 Generated tag mapping:${NC}"
cat "$OUTPUT_FILE"

echo ""
echo -e "${GREEN}🎉 Tag extraction completed successfully!${NC}"
echo -e "${YELLOW}💡 Use this mapping to update build-and-push.sh and image-registry-patches.yaml${NC}"