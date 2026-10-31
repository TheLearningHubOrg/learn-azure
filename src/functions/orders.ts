import { randomUUID } from 'node:crypto';
import { app, HttpRequest, HttpResponseInit, InvocationContext, output } from '@azure/functions';
import { handleCreateOrder } from '../lib/orders.js';

// Output bindings: the host writes these after the handler returns.
// Both use identity-based connections (settings with a __ suffix), so no keys are stored.
const cosmosOut = output.cosmosDB({
  databaseName: '%COSMOS_DATABASE%',
  containerName: '%COSMOS_CONTAINER%',
  connection: 'COSMOS',
  createIfNotExists: false,
});

const queueOut = output.storageQueue({
  queueName: '%ORDERS_QUEUE%',
  connection: 'AzureWebJobsStorage',
});

export async function createOrder(request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return { status: 400, jsonBody: { errors: ['body must be valid JSON'] } };
  }

  const result = handleCreateOrder(body, randomUUID(), new Date());
  if (result.document && result.message) {
    context.extraOutputs.set(cosmosOut, result.document);
    context.extraOutputs.set(queueOut, result.message);
    context.log(`accepted order ${result.document.id} for ${result.document.customerId}`);
  }
  return { status: result.status, jsonBody: result.body };
}

app.http('createOrder', {
  methods: ['POST'],
  route: 'orders',
  authLevel: 'function',
  extraOutputs: [cosmosOut, queueOut],
  handler: createOrder,
});

app.http('health', {
  methods: ['GET'],
  route: 'health',
  authLevel: 'anonymous',
  handler: async () => ({ status: 200, jsonBody: { status: 'ok' } }),
});
