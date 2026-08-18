# Dreamhouse Remodel to Standard Salesforce — Specification & Prompt

Goal: re-implement the Dreamhouse application using out-of-the-box, declarative Salesforce
functionality instead of custom Apex and Lightning Web Components, keeping as close as possible to
the current user experience. This document is written as an actionable, step-by-step spec that a
Salesforce admin or engineer can follow, and doubles as a prompt for an AI agent doing the work.

Everything below was derived by reading the metadata in `force-app/main/default` of this repository.
Items that could not be confirmed from the repo are called out explicitly in
[Section 11 — Unconfirmed items to verify](#11-unconfirmed-items-to-verify-in-the-org).

---

## 0. Inventory of what exists today

### Custom objects

`Property__c` (label Property / Properties, Name field = Text "Property Name", sharing ReadWrite,
feeds + history + activities enabled, compact layout `Property_Compact_Layout`):

| Field API name       | Type                  | Details                                                              |
| -------------------- | --------------------- | -------------------------------------------------------------------- |
| `Address__c`         | Text(100)             | street address, plain text (not a standard Address compound field)   |
| `City__c`            | Text(50)              |                                                                      |
| `State__c`           | Text(20)              |                                                                      |
| `Zip__c`             | Text(10)              |                                                                      |
| `Description__c`     | Long Text Area(500)   | 3 visible lines                                                      |
| `Price__c`           | Currency(8,0)         | label "Asking Price"                                                 |
| `Price_Sold__c`      | Currency(8,0)         |                                                                      |
| `Assessed_Value__c`  | Currency(18,0)        |                                                                      |
| `Beds__c`            | Number(2,0)           |                                                                      |
| `Baths__c`           | Number(2,0)           |                                                                      |
| `Status__c`          | Picklist              | Contracted, Pre Market, Available, Under Agreement, Closed           |
| `Date_Listed__c`     | Date                  | default formula `TODAY() - 10`                                       |
| `Date_Pre_Market__c` | Date                  |                                                                      |
| `Date_Contracted__c` | Date                  |                                                                      |
| `Date_Agreement__c`  | Date                  |                                                                      |
| `Date_Closed__c`     | Date                  |                                                                      |
| `Days_On_Market__c`  | Formula (Number 18,0) | `TODAY() - Date_Listed__c`, blanks as zero — **already declarative** |
| `Location__c`        | Geolocation (scale 7) | exposes `Location__Latitude__s` / `Location__Longitude__s`           |
| `Picture__c`         | URL                   | full-size picture URL                                                |
| `Picture_IMG__c`     | Formula (Text)        | `IF(ISBLANK(Picture__c), '', IMAGE(Picture__c, "Picture"))`          |
| `Thumbnail__c`       | URL                   | thumbnail URL                                                        |
| `Thumbnail_IMG__c`   | Formula (Text)        | formula body not present in the field file (see §11)                 |
| `Record_Link__c`     | Formula (Text)        | formula body not present in the field file (see §11)                 |
| `Broker__c`          | Lookup → `Broker__c`  | child relationship name `Properties`                                 |

`Broker__c` (label Broker / Brokers, Name field = Text "Broker Name", compact layout `Broker_Compact`):

| Field API name    | Type           | Details                                  |
| ----------------- | -------------- | ---------------------------------------- |
| `Broker_Id__c`    | Number(18,0)   | external ID                              |
| `Title__c`        | Text(30)       |                                          |
| `Email__c`        | Email          |                                          |
| `Phone__c`        | Phone          |                                          |
| `Mobile_Phone__c` | Phone          |                                          |
| `Picture__c`      | URL            |                                          |
| `Picture_IMG__c`  | Formula (Text) | `IMAGE(Picture__c, "picture", 150, 150)` |

### Apex

| Class                                                                                             | Purpose                                                                                                                                                                                               |
| ------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `PropertyController.getPagedPropertyList`                                                         | Filtered + paged property search: `Name/City__c/Tags__c LIKE '%key%'`, `Price__c <=`, `Beds__c >=`, `Baths__c >=`, `ORDER BY Price__c`, `LIMIT/OFFSET`, plus a `COUNT()` query; returns `PagedResult` |
| `PropertyController.getPictures`                                                                  | Queries `ContentDocumentLink` (file types PNG/JPG/GIF) then `ContentVersion` for a property                                                                                                           |
| `PagedResult`                                                                                     | DTO: `pageSize`, `pageNumber`, `totalItemCount`, `records`                                                                                                                                            |
| `FileUtilities.createFile`                                                                        | Inserts `ContentVersion` + `ContentDocumentLink` from base64 data                                                                                                                                     |
| `GeocodingService`                                                                                | `@InvocableMethod(callout=true)` HTTP GET to `https://nominatim.openstreetmap.org/search` returning lat/lon                                                                                           |
| `SampleDataController.importSampleData`                                                           | Deletes all Cases/Properties/Brokers/Contacts, then loads three static-resource JSON files and randomizes `Date_Listed__c`                                                                            |
| `TestPropertyController`, `FileUtilitiesTest`, `GeocodingServiceTest`, `TestSampleDataController` | Tests for the above                                                                                                                                                                                   |

### Lightning Web Components

| LWC                                          | Role                                                                                                                                       |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `propertyFilter`                             | Search key + max price slider + min beds/baths; publishes `FiltersChange__c` (debounced 350 ms)                                            |
| `propertyTileList`                           | Subscribes to `FiltersChange__c`, wires `getPagedPropertyList`, renders `propertyTile` grid + `paginator`, publishes `PropertySelected__c` |
| `propertyTile`                               | Single tile (thumbnail, name, price, beds/baths)                                                                                           |
| `paginator`                                  | Previous/next paging UI (2000-row offset cap)                                                                                              |
| `propertyListMap`                            | Loads Leaflet.js from the `leafletjs` static resource, plots OSM tiles + markers for filtered properties, publishes `PropertySelected__c`  |
| `propertyMap`                                | Single-property `lightning-map` marker; subscribes to `PropertySelected__c`                                                                |
| `propertySummary`                            | Selected-property summary card (picture + `lightning-output-field`s), navigates to record                                                  |
| `brokerCard`                                 | Reads `Property__c.Broker__c` then broker Name/Phone/Mobile/Email, navigates to broker                                                     |
| `propertyCarousel`                           | `getPictures` carousel + image compression (`lightning/mediaUtils`) + `FileUtilities.createFile` upload                                    |
| `daysOnMarket`                               | Reads `Date_Listed__c` / `Days_On_Market__c` and renders a colored badge + bar (normal <30, warning <60, alert ≥60)                        |
| `propertyLocation`                           | Device geolocation (`lightning/mobileCapabilities`) + Haversine distance to the property                                                   |
| `barcodeScanner`                             | QR scan (`lightning/mobileCapabilities`) → navigate to the scanned Property record                                                         |
| `listContactsFromDevice`                     | Device contacts (`lightning/mobileCapabilities`)                                                                                           |
| `sampleDataImporter`                         | Button calling `SampleDataController.importSampleData`                                                                                     |
| `navigateToRecord`, `errorPanel`, `ldsUtils` | Flow/utility helpers                                                                                                                       |

### Other metadata

- Flexipages: `Property_Explorer` (AppPage: `propertyFilter` | `propertyTileList` + `propertyMap` + `propertySummary` + `flowruntime:interview` for Create Property), `Property_Finder` (AppPage: `propertyFilter` | `propertyListMap` | `propertySummary` + `daysOnMarket` + `barcodeScanner`), `Property_Record_Page` (standard record-home template with `propertyCarousel`, `brokerCard`, `daysOnMarket`, `propertyMap`, `propertyLocation`, highlights panel, field sections, related lists), `Broker_Record_Page` (fully standard components already), `Settings` (`sampleDataImporter`).
- Layouts: `Property__c-Property Layout`, `Broker__c-Broker Layout`.
- Compact layouts: `Property_Compact_Layout` (Name, City__c, Price__c, Beds__c, Baths__c) and
  `Broker_Compact` (Name, Title__c, Phone__c, Mobile_Phone__c, Email__c).
- List views: only `All` on each object — `Property__c.All` shows Name, City, Beds, Price, Status with
  scope Everything and no filters; `Broker__c.All` likewise.
- Flow: `Create_property` (screen flow — address screen → `GeocodingService` Apex action → property details → picture upload → content-document lookups → set `Picture__c`/`Thumbnail__c` → navigate to record).
- Message channels: `FiltersChange__c` (searchKey, maxPrice, minBedrooms, minBathrooms) and `PropertySelected__c` (propertyId).
- Static resources: `leafletjs`, `sample_data_properties.json`, `sample_data_brokers.json`, `sample_data_contacts.json`.
- Remote site setting `nominatim_openstreetmap`; CSP trusted sites `openStreetMap`, `s3_us_west_2_amazonaws_com`.
- App `Dreamhouse` with tabs Home, Property Explorer, Property Finder, Contacts, Properties, Brokers, Files, Settings; tabs `Property__c`, `Broker__c`, `Property_Explorer`, `Property_Finder`, `Settings`.
- Permission set `dreamhouse` (objects `Property__c`/`Broker__c`, Apex `PropertyController`, `PagedResult`, `SampleDataController`, the five tabs).
- Agentforce prompt templates: `Property`, `PropertyExplorer`, `PropertyFinder`.

---

## 1. Summary mapping table — custom today vs. standard alternative

| #   | Capability                              | Custom today                                                                                                                                                      | Standard alternative                                                                                                                                                     | Fidelity                          |
| --- | --------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------- |
| 1   | Data model                              | `Property__c`, `Broker__c` objects + fields as source metadata                                                                                                    | Same two custom objects, but created declaratively in Object Manager; optionally model Broker as `Account`/`Contact`/`User`                                              | Full                              |
| 2   | Search & filtering                      | `PropertyController.getPagedPropertyList`, `PagedResult`, `propertyFilter`, `propertyTileList`, `propertyTile`, `paginator`, `FiltersChange__c`                   | List views (with filters, sort, built-in paging), list view search box, global/SOSL search, optional report + dashboard                                                  | Partial — no live slider UX       |
| 3   | Property record page                    | `propertySummary`, `brokerCard`, `propertyCarousel`                                                                                                               | Lightning App Builder record page: Highlights Panel, Record Detail / Field Sections, Related Record (Broker lookup), Files related list                                  | High                              |
| 4   | Days on market                          | `daysOnMarket` LWC                                                                                                                                                | `Days_On_Market__c` formula field (already exists) + Highlights Panel / compact layout; conditional coloring via a formula "status" field                                | High (loses bar chart)            |
| 5   | Maps & geocoding                        | `GeocodingService` + Nominatim callout, `propertyListMap` (Leaflet), `propertyMap`                                                                                | Geocode Data Integration Rules on a standard Address compound field; auto-rendered map for Geolocation/Address fields, list view "Map" view in the Salesforce mobile app | Partial                           |
| 6   | Images / files                          | `FileUtilities`, `PropertyController.getPictures`, `propertyCarousel`                                                                                             | Files related list + drag-and-drop upload; `Picture_IMG__c`/`Thumbnail_IMG__c` IMAGE formula fields                                                                      | Partial — no carousel/compression |
| 7   | Sample data                             | `SampleDataController` + `sampleDataImporter` + JSON static resources                                                                                             | Data Import Wizard or Data Loader with CSV files                                                                                                                         | Full (manual)                     |
| 8   | Create Property wizard                  | `Create_property` screen flow calling `GeocodingService`                                                                                                          | Same screen flow minus the Apex action; standard New record modal + geocode rules                                                                                        | High                              |
| 9   | Mobile QR scan                          | `barcodeScanner`                                                                                                                                                  | None declarative — keep custom                                                                                                                                           | Exception                         |
| 10  | Device contacts                         | `listContactsFromDevice`                                                                                                                                          | None declarative — keep custom                                                                                                                                           | Exception                         |
| 11  | Device distance                         | `propertyLocation`                                                                                                                                                | None declarative — keep custom                                                                                                                                           | Exception                         |
| 12  | Synchronized filter/list/map catalog UX | `FiltersChange__c` + `PropertySelected__c` LMS wiring across `propertyFilter`/`propertyTileList`/`propertyListMap`/`propertySummary`/`propertyMap`/`daysOnMarket` | Not reproducible declaratively — keep custom or accept list-view navigation                                                                                              | Exception                         |

---

## 2. Data model (declarative)

Keep both custom objects: there is no standard "Property" sObject in core Salesforce (Financial
Services Cloud and Net Zero Cloud ship unrelated objects; Salesforce for Real Estate / Consumer Goods
templates are separate products — verify licensing before assuming any of them).

Steps:

1. **Setup → Object Manager → Create → Custom Object** for `Property` (plural Properties, Record Name
   = Text "Property Name"). Enable Reports, Activities, Field History, Feed Tracking, Search, Sharing =
   Read/Write, Bulk API and Streaming — matching the current object definition.
2. Create `Broker` the same way (Record Name = Text "Broker Name"; Activities, Feeds and History are
   currently **off** for Broker, Reports/Search/Sharing on).
3. Create every field in §0 through **Fields & Relationships → New**, choosing the field type in the
   table. Nothing here requires code:
    - Text / Long Text Area / Currency / Number / Date / Picklist / URL / Email / Phone → direct
      equivalents in the field wizard.
    - `Location__c` → **Geolocation**, decimal notation, 7 decimal places. This automatically creates the
      `Location__Latitude__s` / `Location__Longitude__s` sub-fields the existing code queries.
    - `Days_On_Market__c` → **Formula (Number, 0 decimals)** = `TODAY() - Date_Listed__c`, "Treat blank
      fields as zeroes".
    - `Picture_IMG__c` / `Thumbnail_IMG__c` → **Formula (Text)** using `IMAGE()`.
    - `Date_Listed__c` → default value formula `TODAY() - 10`.
    - `Broker__c` on Property → **Lookup** to Broker, child relationship name `Properties`.
    - `Broker_Id__c` → Number, External ID (needed for upserts during data loads).
4. **Optional simplification — drop `Broker__c` entirely.** A broker is a person with a name, title,
   email, phone, mobile phone and a picture. All of that exists out of the box:
    - `User` — best fit if brokers are org users (has Title, Email, Phone, MobilePhone, SmallPhotoUrl);
      `Property__c.Broker__c` becomes a Lookup(User) and Chatter photos replace `Picture__c`.
    - `Contact` — best fit if brokers are external people (Title, Email, Phone, MobilePhone, and a
      related Account for the brokerage). This also unifies with the existing sample Contacts.
    - `Account` (Record Type = Brokerage) if the "broker" is a firm rather than a person.
      Trade-off: standard objects bring page layouts, sharing, activities, duplicate rules and Einstein
      features for free, but the migration must remap `sample_data_brokers.json` and every reference to
      `Broker__c` (lookup field, compact layout, tab, permission set, record page, `brokerCard`).
5. **Address**: to unlock standard geocoding (§6) add a standard **Address compound field**. Address
   compound fields are only available out of the box on standard objects (Account, Contact, Lead,
   Order, …); on a custom object, Geocode Data Integration Rules require you to create a
   **`Property_Address__c` field of type Address** where supported, otherwise you must keep the four
   discrete text fields and geocode another way. **Verify in the target org** which of these is
   available for the API version and edition in use (see §11).

Metadata removed by this step: none (fields stay); what changes is that they are administered in
Object Manager rather than hand-edited XML.

---

## 3. Property search & filtering → List Views + Search

**Removed:** `PropertyController.getPagedPropertyList`, `PagedResult`, `TestPropertyController`
(the paging tests), `propertyFilter`, `propertyTileList`, `propertyTile`, `paginator`,
`FiltersChange__c` message channel, and the `Property_Explorer` / `Property_Finder` flexipages'
left/center regions.

**Replaced by:**

1. **Object tab + list views.** Enable the `Properties` tab in the Dreamhouse app (it already exists).
   Only an unfiltered `All` list view exists today (Name, City, Beds, Price, Status). Add list views
   that reproduce the current filter semantics:
    - _Available Properties_ — `Status__c equals Available`.
    - _Affordable Homes_ — `Price__c less or equal 500000` (the LWC slider maxes at 1,200,000; create
      one view per price band, or let users use the per-column filter).
    - _Family Homes_ — `Beds__c greater or equal 3 AND Baths__c greater or equal 2`.
    - _Recently Listed_ — `Date_Listed__c = LAST_N_DAYS:30`, sorted by `Date_Listed__c` descending.
      Filter logic mirrors the SOQL exactly: `Price__c <=`, `Beds__c >=`, `Baths__c >=`.
2. **Sorting and paging come free.** Click a column header to sort (the Apex hard-codes
   `ORDER BY Price__c`); the list view footer pages through records (the `paginator` LWC and its
   2000-offset cap disappear).
3. **Keyword search.** The LIKE across `Name`, `City__c`, `Tags__c` is replaced by:
    - the list view **Search this list** box (searches the displayed list), and
    - **global search** (SOSL), which requires the fields to be searchable: `Name` is indexed
      automatically; mark `City__c` and `Tags__c` as searchable by adding them to the object's
      **Search Layouts → Search Results** columns and, for text fields, they are indexed by default.
      Configure **Setup → Search → Search Settings** and the object's **Search Layouts** so results
      show Name, City, Price, Beds, Baths, Status.
4. **Filter chips at runtime.** Users can add ad-hoc filters via the list view **Filter** panel and pin
   a favourite list view, which covers the "change max price, see results" interaction without code.
5. **Optional: reports + dashboard.** A "Properties by City / by Status" report with bucketing gives a
   richer analytic slice than the tile grid, again with no code.

**Fidelity gap:** the debounced slider UX, the 3-across image tile grid, and instant re-query as the
user drags a slider are _not_ reproducible with list views. Accept list views + search, or keep the
custom catalog (see §9).

---

## 4. Property record page → Lightning App Builder

**Removed:** `propertySummary`, `brokerCard`, `propertyCarousel` (and `PropertyController.getPictures`,
`FileUtilities`, see §7).

**Replaced by**, in **Setup → Lightning App Builder → Property Record Page**:

1. **Highlights Panel** at the top, driven by the `Property_Compact_Layout` compact layout, which today
   holds Name, City__c, Price__c, Beds__c, Baths__c. Add `Status__c` and `Days_On_Market__c` to it —
   this reproduces most of `propertySummary`.
2. **Record Detail** (or **Field Section** components inside a two-column template) for the remaining
   fields, grouped as: _Location_ (Address, City, State, Zip, Location), _Pricing_ (Asking Price,
   Price Sold, Assessed Value), _Details_ (Beds, Baths, Description, Tags), _Lifecycle_ (Status and the
   five Date fields, Days On Market).
3. **Related Record** component pointed at the `Broker__c` lookup, with an update action; the existing
   `Broker_Compact` compact layout already shows Name, Title, Phone, Mobile Phone, Email — exactly the
   fields `brokerCard` renders. This is the declarative
   equivalent of `brokerCard`, including inline edit — which the LWC does not offer.
   Add `Picture_IMG__c` to the Broker compact layout to render the broker photo.
4. **Files related list** (see §7) instead of the carousel; add `Picture_IMG__c` to the Property
   detail section so the main photo renders inline.
5. **Rich Text** component for any static branding that `propertySummary` provided.
6. Keep the existing tabs/facets structure of `Property_Record_Page`; the Broker record page is
   already 100 % standard components and needs no change.

---

## 5. Days on market → formula field

**Removed:** `daysOnMarket` LWC (`daysOnMarket.js/html/css`, its Jest test, and its placement on
`Property_Record_Page` and `Property_Finder`).

**Replaced by:** the already-existing `Days_On_Market__c` formula field
(`TODAY() - Date_Listed__c`, treat blanks as zero). The LWC does not compute the number — it only
reads the formula field and adds a colored badge/bar — so the calculation is already declarative.

To keep the visual signal without code:

1. Add `Days_On_Market__c` to the compact layout so it shows in the Highlights Panel.
2. Add a `Days_On_Market_Status__c` **Formula (Text)** field for the same thresholds the LWC uses:
   `IF(Days_On_Market__c < 30, 'Normal', IF(Days_On_Market__c < 60, 'Warning', 'Alert'))`, optionally
   returning an `IMAGE()` of a green/yellow/red icon so the record page shows a colored indicator.
3. Alternatively surface it as a **list view / report conditional highlighting** (reports support
   conditional formatting on summary fields out of the box).

**Fidelity gap:** the horizontal progress bar (`daysOnMarket / 90 * 100 %`) has no declarative
equivalent; the IMAGE formula or report conditional formatting is the closest standard analogue.

---

## 6. Maps & geocoding → Data Integration Rules + standard maps

**Removed:** `GeocodingService`, `GeocodingServiceTest`, the `nominatim_openstreetmap` remote site
setting, the `openStreetMap` CSP trusted site, the `leafletjs` static resource, `propertyListMap`,
and the Apex action step inside the `Create_property` flow.

**Replaced by:**

1. **Geocode Data Integration Rules** — Setup → Data Integration Rules → activate the geocode rules
   (Address for Accounts / Contacts / Leads … ). These populate hidden geolocation compound sub-fields
   automatically from a **standard Address compound field**, at no cost and with no callout.
    - Because Dreamhouse stores the address in four discrete **text** fields, this only works after
      adding an Address-type field (§2 step 5). If an Address compound field cannot be created on the
      custom object in the target org, the standard rules do **not** apply — in that case keep a
      small custom geocoding step, or move Property to a standard object.
    - Out-of-the-box geocode rules do not write to a custom `Location__c` Geolocation field; they write
      to the rule's own geolocation sub-fields. If downstream components must read `Location__c`, add a
      **record-triggered Flow** (declarative, no Apex) that copies the geocoded latitude/longitude into
      `Location__c`. Verify field-level behavior in the org (§11).
2. **Maps rendered automatically.** Salesforce renders a map preview for standard Address compound
   fields on record pages and in the Salesforce mobile app with no configuration. For the Geolocation
   field, the record page shows latitude/longitude; to show a pin, use the base
   **`lightning-map`** component — this is a base component shipped by Salesforce, so it is not custom
   code in the sense of Apex/LWC business logic, but placing it still requires a thin wrapper LWC
   unless you use the record page's built-in address map.
3. **List view maps.** In the Salesforce mobile app, list views of objects with an Address field expose
   a **Map** view, which is the closest declarative equivalent to `propertyListMap`'s multi-pin map.
4. `propertyMap` (single-property `lightning-map`) can be dropped in favour of the automatic address
   map, or kept — it is a ~50-line wrapper over a base component with no business logic.

**Fidelity gap:** custom marker icons, hover tooltips with thumbnails, and click-to-select-a-property
(publishing `PropertySelected__c`) are not available declaratively.

---

## 7. Images / files → Files related list + standard upload

**Removed:** `FileUtilities`, `FileUtilitiesTest`, `PropertyController.getPictures` (and the picture
tests in `TestPropertyController`), `propertyCarousel`, and the `s3_us_west_2_amazonaws_com` CSP
trusted site if it exists only for the sample images (verify — see §11).

**Replaced by:**

1. **Files related list** on the Property record page (Lightning App Builder → Related Lists, or the
   page layout's "Files" related list). It provides drag-and-drop upload, preview, versioning, sharing
   and deletion — everything `FileUtilities.createFile` and `getPictures` implement by hand, including
   the `ContentVersion` + `ContentDocumentLink` plumbing.
2. **`lightning-file-upload`** base component when an upload button is wanted outside the related list
   (it is also available as a Flow screen component — **Files** — so the `Create_property` flow's
   picture step stays declarative).
3. **`Picture__c` / `Thumbnail__c` URL fields + `Picture_IMG__c` / `Thumbnail_IMG__c` IMAGE formula
   fields** already render pictures declaratively wherever a field can be placed (record page, list
   view, report, compact layout).

**Fidelity gap:** the carousel widget and the client-side image resize/compression
(`lightning/mediaUtils`, 500×500, quality 0.75) have no declarative equivalent. Standard Files stores
the original image; use the Files preview or the IMAGE formula field instead of a carousel.

---

## 8. Sample data loading → Data Import Wizard / Data Loader

**Removed:** `SampleDataController`, `TestSampleDataController`, `sampleDataImporter`, the `Settings`
flexipage and `Settings` tab (or repurpose the tab), and the `sample_data_properties.json` /
`sample_data_brokers.json` / `sample_data_contacts.json` static resources once converted to CSV.

**Replaced by:**

1. Convert each JSON static resource to CSV (one file per object; keep the `Broker_Id__c` external ID
   column so properties can be matched to brokers).
2. Load in dependency order: **Brokers → Contacts → Properties** (Property references Broker).
3. **Data Import Wizard** (Setup → Data Import Wizard) handles custom objects, supports upsert by
   external ID and is fully point-and-click for the volumes involved. Use **Data Loader** (or the
   `sf data import tree`/`sf data import bulk` CLI commands) for larger volumes or for repeatable
   scripted loads in scratch orgs.
4. The `randomizeDateListed` behaviour (`TODAY() - random(0..90)`) has no import-wizard equivalent:
   bake concrete dates into the CSV, or rely on the `Date_Listed__c` default value `TODAY() - 10`.
5. The controller's destructive pre-step (`delete [SELECT Id FROM Case/Property__c/Broker__c/Contact]`)
   is deliberately not reproduced. To reset a demo org, use a fresh scratch org or Data Loader's
   delete/hard-delete operation.

---

## 9. Items that legitimately remain custom

These cannot be reproduced with declarative configuration and should stay as LWCs. Document them as
accepted exceptions:

1. **`barcodeScanner`** — wraps `getBarcodeScanner()` from `lightning/mobileCapabilities` to scan a QR
   code and navigate to the encoded Property record. There is no declarative barcode scanner
   component; the Flow **Scan Barcode** screen component covers some cases in the Salesforce mobile
   app and is worth evaluating as a partial replacement, but it cannot navigate to an arbitrary record
   id without a Flow around it.
2. **`listContactsFromDevice`** — wraps `getContactsService()` to read the device address book. No
   declarative equivalent exists.
3. **`propertyLocation`** — wraps `getLocationService()` plus a Haversine distance calculation against
   `Location__Latitude__s` / `Location__Longitude__s`. Standard geolocation `DISTANCE()` formulas can
   compute distance between two stored geolocations, but not between a record and the _device's live
   position_, so this stays custom.
4. **The synchronized catalog UX** — `propertyFilter` → `FiltersChange__c` → `propertyTileList` /
   `propertyListMap`, and `PropertySelected__c` → `propertySummary` / `propertyMap` / `daysOnMarket`.
   Lightning Message Service has no declarative authoring surface: cross-component, same-page
   master/detail interaction without navigation cannot be built in App Builder. Either accept the
   list-view experience of §3 (click a row → open the record page) or keep these components.
5. **Agentforce prompt templates** (`Property`, `PropertyExplorer`, `PropertyFinder`) are already
   declarative metadata and should be kept as-is; verify they do not reference removed Apex.

---

## 10. Execution checklist

1. [ ] Create/confirm `Property__c` and `Broker__c` and every field in §0 via Object Manager
       (decide first whether Broker becomes `Contact`/`User`/`Account`).
2. [ ] Add an Address compound field (or confirm it is unavailable) and activate Geocode Data
       Integration Rules; add a record-triggered Flow to sync into `Location__c` if needed.
3. [ ] Build the list views and search layouts of §3; add the Properties tab to the Dreamhouse app.
4. [ ] Rebuild `Property_Record_Page` in App Builder with Highlights Panel, Field Sections, Related
       Record (Broker) and the Files related list.
5. [ ] Put `Days_On_Market__c` (+ optional status formula) on the compact layout.
6. [ ] Convert the sample-data JSON to CSV and load with Data Import Wizard / Data Loader.
7. [ ] Edit `Create_property` to drop the `GeocodingService` Apex action and the content-document
       lookups, using the Files screen component and geocode rules instead.
8. [ ] Delete the replaced metadata: Apex classes `PropertyController`, `PagedResult`,
       `FileUtilities`, `GeocodingService`, `SampleDataController` and their tests; LWCs
       `propertyFilter`, `propertyTileList`, `propertyTile`, `paginator`, `propertyListMap`,
       `propertySummary`, `brokerCard`, `propertyCarousel`, `daysOnMarket`, `sampleDataImporter`;
       message channel `FiltersChange__c` (and `PropertySelected__c` if the catalog UX is dropped);
       flexipages `Property_Explorer`, `Property_Finder`, `Settings` and their tabs; static resources
       `leafletjs` and the three sample-data JSON files; remote site `nominatim_openstreetmap`; CSP
       trusted site `openStreetMap`.
9. [ ] Update the `dreamhouse` permission set: remove the Apex class access entries
       (`PropertyController`, `PagedResult`, `SampleDataController`) and the removed tabs; keep object
       and field permissions, adding FLS for any new fields.
10. [ ] Update the `Dreamhouse` app navigation (remove Property Explorer / Property Finder / Settings
        tabs unless the custom exceptions of §9 are retained).
11. [ ] Re-run the Jest/Apex test suites — most will be deleted along with their subjects; ensure the
        remaining tests still pass and code coverage requirements are met for whatever Apex survives.

---

## 11. Unconfirmed items to verify in the org

These could **not** be confirmed from the repository and must be checked before implementing:

1. **`Property__c.Tags__c`** — Text(255), referenced by `PropertyController`'s LIKE search. Confirm
   whether it holds comma-separated tags; free text limits list-view filtering to `contains`.
2. **`Thumbnail_IMG__c` and `Record_Link__c` formula bodies** — both field files declare
   `type=Text` and `formulaTreatBlanksAs=BlankAsZero` but the `<formula>` element is not present in
   the checked-in metadata (unlike `Picture_IMG__c`). Retrieve the current formulas from the org
   before recreating these fields.
3. **Address compound field on a custom object** — whether the target org/edition/API version lets you
   create a field of type Address on `Property__c`, and whether the standard Geocode Data Integration
   Rules can be pointed at it. This is the single biggest risk in §6. Salesforce's out-of-the-box
   geocode rules are documented for Account, Contact, Lead, Contract and Order addresses; custom-object
   support must be verified in the org.
4. **Whether geocode rules can populate a custom Geolocation field** (`Location__c`) directly, or
   whether the record-triggered Flow workaround is required.
5. **Broker model choice** — whether brokers are internal users, external contacts, or firms. This
   determines the §2 step 4 recommendation and the data migration.
6. **`s3_us_west_2_amazonaws_com` CSP trusted site** — confirm it is only used for sample property
   images (the `Picture__c` / `Thumbnail__c` URLs) before removing it.
7. **Agentforce prompt templates** (`Property`, `PropertyExplorer`, `PropertyFinder`) — confirm they do
   not invoke the Apex being deleted or reference the removed flexipages.
8. **Row-count expectations** — list views cap at 2000 rows for some operations, which is the same cap
   the `paginator` enforced; confirm the property volume stays within standard list view limits.
9. **Field-level security** in the `dreamhouse` permission set for any newly added field (status
   formula, Address compound field) — the current permission set grants FLS per field and must be
   extended.
10. **Licensing** — whether any Salesforce industry product (e.g. Salesforce for Real Estate) is
    available in the org, which could replace both custom objects with a supported standard data model.
