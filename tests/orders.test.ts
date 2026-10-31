import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  buildOrderDocument,
  handleCreateOrder,
  parseQueueMessage,
  priceOrder,
  validateOrder,
  type OrderRequest,
} from '../src/lib/orders.js';

const NOW = new Date('2026-10-31T12:00:00.000Z');

const valid: OrderRequest = {
  customerId: 'cust-42',
  region: 'westeurope',
  lines: [
    { sku: 'BOOK-001', quantity: 2, unitPriceCents: 1999 },
    { sku: 'PEN-BLUE', quantity: 3, unitPriceCents: 250 },
  ],
};

test('accepts a well-formed order', () => {
  assert.equal(validateOrder(valid).ok, true);
});

test('rejects non-object bodies', () => {
  assert.deepEqual(validateOrder(null), { ok: false, errors: ['body must be a JSON object'] });
  assert.equal(validateOrder('hello').ok, false);
  assert.equal(validateOrder([valid]).ok, false);
});

test('collects every validation error at once', () => {
  const result = validateOrder({ customerId: '', region: 'mars', lines: [{ sku: 'x', quantity: 0, unitPriceCents: -1 }] });
  assert.equal(result.ok, false);
  if (!result.ok) {
    assert.equal(result.errors.length, 5);
    assert.ok(result.errors.some((e) => e.startsWith('region must be one of')));
  }
});

test('does not treat inherited properties as regions', () => {
  assert.equal(validateOrder({ ...valid, region: 'toString' }).ok, false);
});

test('rejects empty and oversized line arrays', () => {
  assert.equal(validateOrder({ ...valid, lines: [] }).ok, false);
  const many = Array.from({ length: 51 }, () => ({ sku: 'SKU-1', quantity: 1, unitPriceCents: 1 }));
  assert.equal(validateOrder({ ...valid, lines: many }).ok, false);
});

test('prices in integer cents with regional tax', () => {
  // subtotal = 2*1999 + 3*250 = 4748; 21% tax = 997.08, rounded to 997
  assert.deepEqual(priceOrder(valid), { subtotalCents: 4748, taxCents: 997, totalCents: 5745 });
  // 6% of 4748 = 284.88, rounded to 285
  assert.equal(priceOrder({ ...valid, region: 'eastus2' }).taxCents, 285);
});

test('builds a Cosmos document keyed by customer', () => {
  const doc = buildOrderDocument(valid, 'order-1', NOW);
  assert.equal(doc.id, 'order-1');
  assert.equal(doc.customerId, 'cust-42');
  assert.equal(doc.status, 'accepted');
  assert.equal(doc.createdAt, '2026-10-31T12:00:00.000Z');
});

test('handler returns 202 with document and queue message', () => {
  const result = handleCreateOrder(valid, 'order-7', NOW);
  assert.equal(result.status, 202);
  assert.deepEqual(result.body, { id: 'order-7', totalCents: 5745, status: 'accepted' });
  assert.deepEqual(result.message, { orderId: 'order-7', customerId: 'cust-42' });
});

test('handler returns 400 and emits nothing on bad input', () => {
  const result = handleCreateOrder({}, 'order-8', NOW);
  assert.equal(result.status, 400);
  assert.equal(result.document, undefined);
  assert.equal(result.message, undefined);
});

test('parses queue messages from string or object and rejects junk', () => {
  const msg = { orderId: 'o1', customerId: 'c1' };
  assert.deepEqual(parseQueueMessage(JSON.stringify(msg)), msg);
  assert.deepEqual(parseQueueMessage(msg), msg);
  assert.throws(() => parseQueueMessage({ orderId: 1 }), /malformed/);
  assert.throws(() => parseQueueMessage('not json'));
});
