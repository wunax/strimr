import pino from 'pino';

import { LOG_LEVEL } from './config.js';

const logger = pino({
  level: LOG_LEVEL,
  base: { service: 'watch-together-server' },
  timestamp: pino.stdTimeFunctions.isoTime,
});

export default logger;
