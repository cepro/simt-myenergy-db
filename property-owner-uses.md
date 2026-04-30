# properties.owner Column Usage Analysis

This document tracks all uses of the `properties.owner` column to assess impact when introducing shared ownership via `customer_accounts.role = 'owner'`.

---

## 1. Structural References (No Logic Impact)

| Object | File:Line | Purpose |
|--------|-----------|---------|
| Index | `0000_initial.sql:3905` | `properties_owner_idx` - btree index on `owner` |
| Foreign Key | `0000_initial.sql:4220` | `properties_owner_fkey` - FK referencing `customers(id)` |

---

## 2. Functions That Directly Use `p.owner`

### 2.1 `properties_owned()` - **HIGH IMPACT**

```sql
CREATE FUNCTION myenergy.properties_owned() RETURNS uuid[]
  SELECT array_agg(p.id)::uuid[]
  FROM myenergy.properties p
  WHERE p.owner = myenergy.customer()
```

**Call Sites:**
- `0000_initial.sql:4408` - RLS policy on `customers` table
- `0003_postgraphile.sql:119` - RLS policy on `customers` table

**Used In RLS Policies:**
```sql
-- customers policy
OR (id = ANY (myenergy.properties_owned()))
```

**Impact:** With shared ownership, a user may be an owner via `customer_accounts` without being the single `properties.owner`. This function will miss properties where the user has `role='owner'` but is not the primary owner.

---

### 2.2 `get_property_owners_for_auth_user(email_in text)` - **HIGH IMPACT**

```sql
CREATE FUNCTION myenergy.get_property_owners_for_auth_user(email_in text) RETURNS SETOF uuid
  RETURN QUERY
  SELECT DISTINCT p.owner
  FROM myenergy.properties p
  JOIN myenergy.accounts a ON a.property = p.id
  JOIN myenergy.customer_accounts ca ON ca.account = a.id
  JOIN myenergy.customers c ON ca.customer = c.id
  WHERE c.email = email_in
```

**Call Sites:**
- `0000_initial.sql:4304` - RLS policy on `customers` table
- `0003_postgraphile.sql:109` - RLS policy on `customers` table
- `0004_postgraphile2.sql:287` - RLS policy on `customers` table
- `0004_postgraphile2.sql:295` - RLS policy on `customers` table

**Impact:** Same issue - only returns the single `properties.owner`, missing co-owners.

---

### 2.3 `update_property_tenure()` - **CRITICAL IMPACT**

```sql
CREATE FUNCTION myenergy.update_property_tenure() RETURNS trigger
  -- Determines tenure based on whether owner != occupier
  IF EXISTS (
    SELECT 1 FROM myenergy.accounts a
    JOIN myenergy.customer_accounts ca ON ca.account = a.id
    WHERE a.property = p.id
    AND ca.role = 'occupier'
    AND ca.customer != p.owner  -- <-- Problem: p.owner is single value
  ) THEN 'separate_owner_and_occupier'
  ELSE 'single_owner_occupier'
```

**Trigger Call Sites:**
| Trigger | Table | Event |
|---------|-------|-------|
| `update_property_tenure_accounts` | `accounts` | AFTER INSERT, DELETE, UPDATE |
| `update_property_tenure_customer_accounts` | `customer_accounts` | AFTER INSERT, DELETE, UPDATE |
| `update_property_tenure_properties` | `properties` | AFTER UPDATE OF owner |

**Impact:** With multiple owners, there is no single `p.owner` to compare. The tenure logic needs to check if ANY owner differs from ANY occupier, not just the primary owner.

---

### 2.4 `change_property_owner(property_id, new_owner)` - **MEDIUM IMPACT**

```sql
UPDATE myenergy.properties
SET owner = new_owner
WHERE id = property_id;

UPDATE myenergy.customer_accounts
SET customer = new_owner
WHERE account IN (SELECT id FROM accounts WHERE property = property_id)
AND role = 'owner';
```

**Call Sites:**
- `0000_initial.sql:4686-4688` - GRANT statements (function is exposed to anon/auth/service_role)

**Impact:** Updates the single `owner` column and reassigns all `owner` roles in `customer_accounts`. With shared ownership, this may need to handle adding a new owner rather than replacing all owners.

---

### 2.5 `add_property()` - Sets `owner` on Insert

This function creates a new property with a single owner. With shared ownership, this may need to be extended to handle initial co-ownership setup.

---

## 3. Functions That Use `customer_accounts.role = 'owner'` (SAFE)

The following use the `customer_accounts` join with `role = 'owner'` and do NOT directly use `properties.owner`:

| Function/View | File:Line |
|---------------|-----------|
| `property_solar_view` | `0000_initial.sql:3393` |
| `property_supply_view` | `0000_initial.sql:3438` |
| `add_account()` | `0000_initial.sql:606, 621` |

---

## 4. Summary Table

| Reference | Type | Shared Ownership Risk |
|-----------|------|---------------------|
| `properties_owner_idx` | Index | None |
| `properties_owner_fkey` | FK | Low - constraint only |
| `properties_owned()` | Function | **HIGH** - RLS policy |
| `get_property_owners_for_auth_user()` | Function | **HIGH** - RLS policy |
| `update_property_tenure()` | Function/Trigger | **CRITICAL** - tenure logic |
| `change_property_owner()` | Function | **MEDIUM** - ownership transfer |
| `add_property()` | Function | **MEDIUM** - property creation |
| Views (solar/supply) | Views | **None** - use `customer_accounts` |

---

## 5. Recommendations

1. **`update_property_tenure()`** - Must be redesigned to check if ANY owner differs from ANY occupier using `customer_accounts` join rather than `properties.owner`

2. **`properties_owned()`** - Should be updated to also include properties where the user has `role='owner'` in `customer_accounts`:
   ```sql
   WHERE p.owner = myenergy.customer()
   OR EXISTS (
     SELECT 1 FROM myenergy.accounts a
     JOIN myenergy.customer_accounts ca ON ca.account = a.id
     WHERE a.property = p.id AND ca.customer = myenergy.customer() AND ca.role = 'owner'
   )
   ```

3. **`get_property_owners_for_auth_user()`** - Should return all customers who have `role='owner'` for the property, not just the primary owner

4. **`change_property_owner()`** - Consider whether this should add an owner rather than replace the primary owner in shared ownership scenarios
