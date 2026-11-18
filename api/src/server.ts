import { createApp } from './app';
import { prisma } from './db';
import { env } from './env';

const server = createApp().listen(env.port, () => {
  console.log(`SewWallet API ouvindo na porta ${env.port}`);
});

const shutdown = () => {
  server.close(() => {
    void prisma.$disconnect().finally(() => process.exit(0));
  });
};
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
