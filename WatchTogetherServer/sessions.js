const crypto = require("crypto");

const { sessions } = require("./state");
const { broadcast } = require("./messaging");
const logger = require("./logger").child({ module: "sessions" });

function nowMs() {
  return Date.now();
}

function generateCode() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const length = 6 + Math.floor(Math.random() * 3);
  let code = "";
  for (let i = 0; i < length; i += 1) {
    code += alphabet[Math.floor(Math.random() * alphabet.length)];
  }
  return code;
}

function createSessionCode() {
  let code = generateCode();
  let attempts = 0;
  while (sessions.has(code) && attempts < 10) {
    code = generateCode();
    attempts += 1;
  }
  return code;
}

function createSession({ plexServerId, hostUserId, hostName, client }) {
  const code = createSessionCode();
  const session = {
    code,
    plexServerId,
    hostId: null,
    hostUserId,
    participants: [],
    selectedMedia: null,
    readiness: new Map(),
    mediaAccess: new Map(),
    createdAt: nowMs(),
    started: false,
    startAtEpochMs: null,
  };

  const hostParticipant = addParticipant(session, {
    userId: hostUserId,
    displayName: hostName,
    isHost: true,
    client,
  });

  session.hostId = hostParticipant.id;

  sessions.set(code, session);
  return session;
}

function addParticipant(session, { userId, displayName, isHost, client }) {
  const participantId = createParticipantId(session, userId);
  const participant = {
    id: participantId,
    userId,
    displayName,
    isHost,
    isReady: false,
    hasMediaAccess: false,
    client,
  };
  session.participants.push(participant);
  session.readiness.set(participantId, false);
  session.mediaAccess.set(participantId, false);
  return participant;
}

function removeParticipant(session, participantId) {
  session.participants = session.participants.filter((participant) => participant.id !== participantId);
  session.readiness.delete(participantId);
  session.mediaAccess.delete(participantId);
}

function snapshotFor(session) {
  return {
    code: session.code,
    hostId: session.hostId,
    participants: session.participants.map((participant) => ({
      id: participant.id,
      userId: participant.userId,
      displayName: participant.displayName,
      isHost: participant.isHost,
      isReady: session.readiness.get(participant.id) === true,
      hasMediaAccess: session.mediaAccess.get(participant.id) === true,
    })),
    selectedMedia: session.selectedMedia,
    started: session.started,
    startAtEpochMs: session.startAtEpochMs,
  };
}

function sessionForClient(client) {
  if (!client.sessionCode || !client.participantId) return null;
  const session = sessions.get(client.sessionCode);
  if (!session) return null;
  return session;
}

function endSession(session, reason) {
  broadcast(session, "sessionEnded", { reason });
  session.participants.forEach((participant) => {
    if (participant.client) {
      participant.client.sessionCode = null;
      participant.client.participantId = null;
    }
  });
  sessions.delete(session.code);
  logger.info({ code: session.code, reason }, "Session ended");
}

function createParticipantId(session, userId) {
  let participantId = `${userId}-${crypto.randomBytes(3).toString("hex")}`;
  while (session.participants.some((participant) => participant.id === participantId)) {
    participantId = `${userId}-${crypto.randomBytes(3).toString("hex")}`;
  }
  return participantId;
}

module.exports = {
  nowMs,
  createSession,
  addParticipant,
  removeParticipant,
  snapshotFor,
  sessionForClient,
  endSession,
};
