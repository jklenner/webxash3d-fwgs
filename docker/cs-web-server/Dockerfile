FROM debian:trixie-slim AS engine

RUN dpkg --add-architecture i386
RUN echo "deb http://deb.debian.org/debian testing main" > /etc/apt/sources.list.d/testing.list

# 1) Install a single, consistent toolchain (GCC 14 + binutils) from testing
RUN apt-get update && \
    apt-get install -y -t testing \
      gcc-14 g++-14 gcc-14-multilib g++-14-multilib \
      binutils binutils-gold gcc-14-plugin-dev && \
    # keep other deps AFTER toolchain
    apt-get install -y --no-install-recommends \
      git ca-certificates build-essential \
      gcc-multilib g++-multilib \
      libbsd-dev:i386 libsdl2-dev:i386 libfreetype-dev:i386 \
      libopus-dev:i386 libbz2-dev:i386 libvorbis-dev:i386 \
      libopusfile-dev:i386 libogg-dev:i386 && \
    # 2) Make /usr/bin/* resolve to the 14-series explicitly
    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 100 && \
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-14 100 && \
    update-alternatives --set gcc /usr/bin/gcc-14 && \
    update-alternatives --set g++ /usr/bin/g++-14

# 3) Tell the build to use matching LTO-aware tools
ENV CC=/usr/bin/gcc-14 \
    CXX=/usr/bin/g++-14 \
    AR=/usr/bin/gcc-ar-14 \
    NM=/usr/bin/gcc-nm-14 \
    RANLIB=/usr/bin/gcc-ranlib-14

ENV PKG_CONFIG_PATH=/usr/lib/i386-linux-gnu/pkgconfig
WORKDIR /xash

RUN git clone --branch go --single-branch https://github.com/jklenner/xash3d-fwgs . \
    && git submodule update --init --recursive

# 4) Clean any previous build dir just in case
RUN rm -rf build

# 5) Build with LTO using the pinned toolchain
RUN ./waf configure -T release -d --enable-lto --enable-openmp && ./waf build

FROM golang:1.25 AS go

WORKDIR /go
COPY go.mod go.mod
COPY go.sum go.sum
RUN go mod download
RUN mkdir -p ../github.com/jklenner/goxash3d-fwgs
RUN cp -r $(go list -m -f '{{.Dir}}' github.com/jklenner/goxash3d-fwgs)/* ../github.com/jklenner/goxash3d-fwgs
RUN echo 'replace github.com/jklenner/goxash3d-fwgs => ../github.com/jklenner/goxash3d-fwgs' >> go.mod

COPY src/server src/server
COPY --from=engine /xash/build/engine/libxash.a ../github.com/jklenner/goxash3d-fwgs/pkg/libxash.a
COPY --from=engine /xash/build/public/libbuild_vcs.a ../github.com/jklenner/goxash3d-fwgs/pkg/libbuild_vcs.a
COPY --from=engine /xash/build/public/libpublic.a ../github.com/jklenner/goxash3d-fwgs/pkg/libpublic.a
COPY --from=engine /xash/build/3rdparty/libbacktrace/libbacktrace.a ../github.com/jklenner/goxash3d-fwgs/pkg/libbacktrace.a

ENV GOARCH=386
ENV CC="gcc -m32 -D__i386__"
ENV CGO_CFLAGS="-fopenmp -m32"
ENV CGO_LDFLAGS="-fopenmp -m32"
RUN go build -o ./xash ./src/server

FROM debian:trixie-slim AS hlds

ARG hlds_build=8308
ARG hlds_url="https://github.com/DevilBoy-eXe/hlds/releases/download/$hlds_build/hlds_build_$hlds_build.zip"

RUN groupadd -r xash && useradd -r -g xash -m -d /opt/xash xash
RUN usermod -a -G games xash

RUN apt-get -y update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    unzip \
    && apt-get -y clean

USER xash
WORKDIR /opt/xash
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN mkdir -p /opt/xash/xashds

RUN curl -sLJO "$hlds_url" \
    && unzip "hlds_build_$hlds_build.zip" -d "/opt/xash/hlds_build_$hlds_build" \
    && cp -R "hlds_build_$hlds_build/hlds"/* xashds/ \
    && rm -rf "hlds_build_$hlds_build" "hlds_build_$hlds_build.zip"

# Fix warnings:
# couldn't exec listip.cfg
# couldn't exec banned.cfg
RUN touch /opt/xash/xashds/valve/listip.cfg
RUN touch /opt/xash/xashds/valve/banned.cfg

WORKDIR /opt/xash/xashds

# Copy default config
COPY configs/valve valve
COPY configs/cstrike cstrike

FROM --platform=linux/amd64 node:22-alpine AS client

WORKDIR /client

COPY package.json package.json
COPY package-lock.json package-lock.json
RUN npm ci
COPY vite.config.ts vite.config.ts
COPY tsconfig.json tsconfig.json
COPY src/client src/client

RUN npm i -D @vitejs/plugin-basic-ssl
RUN npm run build

FROM debian:trixie-slim AS final

ENV XASH3D_BASEDIR=/xashds

RUN dpkg --add-architecture i386
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgcc-s1:i386 \
    libstdc++6:i386 \
    libgomp1:i386 \
    ca-certificates \
    openssl \
    && apt-get clean

RUN groupadd xashds && useradd -m -g xashds xashds
USER xashds
WORKDIR /xashds
ENV LD_LIBRARY_PATH=/xashds

COPY --from=hlds /opt/xash/xashds .
COPY --from=go /go/xash ./xash
COPY --from=client /client/src/client/dist ./public
COPY --from=engine /xash/build/filesystem/filesystem_stdio.so ./filesystem_stdio.so
COPY --from=engine "/usr/lib/i386-linux-gnu/libstdc++.so.6" "./libstdc++.so.6"
COPY --from=engine "/usr/lib/i386-linux-gnu/libgcc_s.so.1" "./libgcc_s.so.1"
EXPOSE 27015/udp

# Start server
ENTRYPOINT ["./xash", "+ip", "0.0.0.0", "-port", "27015", "-game", "cstrike"]

# Default start parameters
CMD ["+map de_dust2", "+maxplayers", "16"]
