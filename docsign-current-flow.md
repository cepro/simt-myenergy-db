# Document Signing Flow

## Overview

The system uses **DocuSeal** (a document signing platform) to handle electronic signatures for energy supply contracts and solar contracts. Documents are signed via an embedded web view that loads DocuSeal's signing HTML.

---

## Key Components

### Flutter App (simt-myenergy-app)

| Component | Description |
|-----------|-------------|
| `ContractSigningWidget` | WebView-based widget that embeds DocuSeal signing HTML in the app |
| `SupplyContractSignOrViewModal` / `SolarContractChooseOrViewModal` | Modal dialogs that display contract summary and trigger signing flow |
| `contractSignEmbed()` action | API call that fetches DocuSeal embed HTML from the backend |
| `openSupplyContract()` / `openSolarContract()` | Actions that check signing status and open appropriate modal/PDF |
| `initSupabaseRealtimeSubscriptions` | Listens to PostgreSQL changes on `contracts` table to detect when contracts are signed |
| `contracts` table (Supabase) | Stores contract data including `signed_date`, `signed_contract_url`, `docuseal_submission_id` |

### Accounts Service (simt-j-accountservice)

| Component | Description |
|-----------|-------------|
| `DocusealWebhookController` | Receives `form.completed` webhooks from DocuSeal when signing is done |
| `UIHTMLController` | Serves `/contract/{id}/signing-embed.html` - generates HTML page with DocuSeal embed |
| `signing-embed.html` | Thymeleaf template with DocuSeal form embed code |
| `AccountsService.contractMarkSigned()` | Updates contract in database after DocuSeal webhook fires |
| `Contract` / `ContractTerms` entities | Database entities linking contracts to DocuSeal templates |

---

## Document Signing Flow

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              DOCUMENT SIGNING FLOW                              │
└─────────────────────────────────────────────────────────────────────────────────┘

  ┌──────────┐        ┌──────────────────┐        ┌─────────────────────┐
  │  Flutter  │        │  Accounts Service │        │      DocuSeal       │
  │    App    │        │    (Backend)      │        │   (External API)    │
  └─────┬──────┘        └────────┬─────────┘        └──────────┬──────────┘
        │                        │                             │
        │  1. User taps "View"    │                             │
        │  on contract card      │                             │
        │ ─────────────────────►│                             │
        │                        │                             │
        │                        │  2. GET /contract/{id}/      │
        │                        │     signing-embed.html     │
        │                        │ ──────────────────────────►│
        │                        │                             │
        │                        │  3. Returns HTML with       │
        │                        │    DocuSeal embed code      │
        │                        │ ◄──────────────────────────│
        │                        │                             │
        │  4. HTML loaded in      │                             │
        │  WebView widget        │                             │
        │ ◄─────────────────────│                             │
        │                        │                             │
        │  5. User fills & signs  │                             │
        │  document in DocuSeal  │                             │
        │ ──────────────────────│                             │
        │                        │                             │
        │                        │                             │ 6. DocuSeal sends
        │                        │                             │    webhook to
        │                        │                             │    /docuseal/
        │                        │                             │    webhook/
        │                        │  7. POST webhook received  │    epbiuncmro
        │                        │ ◄──────────────────────────│
        │                        │                             │
        │                        │  8. contractMarkSigned()    │
        │                        │    updates Contract table   │
        │                        │    (signed_date, URL, etc)  │
        │                        │                             │
        │                        │  9. Supabase realtime       │
        │  10. PostgreSQL change │    publishes event         │
        │  detected via          │ ──────────────────────────►│
        │  subscription         │                             │
        │ ◄─────────────────────│                             │
        │                        │                             │
        │  11. FFAppState updated│                             │
        │  (supplyContractSigned │                             │
        │   = true)             │                             │
        │                        │                             │
        │  12. UI refreshes -     │                             │
        │  "View" button now     │                             │
        │  opens signed PDF      │                             │
        └────────────────────────┴─────────────────────────────┘
```

---

## Detailed Step Descriptions

### 1. Initiation (Flutter App)
- User taps "View" on a contract card (supply or solar)
- `openSupplyContract()` or `openSolarContract()` is called
- If contract not signed, shows `SupplyContractSignOrViewModalWidget` dialog

### 2. Embed HTML Request
- User clicks "View" in modal
- `contractSignEmbed()` action calls `GET /contract/{id}/signing-embed.html`
- Backend (`UIHTMLController`) generates HTML with DocuSeal embed code

### 3. DocuSeal Signing (External)
- DocuSeal form renders in `ContractSigningWidget` WebView
- User fills in fields and signs document
- DocuSeal generates combined PDF with audit log

### 4. Webhook Processing (Accounts Service)
- DocuSeal sends `POST /docuseal/webhook/epbiuncmro`
- `DocusealWebhookController.docusealWebhook()` receives the event
- Validates template ID against `ContractTerms`
- Calls `AccountsService.contractMarkSigned()` to update contract

### 5. Real-time Update (Flutter App)
- Supabase realtime subscription detects `contracts` table change
- Updates `solarContractSigned` or `supplyContractSigned` in `FFAppState`
- UI automatically reflects signed status

---

## Key Files Reference

### Flutter App
- `app/lib/custom_code/widgets/contract_signing_widget.dart` - WebView embed
- `app/lib/components/supply_contract_sign_or_view_modal/` - Supply contract modal
- `app/lib/components/solar_contract_choose_or_view_modal/` - Solar contract modal
- `app/lib/actions/actions.dart` - `contractSignEmbed()`, `openSupplyContract()`, `openSolarContract()`
- `app/lib/custom_code/actions/init_supabase_realtime_subscriptions.dart` - Realtime listener

### Accounts Service
- `src/main/java/com/simtricity/accounts/DocusealWebhookController.java` - Webhook endpoint
- `src/main/java/com/simtricity/accounts/UIHTMLController.java` - Embed HTML endpoint
- `src/main/resources/templates/signing-embed.html` - DocuSeal embed template
- `src/main/java/com/simtricity/accounts/AccountsServiceImpl.java` - `contractMarkSigned()` impl
