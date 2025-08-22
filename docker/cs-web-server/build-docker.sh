#!/bin/bash

# Check if tag argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <tag>"
    echo ""
    echo "Description:"
    echo "  Build a Docker image for cs-web-server with the specified tag."
    echo ""
    echo "Example:"
    echo "  $0 v1.0.0"
    exit 1
fi

TAG=$1

# Run docker buildx with the provided tag
docker buildx build --platform linux/386 -t cs-web-server:$TAG .
