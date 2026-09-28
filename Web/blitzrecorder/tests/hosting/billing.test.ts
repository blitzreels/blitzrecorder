import test from "node:test";
import assert from "node:assert/strict";
import type Stripe from "stripe";
import { paidHostingPeriod } from "../../lib/hosting/billing";

test("only an active, paid subscription to the hosting price grants storage", () => {
  const period = Math.floor(Date.now() / 1000) + 86400;
  const subscription = {
    status: "active", pause_collection: null, latest_invoice: { status: "paid" },
    items: { data: [{ price: { id: "hosting-price" }, current_period_end: period }] },
  } as unknown as Stripe.Subscription;
  assert.equal(paidHostingPeriod({ subscription, priceID: "hosting-price" }), period);
  assert.equal(paidHostingPeriod({ subscription, priceID: "app-license-price" }), null);
  for (const status of ["trialing", "past_due", "canceled", "unpaid", "incomplete", "paused"] as const) {
    assert.equal(paidHostingPeriod({ subscription: { ...subscription, status }, priceID: "hosting-price" }), null);
  }
  for (const latest_invoice of [null, "unexpanded-invoice", { status: "open" }, { status: "void" }]) {
    assert.equal(paidHostingPeriod({ subscription: { ...subscription, latest_invoice } as Stripe.Subscription, priceID: "hosting-price" }), null);
  }
});
