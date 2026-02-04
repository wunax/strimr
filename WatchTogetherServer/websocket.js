const WebSocket = require("ws");

const { clients } = require("./state");
const { sendJson } = require("./messaging");
const { nowMs } = require("./sessions");
const logger = require("./logger").child({ module: "websocket" });

function createClient(ws, req) {
  const client = {
    ws,
    isClosed: false,
    lastSeenAt: nowMs(),
    lastPongAt: nowMs(),
    sessionCode: null,
    participantId: null,
    displayName: null,
    plexServerId: null,
    remoteAddress: req.socket?.remoteAddress || null,
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
      } catch (error) {}
    },
  };

  return client;
}

function createWebSocketServer(server, { onMessage, onClose }) {
  const wss = new WebSocket.Server({ server });

  wss.on("connection", (ws, req) => {
    const client = createClient(ws, req);
    clients.add(client);

    logger.info({ remoteAddress: client.remoteAddress }, "WebSocket connected");

    ws.on("message", (data) => {
      client.lastSeenAt = nowMs();

      let message;
      try {
        const text = typeof data === "string" ? data : data.toString("utf8");
        message = JSON.parse(text);
      } catch (error) {
        logger.warn({ err: error, remoteAddress: client.remoteAddress }, "Invalid JSON payload");
        sendJson(client, "error", { message: "Invalid JSON payload.", code: "invalid_json" });
        return;
      }

      if (onMessage) {
        onMessage(client, message);
      }
    });

    ws.on("pong", () => {
      client.lastPongAt = nowMs();
    });

    ws.on("close", () => {
      handleClose(client, onClose, "close");
    });

    ws.on("error", (error) => {
      logger.warn({ err: error, remoteAddress: client.remoteAddress }, "WebSocket error");
      handleClose(client, onClose, "error");
    });
  });

  return wss;
}

function handleClose(client, onClose, reason) {
  if (client.closeNotified) return;
  client.closeNotified = true;
  client.isClosed = true;
  clients.delete(client);
  logger.info({ remoteAddress: client.remoteAddress, reason }, "WebSocket closed");
  if (onClose) {
    onClose(client);
  }
}

module.exports = {
  createWebSocketServer,
};
