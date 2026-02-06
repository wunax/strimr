import type { Client, Session } from './types.js';

export const sessions = new Map<string, Session>();
export const clients = new Set<Client>();
