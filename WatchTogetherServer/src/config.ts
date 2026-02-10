import dotenv from 'dotenv';

dotenv.config();

const rawPort = Number.parseInt(process.env.PORT ?? '', 10);
const PORT = Number.isFinite(rawPort) ? rawPort : 8080;
const LOG_LEVEL = process.env.LOG_LEVEL ?? 'info';

function parsePositiveInt(name: string, fallback: number): number {
  const raw = Number.parseInt(process.env[name] ?? '', 10);
  if (Number.isFinite(raw) && raw > 0) {
    return raw;
  }
  return fallback;
}

const PROTOCOL_VERSION = parsePositiveInt('WATCH_TOGETHER_PROTOCOL_VERSION', 1);
const MIN_SUPPORTED_PROTOCOL_VERSION = parsePositiveInt('WATCH_TOGETHER_MIN_PROTOCOL_VERSION', PROTOCOL_VERSION);
const MAX_SUPPORTED_PROTOCOL_VERSION = parsePositiveInt('WATCH_TOGETHER_MAX_PROTOCOL_VERSION', PROTOCOL_VERSION);

export { PORT, LOG_LEVEL, PROTOCOL_VERSION, MIN_SUPPORTED_PROTOCOL_VERSION, MAX_SUPPORTED_PROTOCOL_VERSION };
