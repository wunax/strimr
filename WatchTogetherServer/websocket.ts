import type { IncomingMessage, Server } from 'http';

import WebSocket, { WebSocketServer } from 'ws';

import { sendJson } from './messaging.js';
import loggerBase from './logger.js';
import { nowMs } from './sessions.js';
import { clients } from './state.js';
import type { Client, OnClose, OnMessage, ProtocolMessage } from './types.js';

const logger = loggerBase.child({ module: 'websocket' });

function rawDataToString(data: WebSocket.RawData): string {
  if (typeof data === 'string') return data;
  if (Buffer.isBuffer(data)) return data.toString('utf8');
  if (Array.isArray(data)) return Buffer.concat(data).toString('utf8');
  if (data instanceof ArrayBuffer) {
    return Buffer.from(new Uint8Array(data)).toString('utf8');
  }
  return Buffer.from(data as Uint8Array).toString('utf8');
}

function createClient(ws: WebSocket, req: IncomingMessage): Client {
  const client: Client = {
    ws,
    isClosed: false,
    lastSeenAt: nowMs(),
    lastPongAt: nowMs(),
    sessionCode: null,
    participantId: null,
    userId: null,
    displayName: null,
    plexServerId: null,
    remoteAddress: req.socket?.remoteAddress ?? null,
    closeNotified: false,
    sendText(text) {
      if (this.isClosed || this.ws.readyState !== WebSocket.OPEN) return;
      this.ws.send(text);
    },
    sendPing() {
      if (this.isClosed || this.ws.readyState !== WebSocket.OPEN) return;
      this.ws.ping();
    },
    close() {
      if (this.isClosed) return;
      this.isClosed = true;
      try {
        this.ws.close();
      } catch {
        // Ignore close errors; connection is already closing.
      }
    },
  };

  return client;
}

export function createWebSocketServer(
  server: Server,
  { onMessage, onClose }: { onMessage?: OnMessage; onClose?: OnClose },
): WebSocketServer {
  const wss = new WebSocketServer({ server });

  wss.on('connection', (ws: WebSocket, req: IncomingMessage) => {
    const client = createClient(ws, req);
    clients.add(client);

    logger.info({ remoteAddress: client.remoteAddress }, 'WebSocket connected');

    ws.on('message', (data: WebSocket.RawData) => {
      client.lastSeenAt = nowMs();

      let message: ProtocolMessage;
      try {
        const text = rawDataToString(data);
        message = JSON.parse(text) as ProtocolMessage;
      } catch (error) {
        logger.warn({ err: error, remoteAddress: client.remoteAddress }, 'Invalid JSON payload');
        sendJson(client, 'error', { message: 'Invalid JSON payload.', code: 'invalid_json' });
        return;
      }

      if (onMessage) {
        onMessage(client, message);
      }
    });

    ws.on('pong', () => {
      client.lastPongAt = nowMs();
    });

    ws.on('close', () => {
      handleClose(client, onClose, 'close');
    });

    ws.on('error', (error) => {
      logger.warn({ err: error, remoteAddress: client.remoteAddress }, 'WebSocket error');
      handleClose(client, onClose, 'error');
    });
  });

  return wss;
}

function handleClose(client: Client, onClose: OnClose | undefined, reason: 'close' | 'error') {
  if (client.closeNotified) return;
  client.closeNotified = true;
  client.isClosed = true;
  clients.delete(client);
  logger.info({ remoteAddress: client.remoteAddress, reason }, 'WebSocket closed');
  if (onClose) {
    onClose(client);
  }
}
