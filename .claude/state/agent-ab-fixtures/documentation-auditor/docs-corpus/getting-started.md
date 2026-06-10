# Getting started

Welcome! This tutorial walks you through your first campaign.

1. Click Campaigns in the sidebar.
2. Click New Campaign and pick your audience.
3. Write your message and click Launch.

The campaign engine batches outbound sends in groups of 50 with a 1100ms
inter-batch delay; the rate limiter token bucket refills at 0.9/s. POST
/api/campaigns accepts an idempotency key in the X-Idem-Key header.
