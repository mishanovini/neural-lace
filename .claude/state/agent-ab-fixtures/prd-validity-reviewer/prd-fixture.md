# PRD: Acme Field Services scheduling assistant (FIXTURE)

## Problem
The problem is that we lack an AI-powered scheduling dashboard. Without a
dashboard, the team cannot see the schedule in one place, so we need to build one
with smart suggestions.

## Scenarios
- As a user, I want to manage my data so that I can be more productive.
- As an admin, I want to configure settings so the system works the way I want.
- A dispatcher opens the app and sees useful information about upcoming work.

## Functional requirements
- FR1. The system shows a schedule view.
- FR2. The system suggests the best technician for a job using AI.
- FR3. Admins can configure working hours per technician.

## Non-functional requirements
- NFR1. The app must be fast and responsive.
- NFR2. The schedule view must load in under 2 seconds at the 95th percentile for
  orgs with up to 50 technicians.

## Success metrics
- Users love the scheduling experience.
- Engagement increases significantly.
- Double-booking incidents drop from the current baseline of ~6/month to <=1/month
  within 90 days of launch.

## Out-of-scope
- Payroll. Route optimization. Customer-facing booking.

## Open questions
- Should suggestions consider technician skill tags in v1?
