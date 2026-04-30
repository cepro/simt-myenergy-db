# Shared Ownership Feature Plan

## Overview

Support shared ownership of properties. Shared ownership is between a **corporate body** and an **occupier/shared owner**.

Changes:
- contracts with multiple signatures
- model corporate bodies and corporate body based customers
- clean up modeling of property ownership

## Corporate Bodies

Corporate bodies like Bridport will be added to a new `corporate_bodies` table and customers (corporate body users) at the corporate body to a `customer_corporate_bodies`.

The customers will be linked to the property by `customer_accounts` entries with role='owner'.

Q. How to handle onboarding for these? I think just onboarded out of the box. May require an exception in the customer_status() logic ...


## Database

### Corporate Bodies

#### New `corporate_bodies` Table
Stores organisations that are shared owners.

| Column | Type | Constraints |
|--------|------|-------------|
| id | uuid | PK, DEFAULT `uuid_generate_v4()` |
| name | text | NOT NULL |

**Example row:** `"Bridport Cohousing"`

#### New `customer_corporate_bodies` Table

Joins members of the corporate body (as customers in our `customers` table) to the corporate body.

| Column | Type | Constraints |
|--------|------|-------------|
| customer | uuid | FK → `customers(id)` |
| corporate_body | uuid | FK → `corporate_bodies(id)` |
| | | PK(customer, corporate_body) |

#### Automatic onboarding (?)

`customer_status()` - update - corporate body users automatically onboarded?

### Contracts

#### New `contract_signatures` Table

Joins contracts with signatures.

| Column | Type | Constraints |
|--------|------|-------------|
| contract | uuid | FK → `contracts(id)` |
| customer | uuid | FK → `customers(id)` |
| signed_date | date | |
| | | PK(contract, customer) |

#### Modify `contracts` Table

Drop `signed_date` column
- migrate existing signed_date's to new `contract_signatures` table

New `signed` bool column. Set to true once all required signatures have been collected in `contract_signatures`.

**Signature count trigger**: A DB trigger on `contract_signatures` checks whether all required signatures have been received. The number of required signers could come from an explicit `signatures_required` column on `contracts` (set at creation based on account holders and corporate body owners). Requires spec — the trigger logic, who sets the target count, and how corporate body vs individual signers are counted need clear definition.

### Registered Proprietors

#### New `registered_proprietors` Table

Replaces `property_owners` view. Stores registered proprietors (owners) of properties.

| Column | Type | Constraints |
|--------|------|-------------|
| property | uuid | FK → `properties(id)` |
| customer | uuid | FK → `customers(id)` |
| tenure_type | text | NOT NULL, CHECK (tenure_type IN ('joint_tenant', 'tenant_in_common')) |
| | | PK(property, customer) |

#### Remove `property_owners` View

The `registered_proprietors` table replaces this view. Update any queries that referenced `property_owners` to use `registered_proprietors` JOIN `customers` instead.

## UI Changes

### Workflow

The existing owner workflow (e.g., steffie in WLCE) should work without modification:
- After login shows list of properties owned by the user
- Owner has a single `customer_accounts` role of `'owner'` per property which is how determine owned properties
- Property page shows solar box with contract section and sign button IF a solar account is setup
- Supply section visible with tariff and meter details only (read-only)

### Signing updates

In the old supabase setup we had realtime notifications from supabase to the UI when the contract had been signed. This updated the UI with the new status.

Now we don't yet have a realtime update mechanism so we need something to handle these updates. Whether it's frequent checks / polling or setup a realtime messaging system (see next section).

### Real-time updates via SSE

**SSE (Server-Sent Events)** is a lightweight alternative. The accounts service exposes `GET /contracts/events` using Spring's `SseEmitter`. The Flutter app listens using the `eventsource` package. When a DocuSeal webhook fires and updates `contract_signatures`, the service pushes an event to all connected SSE clients — UI updates immediately without polling.

Example event:
```
event: signature_received
data: {"contractId":"uuid","customerId":"uuid","signedDate":"2026-04-28","submissionId":123}
```

**Effort**: ~1 day across backend and Flutter.

### Orchestrate signing

Attempt to setup the form such that signer A only can sign when they have invoked it. Try do it through the existing embed mechanism - see signing-embed.html. Docs are saying use the API to create a submission first so that may be necessary. Requires a trial.

### Multi Sig Templates

https://www.docuseal.com/resources/add-multiple-signing-parties

- number of signers can not be dynamic
- define a preset number of signers - eg. 2 or 3 (Q. will we need more or just one from corporate body and one from a single co-owner?)
- use Plus button on Template editor to add signers (instead of just adding N signature fields) - not sure what the difference would be but docs showing this as the method
- form.completed event sent to webhook - one per signature
  - update webhook to handle multiple signatures - write to new `contract_signatures` table
