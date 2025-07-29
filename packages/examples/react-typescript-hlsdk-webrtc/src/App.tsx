import React, {FC, useRef} from 'react';
import filesystemURL from 'xash3d-fwgs/filesystem_stdio.wasm'
import xashURL from 'xash3d-fwgs/xash.wasm'
import menuURL from 'xash3d-fwgs/cl_dll/menu_emscripten_wasm32.wasm'
import clientURL from 'hlsdk-portable/cl_dll/client_emscripten_wasm32.wasm'
import serverURL from 'hlsdk-portable/dlls/hl_emscripten_wasm32.so'
import webgl2URL from 'xash3d-fwgs/libref_webgl2.wasm'
import {loadAsync} from 'jszip'
import {Xash3DWebRTC} from "./webrtc";
import './App.css';

const App: FC = () => {
    const canvasRef = useRef<HTMLCanvasElement>(null)

    return (
        <>
            <button className="Input" onClick={async () => {
                const x = new Xash3DWebRTC({
                    canvas: canvasRef.current!,
                    libraries: {
                        filesystem: filesystemURL,
                        xash: xashURL,
                        menu: menuURL,
                        server: serverURL,
                        client: clientURL,
                        render: {
                            gl4es: webgl2URL,
                        }
                    },
                    module: {
                        arguments: ['-windowed', '-ref', 'webgl2'],
                    }
                });

                const [zip] = await Promise.all([
                    (async () => {
                        const res = await fetch('valve.zip')
                        return await loadAsync(await res.arrayBuffer());
                    })(),
                    x.init(),
                ])

                if (x.exited) return

                await Promise.all(Object.entries(zip.files).map(async ([filename, file]) => {
                    if (file.dir) return;

                    const path = '/rodir/' + filename;
                    const dir = path.split('/').slice(0, -1).join('/');

                    x.em.FS.mkdirTree(dir);
                    x.em.FS.writeFile(path, await file.async("uint8array"));
                }))

                x.em.FS.mkdirTree('/rwdir')
                x.em.FS.chdir('/rodir')
                x.main()
            }}>
                Start
            </button>
            <canvas id="canvas" ref={canvasRef}/>
        </>
    );
}

export default App;
