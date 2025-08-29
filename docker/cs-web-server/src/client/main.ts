import { loadAsync } from 'jszip'
import filesystemURL from 'xash3d-fwgs/filesystem_stdio.wasm?url'
import xashURL from 'xash3d-fwgs/xash.wasm?url'
import menuURL from 'cs16-client/cl_dll/menu_emscripten_wasm32.wasm?url'
import clientURL from 'cs16-client/cl_dll/client_emscripten_wasm32.wasm?url'
import serverURL from 'cs16-client/dlls/cs_emscripten_wasm32.so?url'
import gles3URL from 'xash3d-fwgs/libref_gles3compat.wasm?url'
import { Xash3DWebRTC } from './webrtc'

// ===== Username handshake =====
let usernamePromiseResolve: (name: string) => void
const usernamePromise = new Promise<string>((resolve) => {
  usernamePromiseResolve = resolve
})

// ===== Progress plumbing (BroadcastChannel) =====
const PROGRESS_CH = typeof BroadcastChannel !== 'undefined' ? new BroadcastChannel('dl-progress') : null
function reportProgress(msg: any) {
  try { PROGRESS_CH?.postMessage(msg) } catch {}
}

// ===== Fetch with byte-progress & cache validation =====
async function fetchArrayBufferWithProgress(url: string, init?: RequestInit): Promise<ArrayBuffer> {
  const res = await fetch(url, init)
  if (!res.ok) throw new Error(`Failed to fetch ${url}: ${res.status} ${res.statusText}`)
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
  for (const c of chunks) { result.set(c, offset); offset += c.byteLength }
  reportProgress({ type: 'done', url, loaded, total })
  return result.buffer
}

// ===== Simple IndexedDB layer (no IDBFS) =====
const DB_NAME = 'cs-assets'
const STORE_FILES = 'rodir'
const STORE_META = 'meta'
type IDBValue = ArrayBuffer

function idbAvailable() {
  try { return !!indexedDB } catch { return false }
}

function openDB(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, 1)
    req.onupgradeneeded = () => {
      const db = req.result
      if (!db.objectStoreNames.contains(STORE_FILES)) db.createObjectStore(STORE_FILES)
      if (!db.objectStoreNames.contains(STORE_META)) db.createObjectStore(STORE_META)
    }
    req.onsuccess = () => resolve(req.result)
    req.onerror = () => reject(req.error)
  })
}

function idbGet(db: IDBDatabase, store: string, key: string): Promise<any> {
  return new Promise((resolve, reject) => {
    const tx = db.transaction(store, 'readonly')
    const os = tx.objectStore(store)
    const req = os.get(key)
    req.onsuccess = () => resolve(req.result ?? null)
    req.onerror = () => reject(req.error)
  })
}

function idbSet(db: IDBDatabase, store: string, key: string, val: any): Promise<void> {
  return new Promise((resolve, reject) => {
    const tx = db.transaction(store, 'readwrite')
    const os = tx.objectStore(store)
    const req = os.put(val, key)
    req.onsuccess = () => resolve()
    req.onerror = () => reject(req.error)
  })
}

function idbClear(db: IDBDatabase, store: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const tx = db.transaction(store, 'readwrite')
    const os = tx.objectStore(store)
    const req = os.clear()
    req.onsuccess = () => resolve()
    req.onerror = () => reject(req.error)
  })
}

async function idbPutMany(db: IDBDatabase, entries: Array<{ path: string, data: Uint8Array }>): Promise<number> {
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE_FILES, 'readwrite')
    const os = tx.objectStore(STORE_FILES)
    let totalBytes = 0
    let i = 0
    function next() {
      if (i >= entries.length) return
      const { path, data } = entries[i++]
      totalBytes += data.byteLength
      const req = os.put(data.buffer as IDBValue, path)
      req.onsuccess = () => next()
      req.onerror = () => reject(req.error)
    }
    tx.oncomplete = () => resolve(totalBytes)
    tx.onerror = () => reject(tx.error)
    next()
  })
}

async function idbRestoreToFS(x: Xash3DWebRTC, db: IDBDatabase, totalBytesHint: number | null) {
  const FS = x.em.FS
  // We’ll stream via a cursor and update progress
  return new Promise<void>((resolve, reject) => {
    const tx = db.transaction(STORE_FILES, 'readonly')
    const os = tx.objectStore(STORE_FILES)
    const req = os.openCursor()
    let loaded = 0
    const total = totalBytesHint || 0

    reportProgress({ type: 'unzip-start', totalFiles: 0, totalBytes: total })

    req.onsuccess = async () => {
      const cursor = req.result as IDBCursorWithValue | null
      if (!cursor) return
      const path = String(cursor.key)
      const ab = cursor.value as ArrayBuffer
      try {
        const dirPath = '/rodir/' + path.split('/').slice(0, -1).join('/')
        if (dirPath) FS.mkdirTree(dirPath)
        FS.writeFile('/rodir/' + path, new Uint8Array(ab))
        loaded += ab.byteLength || 0
        reportProgress({
          type: 'unzip-progress',
          file: path,
          fileIndex: 0,
          filePercent: 100,
          loadedBytes: total ? Math.min(loaded, total) : loaded,
          totalBytes: total || Math.max(1, loaded) // avoid 0
        })
      } catch (e) {
        reject(e)
        return
      }
      cursor.continue()
    }
    tx.oncomplete = () => {
      reportProgress({ type: 'unzip-done', totalFiles: 0, totalBytes: total })
      resolve()
    }
    tx.onerror = () => reject(tx.error)
  })
}

// ===== Versioning via ETag / Last-Modified / optional valve.version =====
async function getRemoteValveTag(): Promise<string | null> {
  try {
    const head = await fetch('valve.zip', { method: 'HEAD', cache: 'no-cache' })
    if (head.ok) {
      const et = head.headers.get('etag')
      const lm = head.headers.get('last-modified')
      if (et) return et
      if (lm) return lm
    }
  } catch {}
  try {
    const r = await fetch('valve.version', { cache: 'no-cache' })
    if (r.ok) return (await r.text()).trim() || null
  } catch {}
  return null
}

// ===== Main =====
async function main() {
  const x = new Xash3DWebRTC({
    canvas: document.getElementById('canvas') as HTMLCanvasElement,
    module: { arguments: ['-windowed', '-game', 'cstrike'], INITIAL_MEMORY: 512 * 1024 * 1024  },
    libraries: {
      filesystem: filesystemURL,
      xash: xashURL,
      menu: menuURL,
      server: serverURL,
      client: clientURL,
      render: { gles3compat: gles3URL },
    },
    filesMap: {
      'dlls/cs_emscripten_wasm32.so': serverURL,
      '/rwdir/filesystem_stdio.so': filesystemURL,
    },
  })

  // Reduce eviction risk for large caches
  try { await navigator.storage?.persist?.() } catch {}

  // Init engine first (ensures x.em & FS are ready)
  await x.init()

// Prevent detached-ArrayBuffer crashes on level changes: pre-grow heap
try {
  const em: any = (x as any).em;
  const TARGET = 512 * 1024 * 1024; // try 256 MiB first; bump to 384/512 if you still see growth
  if (typeof em._emscripten_resize_heap === 'function') {
    if (em.HEAP8?.buffer?.byteLength < TARGET) em._emscripten_resize_heap(TARGET);
  }
  console.log('[mem] heap bytes:', em.HEAP8?.buffer?.byteLength);
} catch (e) { console.warn('heap pre-grow failed', e); }

  // Always work out of in-memory /rodir (classic MEMFS)
  const FS = x.em.FS
  try { FS.mkdir('/rodir') } catch {}

  // Decide whether to restore or (re)download
  const remoteTag = await getRemoteValveTag()
  const canIDB = idbAvailable()
  let db: IDBDatabase | null = null
  let localTag: string | null = null
  let totalBytesHint: number | null = null

  if (canIDB) {
    db = await openDB()
    localTag = await idbGet(db, STORE_META, 'valve.version')
    totalBytesHint = await idbGet(db, STORE_META, 'valve.totalBytes')?.then?.((x: any)=>x).catch?.(()=>null) ?? await idbGet(db, STORE_META, 'valve.totalBytes')
  }

  const upToDate = !!remoteTag && remoteTag === localTag

  if (canIDB && db && upToDate) {
    // “fake” download complete to keep your UI consistent
    reportProgress({ type: 'start', url: 'valve.zip', loaded: 0, total: 2 })
    reportProgress({ type: 'progress', url: 'valve.zip', loaded: 1, total: 2 })
    reportProgress({ type: 'done',  url: 'valve.zip', loaded: 2, total: 2 })

    // Restore unzipped files from IDB into /rodir (fast, no unzip)
    await idbRestoreToFS(x, db, typeof totalBytesHint === 'number' ? totalBytesHint : null)

  } else {
    // Either first run, version changed, or no IDB — download (304 if unchanged in HTTP cache)
    const ab = await fetchArrayBufferWithProgress('valve.zip', { cache: 'no-cache' })
    const zip = await loadAsync(ab)

    // Unzip sequentially into /rodir and, if possible, persist into IDB
    const entries = Object.values(zip.files).filter((f: any) => !f.dir) as any[]

    let totalUnc = 0
    const sizes: number[] = entries.map((f) => {
      const s = (f._data && typeof f._data.uncompressedSize === 'number') ? f._data.uncompressedSize : 0
      totalUnc += s
      return s
    })

    reportProgress({ type: 'unzip-start', totalFiles: entries.length, totalBytes: totalUnc })

    let doneBytes = 0
    const batchForIDB: Array<{ path: string, data: Uint8Array }> = []

    for (let i = 0; i < entries.length; i++) {
      const file = entries[i]
      const filename = file.name as string
      const dirPath = '/rodir/' + filename.split('/').slice(0, -1).join('/')
      if (dirPath) FS.mkdirTree(dirPath)

      const thisSize = sizes[i] || 0
      const hasBytes = totalUnc > 0 && thisSize > 0

      const onUpdate = (meta: { percent: number }) => {
        const filePct = Math.max(0, Math.min(100, meta.percent || 0))
        const loadedBytes = hasBytes
          ? Math.round(doneBytes + thisSize * (filePct / 100))
          : Math.round(((i + filePct / 100) / entries.length) * 1000)
        reportProgress({
          type: 'unzip-progress',
          file: filename,
          fileIndex: i,
          filePercent: filePct,
          loadedBytes,
          totalBytes: totalUnc || 1000
        })
      }

      const data: Uint8Array = await file.async('uint8array', onUpdate)

      // Write into in-memory FS
      FS.writeFile('/rodir/' + filename, data)

      // Stage for persistence
      if (canIDB && db) batchForIDB.push({ path: filename, data })

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

    reportProgress({ type: 'unzip-done', totalFiles: entries.length, totalBytes: totalUnc })

    // Persist to IndexedDB (replace old content) and store new version tag/meta
    if (canIDB && db) {
      await idbClear(db, STORE_FILES)
      const writtenBytes = await idbPutMany(db, batchForIDB)
      if (remoteTag) await idbSet(db, STORE_META, 'valve.version', remoteTag)
      await idbSet(db, STORE_META, 'valve.totalBytes', writtenBytes)
    }
  }

  // Ready — change working directory and continue as before
  FS.chdir('/rodir')

  // Trigger your "loading finished" animation; your page listens for this
  const logo = document.getElementById('logo')!
  logo.style.animationName = 'pulsate-end'
  logo.style.animationFillMode = 'forwards'
  logo.style.animationIterationCount = '1'
  logo.style.animationDirection = 'normal'

  // Proceed with engine startup
  const username = await usernamePromise
  x.main()
  x.Cmd_ExecuteString('_vgui_menus 0')
  if (!window.matchMedia('(hover: hover)').matches) x.Cmd_ExecuteString('touch_enable 1')
  x.Cmd_ExecuteString(`name "${username}"`)
  x.Cmd_ExecuteString('connect 127.0.0.1:8080')

  window.addEventListener('beforeunload', (event) => {
    event.preventDefault()
    event.returnValue = ''
    return ''
  })
}

// ===== Username persistence in localStorage + form handling =====
const savedUsername = localStorage.getItem('username')
if (savedUsername) {
  (document.getElementById('username') as HTMLInputElement).value = savedUsername
}

;(document.getElementById('form') as HTMLFormElement).addEventListener('submit', (e) => {
  e.preventDefault()
  const username = (document.getElementById('username') as HTMLInputElement).value
  localStorage.setItem('username', username)
  ;(document.getElementById('form') as HTMLFormElement).style.display = 'none'
  usernamePromiseResolve(username)
})

// Kick off
main()
