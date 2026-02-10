import type WebSocket from 'ws';

export type MessagePayload = Record<string, unknown>;

export type ProtocolMessage = {
  v?: number;
  type?: string;
  payload?: MessagePayload;
};

export interface Client {
  ws: WebSocket;
  isClosed: boolean;
  lastSeenAt: number;
  lastPongAt: number;
  sessionCode: string | null;
  participantId: string | null;
  userId: string | null;
  displayName: string | null;
  plexServerId: string | null;
  remoteAddress: string | null;
  closeNotified: boolean;
  sendText(text: string): void;
  sendPing(): void;
  close(): void;
}

export interface Participant {
  id: string;
  userId: string;
  displayName: string;
  isHost: boolean;
  isReady: boolean;
  hasMediaAccess: boolean;
  client: Client;
}

export type SelectedMedia = Record<string, unknown>;

export interface LobbySnapshot {
  code: string;
  hostId: string | null;
  participants: Array<{
    id: string;
    userId: string;
    displayName: string;
    isHost: boolean;
    isReady: boolean;
    hasMediaAccess: boolean;
  }>;
  selectedMedia: SelectedMedia | null;
  started: boolean;
  startAtEpochMs: number | null;
}

export interface Session {
  code: string;
  plexServerId: string;
  hostId: string | null;
  hostUserId: string;
  participants: Participant[];
  selectedMedia: SelectedMedia | null;
  readiness: Map<string, boolean>;
  mediaAccess: Map<string, boolean>;
  createdAt: number;
  started: boolean;
  startAtEpochMs: number | null;
}

export type OnMessage = (client: Client, message: ProtocolMessage) => void;
export type OnClose = (client: Client) => void;
