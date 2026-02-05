import * as http from "http";

import { PORT } from "./config.js";
import {
  CLEANUP_INTERVAL_MS,
  HEARTBEAT_INTERVAL_MS,
  HEARTBEAT_TIMEOUT_MS,
  SESSION_TTL_MS,
} from "./constants.js";
import { handleClientDisconnect, handleMessage } from "./handlers.js";
import logger from "./logger.js";
import { endSession, nowMs } from "./sessions.js";
import { clients, sessions } from "./state.js";
import { createWebSocketServer } from "./websocket.js";

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
