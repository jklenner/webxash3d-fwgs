import Xash, { Em, Module } from './generated/xash'
import { EmNet } from "./net";
import {
    DEFAULT_CLIENT_LIBRARY,
    DEFAULT_SOFT_LIBRARY,
    DEFAULT_FILESYSTEM_LIBRARY,
    DEFAULT_MENU_LIBRARY,
    DEFAULT_SERVER_LIBRARY,
    DEFAULT_GLES3COMPAT_LIBRARY,
    DEFAULT_XASH_LIBRARY,
    DEFAULT_GL4ES_LIBRARY
} from './constants'

/**
 * Rendering library override options.
 */
export type RenderLibrariesOptions = {
    soft?: string
    gles3compat?: string
    gl4es?: string
}

/**
 * Paths for core and optional engine libraries.
 */
export type LibrariesOptions = {
    filesystem?: string
    server?: string
    menu?: string
    client?: string
    xash?: string
    render?: RenderLibrariesOptions
}

/**
 * Supported renderer backends for Xash3D.
 */
export type Xash3DRenderer = 'gl4es' | 'gles3compat' | 'soft'

/**
 * Options for configuring a Xash3D instance.
 */
export type Xash3DOptions = {
    canvas?: HTMLCanvasElement
    renderer?: Xash3DRenderer
    filesMap?: Record<string, string>
    arguments?: string[]
    libraries?: LibrariesOptions
    dynamicLibraries?: string[]
    module?: Partial<Module>
}

/**
 * Reads errno from the WASM runtime.
 * @param em - Emscripten interface
 * @returns errno value or 0 if unavailable
 */
export function ErrNoLocation(em?: Em) {
    const ptr = em?.Module.ccall(
        'getErrnoLocation',
        'number',
        [],
        []
    ) as number;

    if (!ptr) return 0;

    return em!.getValue(ptr, 'i32');
}

/**
 * High-level wrapper around the Xash3D WebAssembly engine.
 */
export class Xash3D {
    /** Engine configuration */
    opts: Xash3DOptions

    /** Optional networking backend */
    net?: EmNet

    private _exited = false

    /** Whether the engine has exited */
    public get exited() {
        return this._exited;
    }

    private set exited(value: boolean) {
        this._exited = value;
    }

    private _running = false

    /** Whether the engine main loop is running */
    public get running() {
        return this._running;
    }

    private set running(value: boolean) {
        this._running = value;
    }

    /** Underlying Emscripten runtime */
    em?: Em

    /** Resolves once the WASM module has initialized */
    private emPromise?: Promise<void>

    /**
     * Create a new engine instance.
     * @param opts - Engine configuration
     */
    constructor(opts: Xash3DOptions = {}) {
        this.opts = opts;
    }

    /**
     * Execute a console command inside the engine.
     * @param cmd - Command string
     */
    Cmd_ExecuteString(cmd: string) {
        this.em?.Module?.ccall(
            'Cmd_ExecuteString',
            null,
            ['string'],
            [cmd]
        )
    }

    /**
     * Request engine termination via the `quit` command.
     */
    Sys_Quit() {
        this.Cmd_ExecuteString('quit')
    }

    /**
     * Initialize the engine runtime.
     * If already initialized, reuses the existing promise.
     */
    async init() {
        if (!this.emPromise) {
            this.emPromise = this.runEm()
        }
        await this.emPromise
        if (this.exited) {
            this.Sys_Quit()
            return
        }
    }

    /**
     * Start the main engine loop.
     * No-op if already running or exited.
     */
    main() {
        if (!this.em || this.running || this.exited) return
        this.running = true
        this.em.start()
    }

    /**
     * Shut down the engine gracefully.
     * No-op if already exited or not running.
     */
    quit() {
        if (this.exited || !this.running) return
        this.exited = true;
        this.running = false;
        this.Sys_Quit()
    }

    /**
     * Resolve a file path via `filesMap`, if mapped.
     * @param path - Path to resolve
     * @returns Mapped path or original
     */
    private locateFile(path: string) {
        return this.opts.filesMap![path] ?? path
    }

    /**
     * Configure renderer-specific libraries and arguments.
     * @param render - Renderer type
     * @returns Engine command-line arguments
     */
    private initRender(render: Xash3DOptions['renderer'] = 'gl4es'): string[] {
        switch (render) {
            case 'gl4es':
            case 'gles3compat':
                if (this.opts?.libraries?.render?.gles3compat) {
                    this.opts.filesMap![DEFAULT_GLES3COMPAT_LIBRARY] = this.opts.libraries.render.gles3compat
                }
                if (this.opts?.libraries?.render?.gl4es) {
                    this.opts.filesMap![DEFAULT_GL4ES_LIBRARY] = this.opts.libraries.render.gl4es
                }
                this.opts.dynamicLibraries!.push(DEFAULT_GLES3COMPAT_LIBRARY)
                return ['-ref', 'webgl2', ...(this.opts.arguments || [])]
            default:
                if (this.opts?.libraries?.render?.soft) {
                    this.opts.filesMap![DEFAULT_SOFT_LIBRARY] = this.opts.libraries.render.soft
                }
                this.opts.dynamicLibraries!.push(DEFAULT_SOFT_LIBRARY)
                return ['-ref', 'soft', ...(this.opts.arguments || [])]
        }
    }

    /**
     * Map a provided library path into `filesMap`.
     * @param library - Target library key
     * @param defaultPath - Default name in WASM FS
     */
    initLibrary(library: keyof Omit<LibrariesOptions, 'render'>, defaultPath: string) {
        if (this.opts.libraries?.[library]) {
            this.opts.filesMap![defaultPath] = this.opts.libraries[library]
        }
    }

    /**
     * Internal: bootstrap the WASM runtime.
     * - Loads libraries
     * - Configures canvas & renderer
     * - Initializes networking
     */
    private async runEm() {
        if (!this.opts.filesMap) {
            this.opts.filesMap = {}
        }
        if (!this.opts.dynamicLibraries) {
            this.opts.dynamicLibraries = []
        }
        if (!this.opts.arguments) {
            this.opts.arguments = []
        }

        this.initLibrary('filesystem', DEFAULT_FILESYSTEM_LIBRARY)
        this.initLibrary('client', DEFAULT_CLIENT_LIBRARY)
        this.initLibrary('server', DEFAULT_SERVER_LIBRARY)
        this.initLibrary('menu', DEFAULT_MENU_LIBRARY)
        if (this.opts.libraries?.xash) {
            this.opts.filesMap[DEFAULT_XASH_LIBRARY] = this.opts.libraries.xash
        }

        const canvas = this.opts?.canvas;
        const args = this.initRender(this.opts.renderer)
        const dynamicLibraries = [
            DEFAULT_FILESYSTEM_LIBRARY,
            DEFAULT_MENU_LIBRARY,
            DEFAULT_SERVER_LIBRARY,
            DEFAULT_CLIENT_LIBRARY,
            ...this.opts.dynamicLibraries,
        ]
        this.em = await Xash({
            canvas,
            dynamicLibraries,
            net: this.net,
            locateFile: path => this.locateFile(path),
            arguments: args,
            ...(this.opts.module ?? {}),
        })
        if (this.net) {
            this.net.init(this.em)
        }
        this.em.FS.mkdir('/rwdir')
    }
}
