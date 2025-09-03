import React, {FC, useRef} from 'react';
import {Xash3D} from "xash3d-fwgs";
import filesystemURL from 'xash3d-fwgs/filesystem_stdio.wasm'
import xashURL from 'xash3d-fwgs/xash.wasm'
import menuURL from 'cs16-client/cl_dll/menu_emscripten_wasm32.wasm'
import clientURL from 'cs16-client/cl_dll/client_emscripten_wasm32.wasm'
import serverURL from 'cs16-client/dlls/cs_emscripten_wasm32.so'
import gles3URL from 'xash3d-fwgs/libref_gles3compat.wasm'
import {loadAsync} from 'jszip'
import './App.css';

const App: FC = () => {
    const canvasRef = useRef<HTMLCanvasElement>(null)

    return (
        <>
            <button onClick={async () => {
                const x = new Xash3D({
                    canvas: canvasRef.current!,
                    arguments: ['-windowed', '-game', 'cstrike'],
                    libraries: {
                        filesystem: filesystemURL,
                        xash: xashURL,
                        menu: menuURL,
                        server: serverURL,
                        client: clientURL,
                        render: {
                            gles3compat: gles3URL,
                        }
                    },
                    dynamicLibraries: ['dlls/cs_emscripten_wasm32.so', '/rwdir/filesystem_stdio.wasm'],
                    filesMap: {
                        'dlls/cs_emscripten_wasm32.so': serverURL,
                        '/rwdir/filesystem_stdio.wasm': filesystemURL,
                    },
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

                x.em.FS.chdir('/rodir')
                x.main()
                x.Cmd_ExecuteString('_vgui_menus 0')
            }}>
                Start
            </button>
            <canvas id="canvas" ref={canvasRef}/>
        </>
    );
}

export default App;
