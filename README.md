# pytorch-gpu-dev

PyTorch CUDA 运行环境镜像集合：code-server / JupyterLab / Gradio / Civitai 下载器，外加**预编译进镜像的 FlashAttention 2 + 3**（构建时不做任何 CUDA 编译）。

多个版本共用一个仓库，按 `wheels/<variant>/` 目录区分，镜像 tag 跟随 variant。

## 版本矩阵

| Variant | 基础镜像 | PyTorch | CUDA | FlashAttention |
|---|---|---|---|---|
| `cu128-torch2.11` | `pytorch/pytorch:2.11.0-cuda12.8-cudnn9-runtime` | 2.11.0 | 12.8 | FA2 2.8.4（sm80/120）+ FA3 3.0.1（sm90a） |

> 基础镜像用 `runtime` 变体（~4.3GB），只含 CUDA 运行时库，不含 nvcc/Toolkit。FA wheel 已编译好，运行不需要 nvcc。成品镜像约 ~9GB（对比 devel 基底 27.5GB）。

## 镜像标签约定

| Tag | 含义 |
|---|---|
| `erhuoyan313/pytorch-gpu-dev:cu128-torch2.11-30102026` | 不可变版本 |
| `erhuoyan313/pytorch-gpu-dev:cu128-torch2.11` | 该 variant 最新 |
| `erhuoyan313/pytorch-gpu-dev:latest` | 全仓库最新构建 |

## 内置组件

| 组件 | 说明 |
|---|---|
| PyTorch | 2.11.0+cu128（torchvision 0.26.0 / torchaudio 2.11.0 随基底） |
| FlashAttention 2 | 2.8.4，sm80 + sm120（Ampere/Ada/Blackwell） |
| FlashAttention 3 | 3.0.1，sm90a（Hopper H100/H200） |
| code-server | :9000，密码环境变量 `PASSWORD` |
| JupyterLab | :8888，密码环境变量 `JUPYTERLAB_PASS` |
| Gradio | :7860 |
| hf cli | `HF_TOKEN` |
| civitai_com / civitai_red | `CIVITAI_TOKEN` |

## 构建

CI 是主路径（GitHub Actions 直接拉 LFS 里的 wheel，不编译）：

```
push 到 main 或手动 workflow_dispatch → 构建 variant → 推 Docker Hub
```

本地构建：

```bash
git lfs pull                      # wheel 是 LFS 对象，先拉本体
./build.sh cu128-torch2.11        # 只构建
./build.sh cu128-torch2.11 --push --user erhuoyan313
```

## 新增一个版本（如 cu130-torch2.12）

1. 建目录 `wheels/cu130-torch2.12/`，放入对应 torch/python 编出的 FA wheel
2. `git lfs track` 已覆盖 `wheels/**/*.whl`，无需改动
3. Dockerfile 无需改（`BASE_IMAGE` / `WHEELS_DIR` 由 build-arg 传入）
4. `build.sh` 的 `base_image_for()` 加一行；workflow 的 variant 选项加一项
5. 推送后 CI 产出 `:cu130-torch2.12` 与 `:latest`

## 运行

```bash
docker run --gpus all -p 9000:9000 -p 8888:8888 -p 7860:7860 \
  -e PASSWORD=xxx -e JUPYTERLAB_PASS=xxx -e HF_TOKEN=xxx \
  -v /path/to/workspace:/workspace \
  erhuoyan313/pytorch-gpu-dev:cu128-torch2.11
```

## wheel 说明

见 [documentation/wheel-reuse.md](documentation/wheel-reuse.md)：架构覆盖、ABI 绑定、升级流程。

## CI Secrets

仓库需配置（Settings → Secrets and variables → Actions）：

| Secret | 用途 |
|---|---|
| `DOCKERHUB_USERNAME` | Docker Hub 用户名 |
| `DOCKERHUB_TOKEN` | Docker Hub access token |
