const logger = require("./logger").child({ module: "messaging" });

function sendJson(client, type, payload) {
  if (!client || client.isClosed) return;
  const message = JSON.stringify({ v: 1, type, payload });
  try {
    client.sendText(message);
  } catch (error) {
    logger.warn({ err: error, type }, "Failed to send message");
  }
}

function broadcast(session, type, payload) {
  session.participants.forEach((participant) => {
    sendJson(participant.client, type, payload);
  });
}

module.exports = {
  sendJson,
  broadcast,
};
