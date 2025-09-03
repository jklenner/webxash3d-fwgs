import React, {FC, useRef} from 'react';
import {Xash3D} from "xash3d-fwgs";
import filesystemURL from 'xash3d-fwgs/filesystem_stdio.wasm'
import xashURL from 'xash3d-fwgs/xash.wasm'
import menuURL from 'xash3d-fwgs/cl_dll/menu_emscripten_wasm32.wasm'
import clientURL from 'hlsdk-portable/cl_dll/client_emscripten_wasm32.wasm'
import serverURL from 'hlsdk-portable/dlls/hl_emscripten_wasm32.so'
import gles3URL from 'xash3d-fwgs/libref_gles3compat.wasm'
import './App.css';

const App: FC = () => {
    const canvasRef = useRef<HTMLCanvasElement>(null)

    return (
        <>
            <input
                className="Input"
                type="file"
                id="folder"
                multiple
                // @ts-ignore
                webkitdirectory={1}
                onChange={async (e) => {
                    if (!e.target?.files?.length) return

                    const x = new Xash3D({
                        canvas: canvasRef.current!,
                        libraries: {
                            filesystem: filesystemURL,
                            xash: xashURL,
                            menu: menuURL,
                            client: clientURL,
                            server: serverURL,
                            render: {
                                gles3compat: gles3URL,
                            }
                        },
                        arguments: ['-windowed'],
                    })
                    await x.init()
                    await Promise.all(Array.from(e.target.files!).map(async f => {
                        const path = `/rodir/${f.webkitRelativePath}`
                        const dir = path.split('/').slice(0, -1).join('/');
                        x.em.FS.mkdirTree(dir)
                        x.em.FS.writeFile(path, new Uint8Array(await f.arrayBuffer()))
                    }))
                    x.em.FS.chdir('/rodir/')
                    x.main()
                }}
            />
            <label htmlFor="folder">
                Game folder
            </label>
            <canvas id="canvas" ref={canvasRef}/>
        </>
    );
}

export default App;
