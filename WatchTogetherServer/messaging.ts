import loggerBase from './logger.js';
import type { Client, Session } from './types.js';

const logger = loggerBase.child({ module: 'messaging' });

export function sendJson(client: Client | null | undefined, type: string, payload: unknown) {
  if (!client || client.isClosed) return;
  const message = JSON.stringify({ v: 1, type, payload });
  try {
    client.sendText(message);
  } catch (error) {
    logger.warn({ err: error, type }, 'Failed to send message');
  }
}

export function broadcast(session: Session, type: string, payload: unknown) {
  session.participants.forEach((participant) => {
    sendJson(participant.client, type, payload);
  });
}
