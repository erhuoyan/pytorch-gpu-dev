# FlashAttention wheel 说明

本仓库**不在构建时编译** FlashAttention。wheel 是预先编好、经 Git LFS 存在 `wheels/<variant>/` 里的二进制制品，镜像构建时直接 `pip install`。

## 当前 wheel

| 文件 | 版本 | 架构覆盖 |
|---|---|---|
| `flash_attn-2.8.4-cp312-cp312-linux_x86_64.whl` | FA2 2.8.4 | sm80（Ampere A100/A40/3090，二进制兼容 Ada 4090）+ sm120（Blackwell 5090） |
| `flash_attn_3-3.0.1-cp310-abi3-linux_x86_64.whl` | FA3 3.0.1 | sm90a（Hopper H100/H200） |

两者包名不同（`flash_attn` / `flash_attn_3`），可共存。

## ABI 绑定（重要）

wheel 与以下三者强绑定，任一变化都必须重编：

- **torch 版本**：2.11.0
- **Python 版本**：3.12（`cp312`）
- **CUDA 版本**：12.8

FA3 的 wheel tag 是 `cp310-abi3`（stable ABI），Python 3.10+ 通用，但仍绑定 torch 的 C++ 符号。

## 编译方法（换版本时用）

编译**不需要 GPU**，只需要 nvcc（devel 基底）+ 足够内存。参考仓库的 `build/flash2_attention.md`、`build/flash3_attention.md` 保留了完整步骤，核心是：

```bash
# FA2
export FLASH_ATTN_CUDA_ARCHS="80;120" FLASH_ATTENTION_FORCE_BUILD=TRUE BUILD_TARGET=cuda USE_NINJA=1 MAX_JOBS=32
cd flash-attention && python -m pip wheel --no-deps --no-build-isolation --wheel-dir out .
# FA3
cd flash-attention/hopper && python -m pip wheel --no-deps --no-build-isolation --wheel-dir out .
```

FA3 不读 `FLASH_ATTN_CUDA_ARCHS`：其 setup.py monkey-patch `_write_ninja_file`，按 `.cu` 文件名后缀分配 gencode（`_sm90.cu`→`sm90a`，`_sm80.cu`→`sm80`）。

在 128 核 / 1TB 内存机器上：FA2 约 35 分钟，FA3 约 50 分钟。

## LFS 注意事项

- `wheels/**/*.whl` 由 `.gitattributes` 交给 LFS 管理
- **CI checkout 必须 `lfs: true`**；`build.sh` 检测到 LFS 指针文件会直接报错
- 新克隆仓库后先跑 `git lfs pull` 再用
- GitHub 免费 LFS 配额 1GB 存储 / 1GB 月流量；当前两个 wheel 合计 719MB
