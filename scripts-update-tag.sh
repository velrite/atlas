#!/bin/sh
set -e
sed -i "s|tag:.*|tag: \"${IMAGE_TAG}\"|" helm/atlas-platform/values.yaml
