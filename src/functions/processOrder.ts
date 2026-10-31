import { app, InvocationContext } from '@azure/functions';
import { parseQueueMessage } from '../lib/orders.js';

// Queue-triggered worker. The HTTP function returns 202 at once and this
// function does the slow part (payment, fulfilment, e-mail) out of band.
export async function processOrder(queueItem: unknown, context: InvocationContext): Promise<void> {
  const message = parseQueueMessage(queueItem);
  const attempt = context.triggerMetadata?.dequeueCount ?? 1;
  context.log(`processing order ${message.orderId} (attempt ${attempt})`);
  // Real work goes here. It must be idempotent: the same message can arrive twice.
}

app.storageQueue('processOrder', {
  queueName: '%ORDERS_QUEUE%',
  connection: 'AzureWebJobsStorage',
  handler: processOrder,
});
