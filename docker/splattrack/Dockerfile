FROM rust:1.93 AS brush-builder
WORKDIR /build/brush

# tags are really outdated, this commit was the latest
RUN git clone https://github.com/ArthurBrussee/brush.git . && \
    git checkout 83b7c71f2148095285d8c2fa2bc961408fcf524d

COPY brush_progress_bar.diff /tmp

# replace the Unicode characters in the progress bar and status with ASCII characters
RUN patch -p 1 < /tmp/brush_progress_bar.diff

RUN cargo fetch
RUN cargo build --release -p brush-app



FROM ubuntu:24.04 AS colmap-builder

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

RUN apt-get update && apt-get install -y --no-install-recommends \
    # OS packages
    ca-certificates \
    # build tools
    git \
    ninja-build \
    build-essential \
    pkg-config \
    unzip \
    cmake \
    # COLMAP build dependencies
    libboost-program-options-dev \
    libboost-filesystem-dev \
    libboost-graph-dev \
    libboost-system-dev \
    libboost-test-dev \
    libeigen3-dev \
    libflann-dev \
    libfreeimage-dev \
    libmetis-dev \
    libgoogle-glog-dev \
    libgflags-dev \
    libsqlite3-dev \
    libglew-dev \
    qtbase5-dev \
    libqt5opengl5-dev \
    libcgal-dev \
    libgtest-dev \
    libopenimageio-dev \
    libopencv-dev \
    openimageio-tools \
    # FFmpeg
    ffmpeg && \
    apt-get clean && \
    apt-get distclean

# CUDA build dependencies -- skip these and set "-DCUDA_ENABLED=OFF" in COLMAP to build it without CUDA support
RUN apt-get update && \
    apt-get install -y --no-install-recommends wget libsuitesparse-dev && \
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb && \
    echo "d2a6b11c096396d868758b86dab1823b25e14d70333f1dfa74da5ddaf6a06dba  cuda-keyring_1.1-1_all.deb" | sha256sum -c - && \
    dpkg -i cuda-keyring_1.1-1_all.deb && \
    apt-get update && \
    apt-get install -y --no-install-recommends nvidia-cuda-toolkit && \
    apt-get clean && \
    apt-get distclean


WORKDIR /opt/libcudss

# CUDA support for Ceres Solver -- skip this and set "-DCUDA_ENABLED=OFF" in Ceres Solver to build it without CUDA support
RUN wget https://developer.download.nvidia.com/compute/cudss/redist/libcudss/linux-x86_64/libcudss-linux-x86_64-0.7.1.4_cuda12-archive.tar.xz && \
    echo "946571d9ea164f948e402dd97a14541cb90fbec800336cfa7ae644af5937632f  libcudss-linux-x86_64-0.7.1.4_cuda12-archive.tar.xz" | sha256sum -c - && \
    tar xvf *.tar.xz --strip-components 1 && \
    rm *.tar.xz


WORKDIR  /build/ceres-solver

# tags are really outdated, this commit was the latest
RUN git clone --recurse-submodules https://github.com/ceres-solver/ceres-solver . && \
    git checkout 0ba987acaf9e8674070f116ed624edf017d2b630


WORKDIR /build/ceres-solver/build

RUN cmake -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/opt/ceres-solver \
        -DUSE_CUDA=ON \
        -Dcudss_DIR=/opt/libcudss/lib/cmake/cudss \
        .. && \
    make -j$(nproc)

RUN make install


WORKDIR /build/colmap

# pinning version
RUN git clone --depth 1 --branch 4.0.4 \
    https://github.com/colmap/colmap.git .


WORKDIR /build/colmap/build

RUN cmake -GNinja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/opt/colmap \
        -DCUDA_ENABLED=ON \
        -DGUI_ENABLED=OFF \
        -DTESTS_ENABLED=OFF \
        -DCeres_DIR=/opt/ceres-solver/lib/cmake/Ceres \
        -Dcudss_DIR=/opt/libcudss/lib/cmake/cudss \
        .. && \
    ninja -j$(nproc)

RUN ninja install --verbose



FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

RUN apt-get update && apt-get install -y --no-install-recommends \
    # OS packages
    ca-certificates \
    # COLMAP runtime dependencies
    libcholmod5 \
    libopengl0 \
    libglew2.2 \
    libgoogle-glog0v6t64 \
    libopenimageio2.4t64 \
    libcurl4t64 \
    libmetis5 \
    libboost-program-options1.83.0 \
    libspqr4 \
    libvulkan1 \
    libvulkan-dev \
    mesa-vulkan-drivers \
    vulkan-tools \
    # COLMAP CUDA runtime dependencies
    libcudart12 \
    libcusolver11 \
    libcusparse12 \
    # Brush runtime dependencies
    openimageio-tools \
    # FFmpeg
    ffmpeg && \
    apt-get clean && \
    apt-get distclean

RUN mkdir -p \
    "/workspace/videos" \
    "/workspace/scenes"

COPY --from=brush-builder /build/brush/target/release/brush /opt/brush/brush
COPY --from=colmap-builder /opt/libcudss /opt/libcudss
COPY --from=colmap-builder /opt/ceres-solver /opt/ceres-solver
COPY --from=colmap-builder /opt/colmap /opt/colmap
COPY --chmod=+x splattrack.sh /usr/local/bin/splattrack.sh

WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/splattrack.sh"]
