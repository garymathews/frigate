# syntax=docker/dockerfile:1.6

ARG DEBIAN_FRONTEND=noninteractive
ARG HSA_OVERRIDE_GFX_VERSION
ARG HSA_OVERRIDE=0

#######################################################################
FROM debian:12-slim AS rocm

ARG DEBIAN_FRONTEND
ARG ROCM
ARG ROCM_SHA256
ARG BUILD_JOBS

RUN apt-get update && apt-get install -qq -y --no-install-recommends \
    build-essential ca-certificates git libdrm-dev libelf-dev libnuma-dev \
    libprotobuf-dev libsqlite3-dev libssl-dev libtinfo6 libmsgpack-cxx-dev \
    nlohmann-json3-dev protobuf-compiler python3-dev python3-pip wget zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*
RUN pip3 install --break-system-packages --no-cache-dir \
    cmake==3.31.10 ninja==1.11.1.4 numpy==1.26.4 packaging wheel setuptools

# This TheRock snapshot includes native gfx900 kernels and runs on Bookworm.
# Keep the complete SDK together, including .kpack files and HIPRTC resources.
RUN wget -q -O /tmp/rocm.tar.gz \
        https://nightly.repo.amd.com/rocm/core/tarball/therock-dist-linux-gfx900-${ROCM}.tar.gz && \
    echo "${ROCM_SHA256}  /tmp/rocm.tar.gz" | sha256sum --check && \
    mkdir -p /opt/rocm && \
    tar -xzf /tmp/rocm.tar.gz -C /opt/rocm && \
    rm /tmp/rocm.tar.gz

ENV PATH="/opt/rocm/bin:/opt/rocm/lib/llvm/bin:${PATH}"
ENV LD_LIBRARY_PATH="/opt/rocm/lib:/opt/rocm/lib/migraphx/lib:/opt/rocm/lib/llvm/lib"
ENV ROCM_PATH=/opt/rocm
ENV CC=/opt/rocm/lib/llvm/bin/clang
ENV CXX=/opt/rocm/lib/llvm/bin/clang++

# Use the rocm-cmake revision required by MIGraphX, rather than the SDK's copy.
RUN git init /tmp/rocm-cmake && \
    git -C /tmp/rocm-cmake remote add origin https://github.com/ROCm/rocm-cmake.git && \
    git -C /tmp/rocm-cmake fetch --depth 1 origin 6a7c5b73b8882c74f8f7060e2633f230dabb7b63 && \
    git -C /tmp/rocm-cmake checkout --detach FETCH_HEAD && \
    cmake -S /tmp/rocm-cmake -B /tmp/rocm-cmake/build \
        -DCMAKE_INSTALL_PREFIX=/opt/rocm && \
    cmake --build /tmp/rocm-cmake/build --target install && \
    rm -rf /tmp/rocm-cmake

#######################################################################
FROM rocm AS migraphx-config

ARG MIGRAPHX_REF
ARG BUILD_JOBS

RUN apt-get update && apt-get install -qq -y --no-install-recommends \
    pybind11-dev python3-pybind11 && rm -rf /var/lib/apt/lists/*

# MIGraphX's CPU target uses the oneDNN 1.x API.
RUN git clone --depth 1 --branch v1.8.1 https://github.com/uxlfoundation/oneDNN.git /tmp/dnnl && \
    cmake -S /tmp/dnnl -B /tmp/dnnl/build -G Ninja \
        -DCMAKE_INSTALL_PREFIX=/opt/rocm \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DDNNL_BUILD_EXAMPLES=OFF -DDNNL_BUILD_TESTS=OFF \
        -DDNNL_CPU_RUNTIME=OMP -DDNNL_ARCH_OPT_FLAGS= && \
    cmake --build /tmp/dnnl/build --parallel ${BUILD_JOBS} && \
    cmake --install /tmp/dnnl/build && \
    rm -rf /tmp/dnnl

RUN git init /tmp/migraphx && \
    git -C /tmp/migraphx remote add origin https://github.com/ROCm/AMDMIGraphX.git && \
    git -C /tmp/migraphx fetch --depth 1 origin ${MIGRAPHX_REF} && \
    git -C /tmp/migraphx checkout --detach FETCH_HEAD && \
    # Upstream declares gfx_default_rocblas only when hipBLASLt is enabled.
    # With hipBLASLt disabled, hipblaslt_supported already returns false.
    sed -i 's/not hipblaslt_supported() or gpu::gfx_default_rocblas()/not hipblaslt_supported()/' \
        /tmp/migraphx/src/targets/gpu/lowering.cpp && \
    cmake -S /tmp/migraphx -B /tmp/migraphx/build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/opt/rocm \
        -DCMAKE_PREFIX_PATH=/opt/rocm \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON \
        -DGPU_TARGETS=gfx900 \
        -DBUILD_TESTING=OFF \
        -DMIGRAPHX_ENABLE_CPU=ON \
        -DMIGRAPHX_ENABLE_PYTHON=ON \
        -DMIGRAPHX_ENABLE_MLIR=OFF \
        -DMIGRAPHX_USE_HIPBLASLT=OFF \
        -DMIGRAPHX_USE_COMPOSABLEKERNEL=OFF \
        -DMIGRAPHX_USE_HIPRTC=ON

FROM migraphx-config AS migraphx

RUN cmake --build /tmp/migraphx/build --parallel ${BUILD_JOBS} && \
    cmake --install /tmp/migraphx/build && \
    echo ${MIGRAPHX_REF} > /opt/rocm/migraphx-version.txt && \
    rm -rf /tmp/migraphx

#######################################################################
FROM migraphx AS onnxruntime

ARG ONNXRUNTIME_REF
ARG BUILD_JOBS

# ORT must use its own FlatBuffers headers to match its generated schemas.
# SDK Clang misreads MIGraphX's module return types as C++20 modules.
RUN rm -rf /opt/rocm/include/flatbuffers /opt/rocm/lib/cmake/flatbuffers \
        /opt/rocm/lib/libflatbuffers.a /opt/rocm/lib/pkgconfig/flatbuffers.pc && \
    git init /tmp/onnxruntime && \
    git -C /tmp/onnxruntime remote add origin https://github.com/microsoft/onnxruntime.git && \
    git -C /tmp/onnxruntime fetch --depth 1 origin ${ONNXRUNTIME_REF} && \
    git -C /tmp/onnxruntime checkout --detach FETCH_HEAD && \
    git -C /tmp/onnxruntime submodule update --init --recursive --depth 1 && \
    cd /tmp/onnxruntime && \
    python3 tools/ci_build/build.py \
        --build_dir /tmp/ort-build \
        --cmake_generator Ninja \
        --config Release \
        --parallel ${BUILD_JOBS} \
        --build_wheel --skip_tests --allow_running_as_root \
        --compile_no_warning_as_error \
        --use_migraphx --migraphx_home /opt/rocm \
        --cmake_extra_defines CMAKE_HIP_ARCHITECTURES=gfx900 \
            CMAKE_CXX_FLAGS=-fno-cxx-modules \
            onnxruntime_BUILD_UNIT_TESTS=OFF && \
    mkdir /wheels && \
    cp /tmp/ort-build/Release/dist/*.whl /wheels/ && \
    rm -rf /tmp/onnxruntime /tmp/ort-build && \
    # Static host libraries are not needed by the runtime. Keep LLVM resources.
    find /opt/rocm/lib -maxdepth 1 -type f -name '*.a' -delete

FROM scratch AS artifacts
COPY --from=onnxruntime /opt/rocm/ /opt/rocm/
COPY --from=onnxruntime /wheels/ /wheels/

#######################################################################
FROM deps AS rocm-prelim-hsa-override0

ARG DEBIAN_FRONTEND

COPY docker/rocm/debian-backports.sources /etc/apt/sources.list.d/debian-backports.sources
RUN echo 'deb http://deb.debian.org/debian trixie main' \
        > /etc/apt/sources.list.d/trixie.list && \
    apt-get update && \
    apt-get install -q -y --no-install-recommends -t bookworm-backports \
        mesa-va-drivers mesa-vulkan-drivers && \
    # Match the C++ headers used to build MIGraphX for runtime HIP compilation.
    # Shared deps use Trixie's libc, so its development headers must match.
    apt-get install -q -y --no-install-recommends -t bookworm \
        libc6-dev/trixie libc-dev-bin/trixie \
        libstdc++-12-dev libnuma1 libdrm2 libelf1 libtinfo6 \
        libprotobuf32 libsqlite3-0 && \
    rm /etc/apt/sources.list.d/trixie.list && \
    rm -rf /var/lib/apt/lists/*

COPY --from=rocm-artifacts /opt/rocm/ /opt/rocm/
RUN printf '/opt/rocm/lib\n/opt/rocm/lib/migraphx/lib\n/opt/rocm/lib/llvm/lib\n' \
        > /etc/ld.so.conf.d/rocm.conf && \
    ldconfig

RUN --mount=type=bind,from=rocm-artifacts,source=/wheels,target=/wheels \
    pip3 uninstall --break-system-packages -y onnxruntime && \
    pip3 install --break-system-packages --no-cache-dir /wheels/*.whl

ENV MIGRAPHX_DISABLE_MIOPEN_FUSION=1
ENV MIGRAPHX_DISABLE_SCHEDULE_PASS=1
ENV MIGRAPHX_DISABLE_REDUCE_FUSION=1
ENV MIGRAPHX_ENABLE_HIPRTC_WORKAROUNDS=1
ENV MIOPEN_CUSTOM_CACHE_DIR=/config/model_cache/migraphx
ENV MIOPEN_USER_DB_PATH=/config/model_cache/migraphx
ENV AMD_COMGR_CACHE=1
ENV AMD_COMGR_CACHE_DIR=/config/model_cache/migraphx

WORKDIR /opt/frigate
COPY --from=rootfs / /

#######################################################################
FROM rocm-prelim-hsa-override0 AS rocm-prelim-hsa-override1

ARG HSA_OVERRIDE_GFX_VERSION
ENV HSA_OVERRIDE_GFX_VERSION=$HSA_OVERRIDE_GFX_VERSION

#######################################################################
FROM rocm-prelim-hsa-override$HSA_OVERRIDE AS rocm-deps
