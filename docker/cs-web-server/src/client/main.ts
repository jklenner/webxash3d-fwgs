import { loadAsync } from 'jszip'
import filesystemURL from 'xash3d-fwgs/filesystem_stdio.wasm?url'
import xashURL from 'xash3d-fwgs/xash.wasm?url'
import menuURL from 'cs16-client/cl_dll/menu_emscripten_wasm32.wasm?url'
import clientURL from 'cs16-client/cl_dll/client_emscripten_wasm32.wasm?url'
import serverURL from 'cs16-client/dlls/cs_emscripten_wasm32.so?url'
import gles3URL from 'xash3d-fwgs/libref_gles3compat.wasm?url'
import { Xash3DWebRTC } from './webrtc'

let usernamePromiseResolve: (name: string) => void
const usernamePromise = new Promise<string>((resolve) => {
  usernamePromiseResolve = resolve
})

// ---- Progress plumbing (BroadcastChannel) ----
const PROGRESS_CH = typeof BroadcastChannel !== 'undefined' ? new BroadcastChannel('dl-progress') : null
function reportProgress(msg: any) {
  try { PROGRESS_CH?.postMessage(msg) } catch {}
}

// Stream a URL to ArrayBuffer and report progress
async function fetchArrayBufferWithProgress(url: string): Promise<ArrayBuffer> {
  const res = await fetch(url)
  const total = Number(res.headers.get('content-length')) || 0

  if (!res.body) {
    reportProgress({ type: 'start', url, loaded: 0, total })
    const ab = await res.arrayBuffer()
    reportProgress({ type: 'progress', url, loaded: ab.byteLength, total })
    reportProgress({ type: 'done', url, loaded: ab.byteLength, total })
    return ab
  }

  reportProgress({ type: 'start', url, loaded: 0, total })

  const reader = res.body.getReader()
  const chunks: Uint8Array[] = []
  let loaded = 0

  try {
    while (true) {
      const { done, value } = await reader.read()
      if (done) break
      if (value) {
        chunks.push(value)
        loaded += value.byteLength
        reportProgress({ type: 'progress', url, loaded, total })
      }
    }
  } catch (err) {
    reportProgress({ type: 'error', url, error: String(err) })
    throw err
  }

  const result = new Uint8Array(loaded)
  let offset = 0
  for (const c of chunks) {
    result.set(c, offset)
    offset += c.byteLength
  }

  reportProgress({ type: 'done', url, loaded, total })
  return result.buffer
}

async function main() {
  const x = new Xash3DWebRTC({
    canvas: document.getElementById('canvas') as HTMLCanvasElement,
    module: {
      arguments: ['-windowed', '-game', 'cstrike'],
    },
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
    filesMap: {
      'dlls/cs_emscripten_wasm32.so': serverURL,
      '/rwdir/filesystem_stdio.so': filesystemURL,
    },
  })

  const [zip] = await Promise.all([
    (async () => {
      const ab = await fetchArrayBufferWithProgress('valve.zip')
      return await loadAsync(ab)
    })(),
    x.init(),
  ])

  // ----- Unzip progress (sequential) -----
  const entries = Object.values(zip.files).filter((f: any) => !f.dir) as any[]
  // Try to compute total uncompressed bytes (may be 0 if JSZip can’t expose it yet)
  // Many JSZip builds expose `f._data?.uncompressedSize`. If unavailable, we'll fall back to equal weighting.
  let totalUnc = 0
  const sizes: number[] = entries.map((f) => {
    const s = (f._data && typeof f._data.uncompressedSize === 'number') ? f._data.uncompressedSize : 0
    totalUnc += s
    return s
  })

  reportProgress({
    type: 'unzip-start',
    totalFiles: entries.length,
    totalBytes: totalUnc
  })

  let doneBytes = 0

  for (let i = 0; i < entries.length; i++) {
    const file = entries[i]
    const filename = file.name as string
    const dirPath = '/rodir/' + filename.split('/').slice(0, -1).join('/')

    if (dirPath) x.em.FS.mkdirTree(dirPath)

    const thisSize = sizes[i] || 0
    const hasBytes = totalUnc > 0 && thisSize > 0

    // Per-file progress callback
    const onUpdate = (meta: { percent: number }) => {
      const filePct = Math.max(0, Math.min(100, meta.percent || 0))
      const loadedBytes = hasBytes
        ? Math.round(doneBytes + thisSize * (filePct / 100))
        : Math.round(((i + filePct / 100) / entries.length) * 1000) // pseudo-bytes scale if unknown
      reportProgress({
        type: 'unzip-progress',
        file: filename,
        fileIndex: i,
        filePercent: filePct,
        loadedBytes,
        totalBytes: totalUnc || 1000 // match pseudo scale if total unknown
      })
    }

    const data: Uint8Array = await file.async('uint8array', onUpdate)
    const fullPath = '/rodir/' + filename
    x.em.FS.writeFile(fullPath, data)

    // Close out this file’s contribution
    if (hasBytes) doneBytes += thisSize
    reportProgress({
      type: 'unzip-progress',
      file: filename,
      fileIndex: i,
      filePercent: 100,
      loadedBytes: hasBytes ? doneBytes : Math.round(((i + 1) / entries.length) * 1000),
      totalBytes: totalUnc || 1000
    })
  }

  reportProgress({
    type: 'unzip-done',
    totalFiles: entries.length,
    totalBytes: totalUnc
  })

  // Mount and continue as before
  x.em.FS.chdir('/rodir')

  // Trigger your "loading finished" animation; your page listens for this
  const logo = document.getElementById('logo')!
  logo.style.animationName = 'pulsate-end'
  logo.style.animationFillMode = 'forwards'
  logo.style.animationIterationCount = '1'
  logo.style.animationDirection = 'normal'

  const username = await usernamePromise
  x.main()
  x.Cmd_ExecuteString('_vgui_menus 0')
  if (!window.matchMedia('(hover: hover)').matches) {
    x.Cmd_ExecuteString('touch_enable 1')
  }
  x.Cmd_ExecuteString(`name "${username}"`)
  x.Cmd_ExecuteString('connect 127.0.0.1:8080')

  window.addEventListener('beforeunload', (event) => {
    event.preventDefault()
    event.returnValue = ''
    return ''
  })
}

const username = localStorage.getItem('username')
if (username) {
  (document.getElementById('username') as HTMLInputElement).value = username
}

(document.getElementById('form') as HTMLFormElement).addEventListener('submit', (e) => {
  e.preventDefault()
  const username = (document.getElementById('username') as HTMLInputElement).value
  localStorage.setItem('username', username)
  ;(document.getElementById('form') as HTMLFormElement).style.display = 'none'
  usernamePromiseResolve(username)
})

main()
