# 📡 WebXash3D-MServer

[![Join our Discord](https://img.shields.io/discord/1397890383605927967?color=5865F2&label=Discord&logo=discord&logoColor=white&style=for-the-badge)](https://discord.gg/cRNGjWfTDd)

> In-game server registration + WebRTC signaling middleware for WebXash3D-powered multiplayer games.
> Built with Fastify, written in TypeScript, powered by Swagger, and designed for real-time gaming.

## 🧩 Features

* ✅ Lightweight HTTP server for server registration
* ✅ WebRTC signaling for peer discovery
* ✅ Automatic OpenAPI (Swagger) docs (can be disabled)
* ✅ Fastify-based (high-performance Node.js server)
* ✅ Built-in logging with optional pretty output
* ✅ Written in TypeScript

## 📦 Installation

```shell
npm install webxash3d-mserver
# or
yarn add webxash3d-mserver
```

## 🚀 Quick Start

```typescript
import {HTTPMServer} from "webxash3d-mserver"

const server = new HTTPMServer({
    port: 3000, // Required: the port your signaling server will listen on
    disableDocs: false, // Optional: disables Swagger docs (default: false)
    logLevel: 'info', // Optional: Pino log level (e.g. 'info', 'debug', 'error')
    enablePrettyLogs: true, // Optional: enable human-readable logs
})

server.start()
```

## 🧠 What Does It Do?

This package is meant to power the backend signaling infrastructure for games using WebXash3D. It does two main things:

1. Registers game servers so they appear in an in-game server list.
2. Handles WebRTC signaling to help clients and servers establish peer-to-peer connections.

It abstracts away the boring parts of multiplayer infrastructure so you can focus on your game.

## ⚙️ Constructor Options

| Option             | Type         | Description                                                       |
|--------------------|--------------|-------------------------------------------------------------------|
| `port`             | `number`     | Required. The HTTP server port to bind to.                        |
| `disableDocs`      | `boolean`    | Optional. Disables auto-generated Swagger docs. Default: `false`. |
| `logLevel`         | `pino.Level` | Optional. Sets logging level. Default: `'info'`.                  |
| `enablePrettyLogs` | `boolean`    | Optional. Enables pretty-printed logs. Default: `false`.          |

## 📑 API Endpoints

| Method | Path          | Description                                   |
|--------|---------------|-----------------------------------------------|
| `GET`  | `/v1/servers` | Required. Get list of registered game servers |
| `WS`   | `/ws`         | WS endpoint (client ↔ peer)                   |
| `GET`  | `/docs`       | Swagger UI (auto-generated API docs)          |

## 🌐 Discord Community

Need help? Want to share your project or ideas?
**[Join our Discord community](https://discord.gg/cRNGjWfTDd)** to connect with others!

## 📄 License

MIT License — free for personal and commercial use.

## 📝 Changelog

See [CHANGELOG.md](https://github.com/yohimik/webxash3d-fwgs/tree/main/packages/webxash3d-mserver/CHANGELOG.md) for a full list of updates and release history.