const { sessions } = require("./state");
const {
  createSession,
  addParticipant,
  removeParticipant,
  snapshotFor,
  sessionForClient,
  endSession,
  nowMs,
} = require("./sessions");
const { sendJson, broadcast } = require("./messaging");
const logger = require("./logger").child({ module: "handlers" });

function handleMessage(client, message) {
  if (!message || message.v !== 1 || !message.type) {
    logger.warn({ messageType: message?.type }, "Unsupported protocol version");
    sendJson(client, "error", { message: "Unsupported protocol version.", code: "bad_version" });
    return;
  }

  switch (message.type) {
    case "createSession":
      handleCreateSession(client, message.payload || {});
      break;
    case "joinSession":
      handleJoinSession(client, message.payload || {});
      break;
    case "leaveSession":
      handleLeaveSession(client, message.payload || {});
      break;
    case "setReady":
      handleSetReady(client, message.payload || {});
      break;
    case "setSelectedMedia":
      handleSetSelectedMedia(client, message.payload || {});
      break;
    case "mediaAccess":
      handleMediaAccess(client, message.payload || {});
      break;
    case "startPlayback":
      handleStartPlayback(client, message.payload || {});
      break;
    case "stopPlayback":
      handleStopPlayback(client, message.payload || {});
      break;
    case "playerEvent":
      handlePlayerEvent(client, message.payload || {});
      break;
    case "ping":
      handlePing(client, message.payload || {});
      break;
    default:
      logger.warn({ messageType: message.type }, "Unknown message type");
      sendJson(client, "error", { message: "Unknown message type.", code: "unknown_type" });
  }
}

function handleCreateSession(client, payload) {
  const { plexServerId, participantId: userId, displayName } = payload;
  if (!plexServerId || !userId || !displayName) {
    sendJson(client, "error", { message: "Missing identity payload.", code: "missing_identity" });
    return;
  }

  const session = createSession({
    plexServerId,
    hostUserId: userId,
    hostName: displayName,
    client,
  });

  const participantId = session.hostId;

  client.sessionCode = session.code;
  client.participantId = participantId;
  client.userId = userId;
  client.displayName = displayName;
  client.plexServerId = plexServerId;

  logger.info({ code: session.code, hostId: session.hostId, plexServerId, userId }, "Session created");

  sendJson(client, "created", { code: session.code, hostId: session.hostId, participantId });
  broadcast(session, "lobbySnapshot", snapshotFor(session));
}

function handleJoinSession(client, payload) {
  const { code, plexServerId, participantId: userId, displayName } = payload;
  if (!code || !plexServerId || !userId || !displayName) {
    sendJson(client, "error", { message: "Missing identity payload.", code: "missing_identity" });
    return;
  }

  const session = sessions.get(code);
  if (!session) {
    sendJson(client, "error", { message: "Session not found.", code: "not_found" });
    return;
  }

  if (session.plexServerId !== plexServerId) {
    sendJson(client, "error", { message: "Server mismatch.", code: "server_mismatch" });
    return;
  }

  const hasHost = session.participants.some((participant) => participant.isHost);
  const shouldBeHost = session.hostUserId === userId && !hasHost;
  const participant = addParticipant(session, {
    userId,
    displayName,
    isHost: shouldBeHost,
    client,
  });

  if (shouldBeHost) {
    session.hostId = participant.id;
  }

  client.sessionCode = session.code;
  client.participantId = participant.id;
  client.userId = userId;
  client.displayName = displayName;
  client.plexServerId = plexServerId;

  logger.info({ code: session.code, participantId: participant.id, userId }, "Participant joined");

  sendJson(client, "joined", { code: session.code, hostId: session.hostId, participantId: participant.id });
  broadcast(session, "lobbySnapshot", snapshotFor(session));
}

function handleLeaveSession(client, payload) {
  if (!client.sessionCode || !client.participantId) return;
  const session = sessions.get(client.sessionCode);
  if (!session) return;

  const isHost = session.hostId === client.participantId;
  const endForAll = payload.endForAll === true;
  const participantId = client.participantId;

  removeParticipant(session, client.participantId);
  client.sessionCode = null;
  client.participantId = null;

  logger.info(
    { code: session.code, participantId, endForAll, isHost },
    "Participant left"
  );

  if (endForAll) {
    endSession(session, "Session ended by host.");
    return;
  }

  if (session.participants.length === 0) {
    sessions.delete(session.code);
    return;
  }

  if (isHost) {
    assignNewHost(session);
  }

  broadcast(session, "lobbySnapshot", snapshotFor(session));
}

function handleSetReady(client, payload) {
  const session = sessionForClient(client);
  if (!session) return;
  session.readiness.set(client.participantId, payload.isReady === true);
  logger.debug({ code: session.code, participantId: client.participantId }, "Participant readiness updated");
  broadcast(session, "lobbySnapshot", snapshotFor(session));
}

function handleSetSelectedMedia(client, payload) {
  const session = sessionForClient(client);
  if (!session) return;

  if (session.hostId !== client.participantId) {
    sendJson(client, "error", { message: "Host only action.", code: "forbidden" });
    return;
  }

  if (!payload.media) {
    return;
  }

  session.selectedMedia = payload.media;
  session.started = false;
  session.startAtEpochMs = null;
  session.mediaAccess = new Map();
  session.participants.forEach((participant) => {
    session.mediaAccess.set(participant.id, false);
  });

  logger.info({ code: session.code, hostId: session.hostId }, "Selected media updated");

  broadcast(session, "lobbySnapshot", snapshotFor(session));
}

function handleMediaAccess(client, payload) {
  const session = sessionForClient(client);
  if (!session) return;
  session.mediaAccess.set(client.participantId, payload.hasAccess === true);
  logger.debug({ code: session.code, participantId: client.participantId }, "Media access updated");
  broadcast(session, "lobbySnapshot", snapshotFor(session));
}

function handleStartPlayback(client, payload) {
  const session = sessionForClient(client);
  if (!session) return;

  if (session.hostId !== client.participantId) {
    sendJson(client, "error", { message: "Host only action.", code: "forbidden" });
    return;
  }

  if (!payload.ratingKey || !payload.type) {
    return;
  }

  session.started = true;
  session.startAtEpochMs = nowMs() + 2000;

  const startPayload = {
    ratingKey: payload.ratingKey,
    type: payload.type,
    startAtEpochMs: session.startAtEpochMs,
  };

  logger.info({ code: session.code, startAtEpochMs: session.startAtEpochMs }, "Playback started");

  broadcast(session, "startPlayback", startPayload);
  broadcast(session, "lobbySnapshot", snapshotFor(session));
}

function handleStopPlayback(client, payload) {
  const session = sessionForClient(client);
  if (!session) return;

  if (session.hostId !== client.participantId) {
    sendJson(client, "error", { message: "Host only action.", code: "forbidden" });
    return;
  }

  session.started = false;
  session.startAtEpochMs = null;

  broadcast(session, "playbackStopped", { reason: payload.reason || null });
  broadcast(session, "lobbySnapshot", snapshotFor(session));
}

function handlePlayerEvent(client, payload) {
  const session = sessionForClient(client);
  if (!session) return;
  if (!session.started) return;

  if (!payload.event) return;

  const event = {
    ...payload.event,
    senderId: client.participantId,
    serverReceivedAtMs: nowMs(),
  };

  logger.debug({ code: session.code, eventType: payload.event.type }, "Player event received");

  broadcast(session, "playerEvent", event);
}

function handlePing(client, payload) {
  sendJson(client, "pong", {
    sentAtMs: payload.sentAtMs || 0,
    receivedAtMs: nowMs(),
  });
}

function handleClientDisconnect(client) {
  if (!client.sessionCode || !client.participantId) return;
  const session = sessions.get(client.sessionCode);
  if (!session) return;

  const isHost = session.hostId === client.participantId;
  const participantId = client.participantId;

  removeParticipant(session, participantId);

  if (session.participants.length === 0) {
    logger.info({ code: session.code }, "Session empty after disconnect; removing");
    sessions.delete(session.code);
    return;
  }

  if (isHost) {
    logger.info({ code: session.code, participantId }, "Host disconnected; reassigning host");
    assignNewHost(session);
  }

  logger.info({ code: session.code, participantId }, "Participant disconnected");
  broadcast(session, "lobbySnapshot", snapshotFor(session));
}

function assignNewHost(session) {
  session.participants.forEach((participant) => {
    participant.isHost = false;
  });

  const nextHost = session.participants[0];
  if (!nextHost) return;

  nextHost.isHost = true;
  session.hostId = nextHost.id;
  session.hostUserId = nextHost.userId;
}

module.exports = {
  handleMessage,
  handleClientDisconnect,
};
