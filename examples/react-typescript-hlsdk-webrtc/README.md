# React Xash3D-FWGS HLSDK Portable WebRTC with TypeScript

This project integrates the Xash3D-FWGS HLSDK Portable with a React + WebRTC Online + TypeScript frontend.

WebRTC provides near-UDP performance in the browser—typically [2–3 times faster](https://github.com/yohimik/ws-webrtc-benchmark) than WebSockets.

1. Start by using [the goxash3d-fwgs WebRTC example](https://github.com/yohimik/goxash3d-fwgs/tree/main/examples/webrtc-hl) dedicated server.
2. Check out WebRTC example.
3. Connect to the server via the multiplayer LAN menu or by using the console command: `connect 127.0.0.1:8080`.

## Quick Start

Install dependencies:

```shell
pnpm install
```

Zip and copy the `valve` folder from your Half-Life installation into the `public/valve.zip`.
Note: zip contents should be like this:
```shell
/valve.zip
└──┬/valve                  
   ├───/file1           
   └───/file2...
```

Start the app:

```shell
npm start
```
Open http://localhost:3000 in your browser.
