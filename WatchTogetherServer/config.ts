import dotenv from 'dotenv';

dotenv.config();

const rawPort = Number.parseInt(process.env.PORT ?? '', 10);
const PORT = Number.isFinite(rawPort) ? rawPort : 8080;
const LOG_LEVEL = process.env.LOG_LEVEL ?? 'info';

export { PORT, LOG_LEVEL };
