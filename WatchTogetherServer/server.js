const http = require("http");

const { PORT } = require("./config");
const {
  SESSION_TTL_MS,
  CLEANUP_INTERVAL_MS,
  HEARTBEAT_INTERVAL_MS,
  HEARTBEAT_TIMEOUT_MS,
} = require("./constants");
const logger = require("./logger");
const { clients, sessions } = require("./state");
const { createWebSocketServer } = require("./websocket");
const { handleMessage, handleClientDisconnect } = require("./handlers");
const { endSession, nowMs } = require("./sessions");

const server = http.createServer((req, res) => {
  res.writeHead(200, { "Content-Type": "text/plain" });
  res.end("WatchTogetherServer");
});

createWebSocketServer(server, {
  onMessage: handleMessage,
  onClose: handleClientDisconnect,
});

setInterval(() => {
  const now = nowMs();
  for (const session of sessions.values()) {
    if (now - session.createdAt > SESSION_TTL_MS) {
      logger.info({ code: session.code }, "Session expired");
      endSession(session, "Session expired.");
    }
  }
}, CLEANUP_INTERVAL_MS);

setInterval(() => {
  const now = nowMs();
  for (const client of clients) {
    if (now - client.lastPongAt > HEARTBEAT_TIMEOUT_MS) {
      logger.info({ remoteAddress: client.remoteAddress }, "Heartbeat timeout; closing socket");
      client.close();
      continue;
    }

    client.sendPing();
  }
}, HEARTBEAT_INTERVAL_MS);

server.listen(PORT, () => {
  logger.info({ port: PORT, logLevel: logger.level }, "WatchTogetherServer listening");
});
