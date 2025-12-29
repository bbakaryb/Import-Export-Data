# DataPorter — CSV Import / Export for Salesforce (LWC) Package

## 📌 Description
DataPorter package enables **CSV export and import** of Salesforce records, directly from a record page.:  
It is designed to be:
- 🔐 **Secure** (FLS enforced)
- 🧠 **User-friendly** (preview + optional mapping)
- 🧩 **Reusable** (generic Apex services) 

---

## 📂 Package Content
- **Main Class**: `Import_Export_Data` (entry point for LWC)
    - Export CSV
    - Import CSV
    - Resolve object API name from recordId
    - List CSV-compatible fields

- **Export Service**: `CsvExportService`(Handles CSV export logic)  
    - Uses field **labels** as CSV headers
    - Base64-encoded CSV output 

- **Import Service**: `CsvImportService`(Handles CSV import logic)  
    - CSV parsing and validation
    - Optional column mapping
    - Automatic fallback matching
    - Field type handling
    - Insert & Update supported via Id column

- **Utils**: `CsvUtils`(Shared CSV utility methods)  
    - CSV escaping 
    - CSV parsing (quoted values, escaped quotes)
    - Line normalization

- **Lightning Web Component**: `lwc01_DataPorter`(main UI component)
    - Detect object from `recordId`
    - Load available fields
    - Handle CSV export
    - Handle CSV import
    - Preview CSV content
    - Build mapping model
    - Field ordering
    - Preview before import
    - Optional mapping with auto-detection
    - Toast notifications


---

## ⚠️ Current Limitations
    - Single-record export only
    - Synchronous import and update (not suitable for very large CSV files, no queueable yet)
    - No rollback / partial success handling yet

---

## 🔧 Installation Guide

### Install package in a **Scratch Org**

1. Enable DevHub in your main org. 
2. Clone the repository
```bash
git clone https://github.com/bbakaryb/Import-Export-Data.git
cd Import-Export-Data
```

3. Authenticate a Dev Hub
```bash
sf org login web --set-default-dev-hub --alias DevHub
```

4. Create a Scratch Org
```bash
sf org create scratch --definition-file config/project-scratch-def.json --duration-days 30 --alias MyScratchOrg --target-dev-hub DevHub
```

5. Install the package:
```bash
sf package install --wait 10 --publish-wait 10 --package dataporter@0.1.0-1 --installation-key test1234 --no-prompt --target-org MyScratchOrg
```

6. Open your Scratch Org:
```bash
sf org open --target-org MyScratchOrg
```

### Install package in a **Production or Sandbox Org**

1. Authenticate your target org:
```bash
sf org login web --alias MyOrg
```

2. Install the package:
```bash
sf package install --wait 10 --publish-wait 10 --package dataporter@0.1.0-1 --installation-key test1234 --no-prompt --target-org MyOrg
```

---

## 🛠 Usage
1. Add `lwc01_DataPorter` in a record page
2. Open a record page
2. Select fields to export
3. Export CSV (as template)
4. Edit CSV
5. Re-import CSV with optional mapping  
