#!/bin/bash

# Check if tag argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <tag>"
    echo ""
    echo "Description:"
    echo "  Build a Docker image for cs-web-server with the specified tag."
    echo "  Also tags the image as 'latest'."
    echo ""
    echo "Example:"
    echo "  $0 v1.0.0"
    exit 1
fi

TAG="$1"

# Run docker buildx with the provided tag and 'latest'
docker buildx build --platform linux/386 \
  -t cs-web-server:"$TAG" \
  -t cs-web-server:latest \
  .
