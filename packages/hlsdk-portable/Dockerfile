FROM emscripten/emsdk:4.0.13

WORKDIR /hlsdk-portable
COPY hlsdk-portable .
RUN emconfigure ./waf configure --emscripten -T release && \
    emmake ./waf && \
    emconfigure ./waf install --destdir out

ENTRYPOINT ["cp", "-r", "/hlsdk-portable/out/.", "/out/"]