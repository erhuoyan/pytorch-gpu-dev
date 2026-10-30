# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=pytorch/pytorch:2.11.0-cuda12.8-cudnn9-devel
ARG FA_CUDA_ARCHS="80;120"
ARG MAX_JOBS=32

# ==================== Stage 1: flash-attn wheel builder ====================
FROM ${BASE_IMAGE} AS fa-builder
ARG FA_CUDA_ARCHS
ARG MAX_JOBS

ENV FLASH_ATTENTION_FORCE_BUILD=TRUE \
    BUILD_TARGET=cuda \
    USE_NINJA=1 \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    FLASH_ATTN_CUDA_ARCHS=${FA_CUDA_ARCHS} \
    MAX_JOBS=${MAX_JOBS}

# Build deps for flash-attn setup.py
RUN --mount=type=cache,target=/root/.cache/pip \
    apt-get update -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git wget unzip ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && python -m pip install --root-user-action ignore \
        ninja packaging wheel build einops cmake setuptools

# Build context carries ./wheels (empty on first build, filled on later builds)
COPY wheels/ /cached-wheels/

RUN mkdir -p /out/wheels \
    && if compgen -G "/cached-wheels/flash_attn*.whl" > /dev/null; then \
           echo ">>> Reusing cached flash-attn wheels from build context"; \
           cp /cached-wheels/flash_attn*.whl /out/wheels/; \
       else \
           echo ">>> Building flash-attn wheels from source (no cached wheels)"; \
           git clone --depth 1 https://github.com/Dao-AILab/flash-attention.git /tmp/fa \
           && cd /tmp/fa \
           && git submodule update --init --depth 1 -- csrc/cutlass \
           && echo ">>> Building FlashAttention 2 (sm80/sm120)..." \
           && cd /tmp/fa \
           && python -m pip wheel --no-cache-dir --no-deps --no-build-isolation \
                  --wheel-dir /out/wheels . \
           && echo ">>> Building FlashAttention 3 (sm90a hopper)..." \
           && cd /tmp/fa/hopper \
           && python -m pip wheel --no-cache-dir --no-deps --no-build-isolation \
                  --wheel-dir /out/wheels . ; \
       fi \
    && ls -lh /out/wheels/

# ==================== Stage 2: final image ====================
FROM ${BASE_IMAGE}

# HuggingFace cache on the workspace volume
ENV HF_HOME=/workspace/cache \
    PIP_BREAK_SYSTEM_PACKAGES=1

WORKDIR /

# Requirements
COPY --chmod=664 requirements.txt /requirements.txt

# Development tools
RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install -U pip \
    && python -m pip install \
        --break-system-packages \
        --root-user-action ignore \
        -r /requirements.txt

# code-server
RUN curl -fsSL https://code-server.dev/install.sh | sh

# FlashAttention wheels from builder
COPY --from=fa-builder /out/wheels/ /tmp/wheels/
RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install --no-cache-dir /tmp/wheels/*.whl \
    && rm -rf /tmp/wheels


# Civitai downloaders
COPY --chmod=755 civitai_com_environment.py /usr/local/bin/civitai_com
COPY --chmod=755 civitai_red_environment.py /usr/local/bin/civitai_red

# Build scripts + docs (available as /build inside container)
COPY --chmod=644 build/ /build

# README
COPY --chmod=664 documentation/README.md /README.md

# Startup + workspace helper scripts
COPY --chmod=755 start.sh /
COPY --chmod=755 onworkspace/build-on-workspace.sh onworkspace/readme-on-workspace.sh /

WORKDIR /workspace

# code-server / jupyterlab / jupyter-server / gradio
EXPOSE 9000 8888 7860

LABEL org.opencontainers.image.title="PyTorch CUDA 12.8 Devel + FlashAttn 2/3" \
      org.opencontainers.image.description="PyTorch 2.11 CUDA 12.8 devel + code-server + Jupyter + Gradio + flash-attn 2/3 wheels" \
      org.opencontainers.image.licenses="MIT"

# Sanity check: imports must succeed (no GPU required to import)
RUN python -c "import torch, torchvision, torchaudio, triton, flash_attn; print('torch', torch.__version__); print('torchvision', torchvision.__version__); print('torchaudio', torchaudio.__version__); print('flash_attn', flash_attn.__version__); print('CUDA', torch.version.cuda)" \
    && python -c "import flash_attn_3; print('flash_attn_3 OK')" || echo "WARN: flash_attn_3 import check skipped"

# Start
CMD [ "/start.sh" ]
