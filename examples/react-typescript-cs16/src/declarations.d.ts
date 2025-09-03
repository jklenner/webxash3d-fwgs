// declarations.d.ts

// Allow importing .wasm files as modules
declare module "*.wasm" {
    const value: string;
    export default value;
}

// Allow importing .zip files as modules
declare module "*.zip" {
    const value: string;
    export default value;
}

// Allow importing .so files as modules
declare module "*.so" {
    const value: string;
    export default value;
}

// Allow importing .pk3 files as modules
declare module "*.pk3" {
    const value: string;
    export default value;
}