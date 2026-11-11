# syntax=docker/dockerfile:1.6

FROM deps AS rocm-deps

ARG DEBIAN_FRONTEND=noninteractive

COPY docker/rocm/debian-backports.sources /etc/apt/sources.list.d/debian-backports.sources
RUN echo 'deb http://deb.debian.org/debian trixie main' \
        > /etc/apt/sources.list.d/trixie.list && \
    apt-get update && \
    apt-get install -q -y --no-install-recommends -t bookworm-backports \
        mesa-va-drivers mesa-vulkan-drivers && \
    # Match the C++ headers used to build MIGraphX for runtime HIP compilation.
    # Shared deps use Trixie's libc, so its development headers must match.
    apt-get install -q -y --no-install-recommends -t bookworm \
        libc6-dev/trixie libstdc++-12-dev \
        libnuma1 libdrm2 libelf1 libtinfo6 libprotobuf32 libsqlite3-0 && \
    rm /etc/apt/sources.list.d/trixie.list && \
    rm -rf /var/lib/apt/lists/*

COPY --from=rocm-artifacts /opt/rocm/ /opt/rocm/
RUN printf '/opt/rocm/lib\n/opt/rocm/lib/migraphx/lib\n/opt/rocm/lib/llvm/lib\n' \
        > /etc/ld.so.conf.d/rocm.conf && \
    ldconfig

RUN --mount=type=bind,from=rocm-artifacts,source=/wheels,target=/wheels \
    pip3 uninstall --break-system-packages -y onnxruntime && \
    pip3 install --break-system-packages --no-cache-dir /wheels/*.whl

ENV MIGRAPHX_DISABLE_MIOPEN_FUSION=1 \
    MIGRAPHX_DISABLE_SCHEDULE_PASS=1 \
    MIGRAPHX_DISABLE_REDUCE_FUSION=1 \
    MIOPEN_CUSTOM_CACHE_DIR=/config/model_cache/migraphx \
    MIOPEN_USER_DB_PATH=/config/model_cache/migraphx \
    AMD_COMGR_CACHE=1 \
    AMD_COMGR_CACHE_DIR=/config/model_cache/migraphx

WORKDIR /opt/frigate
COPY --from=rootfs / /
