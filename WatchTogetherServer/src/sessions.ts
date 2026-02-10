import * as crypto from 'crypto';

import { broadcast } from './messaging.js';
import loggerBase from './logger.js';
import { sessions } from './state.js';
import type { Client, LobbySnapshot, Participant, Session } from './types.js';

const logger = loggerBase.child({ module: 'sessions' });

export function nowMs(): number {
  return Date.now();
}

function generateCode(): string {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const length = 6 + Math.floor(Math.random() * 3);
  let code = '';
  for (let i = 0; i < length; i += 1) {
    code += alphabet[Math.floor(Math.random() * alphabet.length)];
  }
  return code;
}

function createSessionCode(): string {
  let code = generateCode();
  let attempts = 0;
  while (sessions.has(code) && attempts < 10) {
    code = generateCode();
    attempts += 1;
  }
  return code;
}

export function createSession({
  plexServerId,
  hostUserId,
  hostName,
  client,
}: {
  plexServerId: string;
  hostUserId: string;
  hostName: string;
  client: Client;
}): Session {
  const code = createSessionCode();
  const session: Session = {
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

export function addParticipant(
  session: Session,
  { userId, displayName, isHost, client }: { userId: string; displayName: string; isHost: boolean; client: Client },
): Participant {
  const participantId = createParticipantId(session, userId);
  const participant: Participant = {
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

export function removeParticipant(session: Session, participantId: string): void {
  session.participants = session.participants.filter((participant) => participant.id !== participantId);
  session.readiness.delete(participantId);
  session.mediaAccess.delete(participantId);
}

export function snapshotFor(session: Session): LobbySnapshot {
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

export function sessionForClient(client: Client): Session | null {
  if (!client.sessionCode || !client.participantId) return null;
  const session = sessions.get(client.sessionCode);
  if (!session) return null;
  return session;
}

export function endSession(session: Session, reason: string): void {
  broadcast(session, 'sessionEnded', { reason });
  session.participants.forEach((participant) => {
    participant.client.sessionCode = null;
    participant.client.participantId = null;
  });
  sessions.delete(session.code);
  logger.info({ code: session.code, reason }, 'Session ended');
}

function createParticipantId(session: Session, userId: string): string {
  let participantId = `${userId}-${crypto.randomBytes(3).toString('hex')}`;
  while (session.participants.some((participant) => participant.id === participantId)) {
    participantId = `${userId}-${crypto.randomBytes(3).toString('hex')}`;
  }
  return participantId;
}
