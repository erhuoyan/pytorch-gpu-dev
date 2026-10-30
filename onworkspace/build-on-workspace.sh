#!/bin/bash

# Ensure we have /workspace in all scenarios
mkdir -p /workspace

if [[ ! -d /workspace/build ]]; then
    mv /build /workspace
    chmod -R 777 /workspace/build
else
    rm -rf /build
fi

# Linking
ln -s /workspace/build /build
