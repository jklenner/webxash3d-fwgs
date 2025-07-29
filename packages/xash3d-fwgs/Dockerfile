FROM emscripten/emsdk:4.0.11

WORKDIR /xash3d-fwgs
COPY xash3d-fwgs .
ENV EMCC_CFLAGS="-s USE_SDL=2"
RUN emconfigure ./waf configure --emscripten && \
	emmake ./waf build

RUN mkdir out
RUN mkdir out/cl_dll
RUN mv build/3rdparty/mainui/libmenu.wasm out/cl_dll/menu_emscripten_wasm32.wasm
RUN mv build/engine/xash.js out/raw.js
RUN mv build/engine/xash.wasm out/xash.wasm
RUN mv build/filesystem/filesystem_stdio.wasm out/filesystem_stdio.wasm
RUN mv build/ref/gl/libref_webgl2.wasm out/libref_webgl2.wasm
RUN mv build/ref/soft/libref_soft.wasm out/libref_soft.wasm
ENTRYPOINT ["cp", "-r", "/xash3d-fwgs/out/.", "/out/"]