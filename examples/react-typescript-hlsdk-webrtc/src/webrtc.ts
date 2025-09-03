import {Packet, Xash3D, Xash3DOptions, Net} from "xash3d-fwgs";

export class Xash3DWebRTC extends Xash3D {
    private channel?: RTCDataChannel
    private resolve?: (value?: unknown) => void
    private ws?: WebSocket
    private peer?: RTCPeerConnection

    constructor(opts?: Xash3DOptions) {
        super(opts);
        this.net = new Net(this)
    }

    async init() {
        await Promise.all([
            super.init(),
            this.connect()
        ]);
    }

    initConnection(stream: MediaStream) {
        if (this.peer) return

        this.peer = new RTCPeerConnection()
        this.peer.onicecandidate = e => {
            if (!e.candidate) {
                return
            }
            this.ws!.send(JSON.stringify({
                event: 'candidate',
                data: JSON.stringify(e.candidate.toJSON())
            }))
        }
        stream?.getTracks()?.forEach(t => {
            this.peer!.addTrack(t, stream)
        })
        let channelsCount = 0
        this.peer.ondatachannel = (e) => {
            if (e.channel.label === 'write') {
                e.channel.onmessage = (ee) => {
                    const packet: Packet = {
                        ip: [127, 0, 0, 1],
                        port: 8080,
                        data: ee.data
                    }
                    if (ee.data.arrayBuffer) {
                        ee.data.arrayBuffer().then((data: Int8Array) => {
                            packet.data = data;
                            (this.net as Net).incoming.enqueue(packet)
                        })
                    } else {
                        (this.net as Net).incoming.enqueue(packet)
                    }
                }
            }
            e.channel.onopen = () => {
                channelsCount += 1
                if (e.channel.label === 'read') {
                    this.channel = e.channel
                }
                if (channelsCount === 2) {
                    if (this.resolve) {
                        const r = this.resolve
                        this.resolve = undefined
                        r()
                    }
                }
            }
        }
    }

    async connect() {
        const stream = await navigator.mediaDevices.getUserMedia({audio: true})
        return new Promise(resolve => {
            this.resolve = resolve;
            this.ws = new WebSocket("ws://localhost:27016/websocket")
            const handler = async (e: MessageEvent) => {
                this.initConnection(stream)
                const parsed = JSON.parse(e.data)
                if (parsed.event === 'offer') {
                    await this.peer!.setRemoteDescription(JSON.parse(parsed.data))
                    const answer = await this.peer!.createAnswer()
                    await this.peer!.setLocalDescription(answer)
                    this.ws!.send(JSON.stringify({
                        event: 'answer',
                        data: JSON.stringify(answer)
                    }))
                }
                if (parsed.event === 'candidate') {
                    await this.peer!.addIceCandidate(JSON.parse(parsed.data))
                }
            }
            this.ws.addEventListener('message', handler)
        })
    }

    sendto(packet: Packet) {
        if (!this.channel) return
        this.channel.send(packet.data)
    }
}
