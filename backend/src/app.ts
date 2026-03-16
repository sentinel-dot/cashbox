import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import dotenv from 'dotenv';
import pinoHttp from 'pino-http';
import { apiRateLimit } from './middleware/rateLimitMiddleware.js';
import { logger } from './logger.js';

dotenv.config();

const app = express();

// Request-Logging (alle Requests: Methode, URL, Status, Dauer, tenant_id aus JWT)
app.use(pinoHttp({
  logger,
  // Gesundheits-Check nicht loggen (zu viel Rauschen)
  autoLogging: { ignore: (req) => req.url === '/health' },
  customLogLevel: (_req, res) => res.statusCode >= 500 ? 'error' : res.statusCode >= 400 ? 'warn' : 'info',
  serializers: {
    req: (req) => ({
      method: req.method,
      url:    req.url,
      // tenant_id aus JWT wenn vorhanden (gesetzt von tenantMiddleware)
      tenant: (req.raw as any).auth?.tenantId,
    }),
    res: (res) => ({ status: res.statusCode }),
  },
}));

// Security headers
app.use(helmet());

// CORS — nur eigene App in Prod
app.use(cors({
  origin: process.env['NODE_ENV'] === 'production'
    ? process.env['ALLOWED_ORIGIN'] ?? false
    : true,
  credentials: true,
}));

// Stripe Webhook braucht raw body — muss VOR express.json() registriert werden
app.use('/webhooks/stripe', express.raw({ type: 'application/json' }));

// JSON body parsing für alle anderen Routen
app.use(express.json());

// Global rate limit
app.use(apiRateLimit);

// Health check (kein Auth nötig)
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Routes
import authRouter           from './routes/auth.js';
import onboardingRouter     from './routes/onboarding.js';
import webhooksRouter       from './routes/webhooks.js';
import usersRouter          from './routes/users.js';
import devicesRouter        from './routes/devices.js';
import productsRouter       from './routes/products.js';
import modifierGroupsRouter from './routes/modifierGroups.js';
import tablesRouter         from './routes/tables.js';
import sessionsRouter       from './routes/sessions.js';
import ordersRouter         from './routes/orders.js';
import receiptsRouter       from './routes/receipts.js';
import tenantsRouter        from './routes/tenants.js';
import syncRouter           from './routes/sync.js';
import reportsRouter        from './routes/reports.js';
import exportRouter         from './routes/export.js';
app.use('/auth',            authRouter);
app.use('/onboarding',      onboardingRouter);
app.use('/webhooks',        webhooksRouter);
app.use('/users',           usersRouter);
app.use('/devices',         devicesRouter);
app.use('/products',        productsRouter);
app.use('/modifier-groups', modifierGroupsRouter);
app.use('/tables',          tablesRouter);
app.use('/sessions',        sessionsRouter);
app.use('/orders',          ordersRouter);
app.use('/receipts',        receiptsRouter);
app.use('/tenants',         tenantsRouter);
app.use('/sync',            syncRouter);
app.use('/reports',         reportsRouter);
app.use('/export',          exportRouter);

// Globaler Error Handler — muss als letztes registriert werden
// Express 5 leitet abgelehnte Promises automatisch hierher weiter
app.use((err: any, req: any, res: any, _next: any) => {
  const status = err.status ?? err.statusCode ?? 500;
  if (status >= 500) {
    logger.error({ err, url: req.url, method: req.method, tenant: req.auth?.tenantId }, 'Unhandled error');
  }
  // Kein Stack Trace in Produktion
  res.status(status).json({
    error: process.env['NODE_ENV'] === 'production'
      ? 'Interner Serverfehler.'
      : (err.message ?? 'Interner Serverfehler.'),
  });
});

export default app;
