# Sakila Data Dictionary

Source: `sakila-schema.sql` (Sakila 1.5, MySQL). Line numbers refer to that file. The schema has 16 base tables; the views, procedures, functions and triggers are not documented here.

## 1. Base tables

| Table | Primary key | Foreign keys (column → referenced table.column) | One row = |
|---|---|---|---|
| `actor` | `actor_id` | none | One actor (person). |
| `address` | `address_id` | `city_id` → `city.city_id` (`fk_address_city`) | One street address with phone and postal code. Shared by customers, staff and stores. |
| `category` | `category_id` | none | One film genre (e.g. Action, Comedy). |
| `city` | `city_id` | `country_id` → `country.country_id` (`fk_city_country`) | One city, belonging to one country. |
| `country` | `country_id` | none | One country. |
| `customer` | `customer_id` | `store_id` → `store.store_id` (`fk_customer_store`); `address_id` → `address.address_id` (`fk_customer_address`) | One registered customer, tied to a home store. |
| `film` | `film_id` | `language_id` → `language.language_id` (`fk_film_language`); `original_language_id` → `language.language_id` (`fk_film_language_original`) | One film title (the catalog entry, not a physical copy). |
| `film_actor` | `(actor_id, film_id)` | `actor_id` → `actor.actor_id` (`fk_film_actor_actor`); `film_id` → `film.film_id` (`fk_film_actor_film`) | One actor appearing in one film (bridge table). |
| `film_category` | `(film_id, category_id)` | `film_id` → `film.film_id` (`fk_film_category_film`); `category_id` → `category.category_id` (`fk_film_category_category`) | One film assigned to one category (bridge table). |
| `film_text` | `film_id` | none (no FK constraint; kept in sync with `film` by triggers `ins_film`, `upd_film`, `del_film`) | Searchable copy of one film's title and description (FULLTEXT index). |
| `inventory` | `inventory_id` | `film_id` → `film.film_id` (`fk_inventory_film`); `store_id` → `store.store_id` (`fk_inventory_store`) | One physical copy of a film held at one store. |
| `language` | `language_id` | none | One spoken language (e.g. English). |
| `payment` | `payment_id` | `rental_id` → `rental.rental_id` (`fk_payment_rental`, nullable, `ON DELETE SET NULL`); `customer_id` → `customer.customer_id` (`fk_payment_customer`); `staff_id` → `staff.staff_id` (`fk_payment_staff`) | One payment made by a customer and taken by a staff member, usually for one rental. |
| `rental` | `rental_id` | `inventory_id` → `inventory.inventory_id` (`fk_rental_inventory`); `customer_id` → `customer.customer_id` (`fk_rental_customer`); `staff_id` → `staff.staff_id` (`fk_rental_staff`) | One customer renting one inventory copy at a point in time; `return_date` is NULL while still out. |
| `staff` | `staff_id` | `store_id` → `store.store_id` (`fk_staff_store`); `address_id` → `address.address_id` (`fk_staff_address`) | One employee, assigned to a store. |
| `store` | `store_id` | `manager_staff_id` → `staff.staff_id` (`fk_store_staff`); `address_id` → `address.address_id` (`fk_store_address`) | One rental store, with one manager (unique per store). |

Things to watch:

- `film` has two FKs to `language`: `language_id` is the film's language, `original_language_id` is optional (nullable).
- `store` and `staff` reference each other (`fk_store_staff` and `fk_staff_store`). The script disables `FOREIGN_KEY_CHECKS` (line 33) so the tables can load.
- `payment.rental_id` is nullable, so some payments may have no rental. Joins from `payment` to `rental` should consider a LEFT JOIN.
- `rental` has a unique key on `(rental_date, inventory_id, customer_id)`.
- Every table has a `last_update` audit timestamp.

## 2. The five relationships

### 2.1 film – inventory – rental – payment

**Chain:** `film` 1—N `inventory` 1—N `rental` 1—N `payment`.

A `film` is a title. `inventory` holds the physical copies of that title at each store. Every time a copy is rented, a `rental` row is created. Customers pay through `payment` rows that point back to the rental. To get from a payment to a film title you must go payment → rental → inventory → film.

| Link | CREATE TABLE (line) | FOREIGN KEY constraint | Notes |
|---|---|---|---|
| inventory → film | `inventory` (242) | `fk_inventory_film` (`film_id` → `film.film_id`, line 251) | Many copies per film. |
| rental → inventory | `rental` (290) | `fk_rental_inventory` (`inventory_id` → `inventory.inventory_id`, line 304) | A copy can be rented many times over time. |
| payment → rental | `payment` (269) | `fk_payment_rental` (`rental_id` → `rental.rental_id`, line 280) | `rental_id` is nullable; `ON DELETE SET NULL`. |

Also relevant: `inventory.store_id` (`fk_inventory_store`, line 250) says which store holds the copy. `film` is defined at line 137.

Example join: `payment p JOIN rental r USING (rental_id) JOIN inventory i USING (inventory_id) JOIN film f USING (film_id)`.

### 2.2 customer – store – staff

**Chain:** `customer` N—1 `store` 1—N `staff`, and `store` N—1 `staff` (manager).

A customer belongs to a home store. Staff work at a store. Each store also has exactly one manager, who is a staff member. Staff are also recorded on each `rental` and `payment` as the employee who handled it.

| Link | CREATE TABLE (line) | FOREIGN KEY constraint | Notes |
|---|---|---|---|
| customer → store | `customer` (115) | `fk_customer_store` (`store_id` → `store.store_id`, line 130) | Customer's home store. |
| staff → store | `staff` (312) | `fk_staff_store` (`store_id` → `store.store_id`, line 327) | Store where the employee works. |
| store → staff (manager) | `store` (335) | `fk_store_staff` (`manager_staff_id` → `staff.staff_id`, line 343) | Unique per store (`idx_unique_manager`, line 341). Circular with `fk_staff_store`. |

Related: `rental.staff_id` (`fk_rental_staff`, line 303) and `payment.staff_id` (`fk_payment_staff`, line 282) record who processed a transaction. Neither of these tables links directly to `store`. Store is reached through `customer` or `inventory`, and the two can differ, because a customer can rent from a store other than their home store.

### 2.3 film – actor

**Chain:** `film` N—M `actor` through the bridge table `film_actor`.

One film has many actors, and one actor appears in many films. `film_actor` resolves this: each row is one (actor, film) pair, and the composite primary key prevents duplicates.

| Link | CREATE TABLE (line) | FOREIGN KEY constraint | Notes |
|---|---|---|---|
| film_actor → actor | `film_actor` (163) | `fk_film_actor_actor` (`actor_id` → `actor.actor_id`, line 169) | Part of PK `(actor_id, film_id)`, line 167. |
| film_actor → film | `film_actor` (163) | `fk_film_actor_film` (`film_id` → `film.film_id`, line 170) | Indexed by `idx_fk_film_id`. |

Parent tables: `actor` (44) and `film` (137).

### 2.4 film – category

**Chain:** `film` N—M `category` through the bridge table `film_category`.

Same pattern as film–actor. Each row assigns one film to one category. The schema allows a film to have several categories (PK is `(film_id, category_id)`, line 181), so summing sales by category can count a film more than once. The `sales_by_film_category` view carries a comment saying this (lines 423–425).

| Link | CREATE TABLE (line) | FOREIGN KEY constraint | Notes |
|---|---|---|---|
| film_category → film | `film_category` (177) | `fk_film_category_film` (`film_id` → `film.film_id`, line 182) | |
| film_category → category | `film_category` (177) | `fk_film_category_category` (`category_id` → `category.category_id`, line 183) | |

Parent tables: `film` (137) and `category` (79).

### 2.5 address – city – country

**Chain:** `address` N—1 `city` N—1 `country`.

Location is normalized into three levels. `address` holds the street-level detail. `city` holds the city name. `country` holds the country name. To get a country for a customer, staff member or store, go through `address`: for example `customer` → `address` → `city` → `country`. The address table is shared by `customer` (`fk_customer_address`, line 129), `staff` (`fk_staff_address`, line 328) and `store` (`fk_store_address`, line 344).

| Link | CREATE TABLE (line) | FOREIGN KEY constraint | Notes |
|---|---|---|---|
| address → city | `address` (57) | `fk_address_city` (`city_id` → `city.city_id`, line 72) | |
| city → country | `city` (90) | `fk_city_country` (`country_id` → `country.country_id`, line 97) | |

Parent table: `country` (104).
