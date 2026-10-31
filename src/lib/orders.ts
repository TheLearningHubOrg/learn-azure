// Pure domain logic for the orders sample. No Azure SDK imports live here,
// so every rule can be unit tested without a Functions host or emulator.

export interface OrderLine {
  sku: string;
  quantity: number;
  unitPriceCents: number;
}

export interface OrderRequest {
  customerId: string;
  region: string;
  lines: OrderLine[];
}

export interface OrderDocument {
  id: string;
  // Partition key: orders are always read per customer, so the customer id
  // spreads writes evenly and keeps one customer's history in one logical partition.
  customerId: string;
  region: string;
  lines: OrderLine[];
  subtotalCents: number;
  taxCents: number;
  totalCents: number;
  status: 'accepted' | 'processed';
  createdAt: string;
}

export interface QueueMessage {
  orderId: string;
  customerId: string;
}

export type ValidationResult =
  | { ok: true; value: OrderRequest }
  | { ok: false; errors: string[] };

// Tax rates in basis points (1 bp = 0.01%). Money stays in integer cents
// to avoid floating point rounding drift.
export const TAX_RATES_BP: Record<string, number> = {
  eastus2: 600,
  westeurope: 2100,
  centralindia: 1800,
};

const MAX_LINES = 50;
const MAX_QUANTITY = 1000;
const SKU_PATTERN = /^[A-Z0-9-]{3,32}$/;

function isIntInRange(value: unknown, min: number, max: number): boolean {
  return typeof value === 'number' && Number.isInteger(value) && value >= min && value <= max;
}

export function validateOrder(input: unknown): ValidationResult {
  if (typeof input !== 'object' || input === null || Array.isArray(input)) {
    return { ok: false, errors: ['body must be a JSON object'] };
  }
  const body = input as Record<string, unknown>;
  const errors: string[] = [];

  if (typeof body.customerId !== 'string' || body.customerId.trim() === '') {
    errors.push('customerId is required');
  }
  if (typeof body.region !== 'string' || !Object.hasOwn(TAX_RATES_BP, body.region)) {
    errors.push(`region must be one of: ${Object.keys(TAX_RATES_BP).join(', ')}`);
  }
  if (!Array.isArray(body.lines) || body.lines.length === 0) {
    errors.push('lines must be a non-empty array');
  } else if (body.lines.length > MAX_LINES) {
    errors.push(`an order may contain at most ${MAX_LINES} lines`);
  } else {
    body.lines.forEach((raw, i) => {
      const line = (typeof raw === 'object' && raw !== null ? raw : {}) as Record<string, unknown>;
      if (typeof line.sku !== 'string' || !SKU_PATTERN.test(line.sku)) {
        errors.push(`lines[${i}].sku is invalid`);
      }
      if (!isIntInRange(line.quantity, 1, MAX_QUANTITY)) {
        errors.push(`lines[${i}].quantity must be an integer between 1 and ${MAX_QUANTITY}`);
      }
      if (!isIntInRange(line.unitPriceCents, 0, Number.MAX_SAFE_INTEGER)) {
        errors.push(`lines[${i}].unitPriceCents must be a non-negative integer`);
      }
    });
  }

  if (errors.length > 0) return { ok: false, errors };
  return { ok: true, value: body as unknown as OrderRequest };
}

export function priceOrder(order: OrderRequest): { subtotalCents: number; taxCents: number; totalCents: number } {
  const subtotalCents = order.lines.reduce((sum, l) => sum + l.quantity * l.unitPriceCents, 0);
  const rate = TAX_RATES_BP[order.region] ?? 0;
  const taxCents = Math.round((subtotalCents * rate) / 10_000);
  return { subtotalCents, taxCents, totalCents: subtotalCents + taxCents };
}

export function buildOrderDocument(order: OrderRequest, id: string, now: Date): OrderDocument {
  return {
    id,
    customerId: order.customerId,
    region: order.region,
    lines: order.lines,
    ...priceOrder(order),
    status: 'accepted',
    createdAt: now.toISOString(),
  };
}

export interface HandlerResult {
  status: number;
  body: unknown;
  document?: OrderDocument;
  message?: QueueMessage;
}

// The whole HTTP decision in one testable function. The Functions entry point
// only maps this result onto output bindings.
export function handleCreateOrder(input: unknown, id: string, now: Date): HandlerResult {
  const result = validateOrder(input);
  if (!result.ok) {
    return { status: 400, body: { errors: result.errors } };
  }
  const document = buildOrderDocument(result.value, id, now);
  return {
    status: 202,
    body: { id: document.id, totalCents: document.totalCents, status: document.status },
    document,
    message: { orderId: document.id, customerId: document.customerId },
  };
}

export function parseQueueMessage(raw: unknown): QueueMessage {
  const value: unknown = typeof raw === 'string' ? JSON.parse(raw) : raw;
  const candidate = value as Partial<QueueMessage> | null;
  if (
    typeof candidate !== 'object' || candidate === null ||
    typeof candidate.orderId !== 'string' ||
    typeof candidate.customerId !== 'string'
  ) {
    // Throwing makes the runtime retry. After maxDequeueCount attempts the
    // message moves to the <queue>-poison queue for inspection.
    throw new Error('malformed queue message');
  }
  return { orderId: candidate.orderId, customerId: candidate.customerId };
}
