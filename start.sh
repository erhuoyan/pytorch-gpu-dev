#!/bin/bash

echo "ℹ️ pytorch-gpu-dev pod started"
echo "ℹ️ Wait until 🎉 Ready to develop 🎉"

# Enable SSH if PUBLIC_KEY is set
if [[ -n "$PUBLIC_KEY" ]]; then
    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    mkdir -p /run/sshd
    /usr/sbin/sshd
    echo "✅ [SSH enabled]"
fi

# Export env variables
if [[ -n "${RUNPOD_GPU_COUNT:-}" ]]; then
    echo "ℹ️ Exporting runpod.io environment variables..."
    printenv | grep -E '^RUNPOD_|^PATH=|^_=' \
      | awk -F = '{ print "export " $1 "=\"" $2 "\"" }' >> /etc/rp_environment
    echo 'source /etc/rp_environment' >> ~/.bashrc
fi

# Move necessary files to workspace
echo "ℹ️ [Moving necessary files to workspace] enabling rebooting pod without data loss"
for script in build-on-workspace.sh readme-on-workspace.sh; do
    if [ -f "/$script" ]; then
        echo "Executing $script..."
        "/$script"
    else
        echo "⚠️ WARNING: Skipping $script (not found)"
    fi
done

# Create output directory for cloud transfer
mkdir -p /workspace/output/

# GPU detection
HAS_GPU=0
if [[ -n "${RUNPOD_GPU_COUNT:-}" && "${RUNPOD_GPU_COUNT:-0}" -gt 0 ]]; then
    HAS_GPU=1
    echo "✅ [GPU DETECTED] Found via RUNPOD_GPU_COUNT=${RUNPOD_GPU_COUNT}"
elif command -v nvidia-smi >/dev/null 2>&1; then
    if nvidia-smi >/dev/null 2>&1; then
        HAS_GPU=1
        GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader | xargs | sed 's/,/, /g')
        echo " ✅ [GPU DETECTED] Found via nvidia-smi → Model(s): ${GPU_MODEL}"
    fi
elif [[ -n "${CUDA_VISIBLE_DEVICES:-}" && "${CUDA_VISIBLE_DEVICES}" != "-1" ]]; then
    HAS_GPU=1
    echo "✅ [GPU DETECTED] Found via CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES}"
else
    echo "⚠️ [NO GPU] Running on CPU only"
fi

# Run services
if [[ "$HAS_GPU" -eq 1 ]]; then
    if [[ -n "$PASSWORD" ]]; then
        code-server /workspace --auth password --disable-update-check --disable-telemetry --host 0.0.0.0 --bind-addr 0.0.0.0:9000 &
    else
        echo "⚠️ PASSWORD is not set as an environment. password created in /root/.config/code-server/config.yaml"
        code-server /workspace --disable-telemetry --disable-update-check --host 0.0.0.0 --bind-addr 0.0.0.0:9000 &
    fi

    sleep 5

    if [[ -n "$JUPYTERLAB_PASS" ]]; then
        # Use Python to hash the password
        HASHED_PASSWORD=$(python -c "
import os
from jupyter_server.auth import passwd
print(passwd(os.environ['JUPYTERLAB_PASS']))
")

        # Path to Jupyter config
        CONFIG_PATH=~/.jupyter/jupyter_server_config.py

        # Ensure config directory exists
        mkdir -p ~/.jupyter

        # Remove existing legacy and current password settings
        sed -i \
            -e '/^c\.ServerApp\.password[[:space:]]*=/d' \
            -e '/^c\.PasswordIdentityProvider\.hashed_password[[:space:]]*=/d' \
            "$CONFIG_PATH" 2>/dev/null || true

        # Append the new hashed password
        echo "c.PasswordIdentityProvider.hashed_password = '$HASHED_PASSWORD'" >> "$CONFIG_PATH"
        echo "[INFO] Jupyter Server password set in $CONFIG_PATH"

        # Start JupyterLab
        jupyter lab \
            --ip=0.0.0.0 \
            --port=8888 \
            --no-browser \
            --allow-root \
            --ServerApp.allow_origin='*' \
            --ServerApp.allow_remote_access=True &
    else
        echo "⚠️ WARNING: JUPYTERLAB_PASS is not set as an environment variable - JupyterLab not started"
    fi
else
    echo "⚠️ WARNING: No GPU available, Services not started to limit memory use"
fi

download_sources() {
    local url_var="$1"

    # Check if URL variable is set and not empty
    if [[ -z "${!url_var}" ]]; then
        return 0
    fi

    # Destination directory
    local dest_dir="/workspace/build/"
    mkdir -p "$dest_dir"

    # Get filename from URL
    local url="${!url_var}"
    local filename
    filename=$(basename "$url")

    echo "[INFO] Downloading $filename ..."
    if ! wget -q -P "$dest_dir" "$url"; then
        echo "⚠️ Failed to download $url"
        return 0
    fi

    local filepath="${dest_dir}${filename}"

    # Automatically extract common archive formats
    case "$filename" in
        *.zip)
            echo "[INFO] Unzipping $filename ..."
            unzip -o "$filepath" -d "$dest_dir" >/dev/null 2>&1 || echo "⚠️ Failed to unzip $filename"
            ;;
        *.tar.gz|*.tgz)
            echo "[INFO] Extracting $filename ..."
            tar -xzf "$filepath" -C "$dest_dir" || echo "⚠️ Failed to extract $filename"
            ;;
        *.tar.xz)
            echo "[INFO] Extracting $filename ..."
            tar -xJf "$filepath" -C "$dest_dir" || echo "⚠️ Failed to extract $filename"
            ;;
        *.tar.bz2)
            echo "[INFO] Extracting $filename ..."
            tar -xjf "$filepath" -C "$dest_dir" || echo "⚠️ Failed to extract $filename"
            ;;
        *.7z)
            echo "[INFO] Extracting $filename ..."
            7z x -y -o"$dest_dir" "$filepath" >/dev/null 2>&1 || echo "⚠️ Failed to extract $filename"
            ;;
        *)
            echo "[INFO] No extraction performed for $filename"
            ;;
    esac

    sleep 1
    return 0
}

# Provisioning sources
echo "[INFO] Provisioning sources"

for i in $(seq 1 50); do
    VAR="SOURCE${i}"
    download_sources "$VAR"
done

# Final message
echo "✅ Following environment"

python - <<'PY'
import torch, platform, triton, os
print(f"Python: {platform.python_version()}")
print(f"PyTorch: {torch.__version__}")
print(f"Triton version: {triton.__version__}")
print(f"CUDA available: {torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"  ↳ CUDA runtime: {torch.version.cuda}")
    print(f"  ↳ GPU(s): {[torch.cuda.get_device_name(i) for i in range(torch.cuda.device_count())]}")
    print(f"  ↳ cuDNN: {torch.backends.cudnn.version()}")
try:
    import flash_attn
    print(f"FlashAttention 2: {flash_attn.__version__}")
except ImportError:
    print("FlashAttention 2: not installed")
try:
    from flash_attn import flash_attn_func  # noqa
    print("FlashAttention 2 import: OK")
except Exception as e:
    print(f"FlashAttention 2 import: {e}")
try:
    import flashattn_hopper
    print(f"FlashAttention 3 (hopper): OK @ {flashattn_hopper.__file__}")
except ImportError:
    print("FlashAttention 3 (hopper): not installed")
print("Torch build info:")
print(torch.__config__.show())
PY

if [[ "$HAS_GPU" -eq 1 ]]; then
    echo "🎉 Ready to develop 🎉"
    echo "👉 🔗 Code-Server : http://<host>:9000/"
    echo "👉 🔗 JupyterLab  : http://<host>:8888/"
    echo "👉 🔗 Gradio      : http://<host>:7860/"

    if [[ -n "$PASSWORD" ]]; then
        echo "ℹ️ Code-Server login use PASSWORD set as env"
    else
        echo "⚠️ Code-Server password not provided via env (PASSWORD) use generated."
        cat /root/.config/code-server/config.yaml
    fi
else
    echo "ℹ️ Running error diagnosis"
    echo "⚠️ No GPU detected in the container; check driver / device mounting."
fi

# Keep the container running
exec sleep infinity
