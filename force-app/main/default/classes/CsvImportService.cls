public with sharing class CsvImportService {

    // Maximum number of CSV data lines allowed
    private static final Integer MAX_LINES = 5000;

    /**
     * Main CSV import entry point
     * @param objectName API name of the target object
     * @param base64Csv  Base64-encoded CSV file content
     * @return Map containing success flag, errors or inserted count
     */
    public static Map<String, Object> importCsv(String objectName, String base64Csv, Map<String, String> csvToFieldMap) {
        if (String.isBlank(objectName) || String.isBlank(base64Csv)) {
            throw new AuraHandledException('Object name and CSV file are required.');
        }

        Boolean isUpdate = false; // INSERT by default
        
        List<String> errors = new List<String>();
        List<SObject> toInsert = new List<SObject>();

        /* === Decode CSV === */
        List<String> lines = decodeAndSplitCsv(base64Csv);
        /* === Object describe === */
        Schema.SObjectType sType = Schema.getGlobalDescribe().get(objectName);
        if (sType == null) throw new AuraHandledException('Unknow object: ' + objectName);

        Schema.DescribeSObjectResult dsr = sType.getDescribe();
        Map<String, Schema.SObjectField> fieldMap = dsr.fields.getMap();

        /* === CSV headers === */
        List<String> headers = new List<String>();
        for (String h : CsvUtils.parseLine(lines[0])) {
            headers.add(h.replace('\uFEFF','').replace('"','').trim());
        }

        Set<String> headerSet = new Set<String>();
        for (String h : headers) {
            if (!headerSet.add(h.toLowerCase())) {
                errors.add('Duplicate CSV column: "' + h + '"');
            }
        }

        /* =========================================================
           header → API resolution
        ========================================================= */
        Map<String, String> resolvedHeaderToApi = resolveHeaders(headers, fieldMap, csvToFieldMap, errors);

        /* === STOP BEFORE DATA LOOP === */
        if (!errors.isEmpty()) {
            return new Map<String, Object>{
                'success' => false,
                'errors'  => errors
            };
        }
        // Presence of Id column enables update/upsert mode
        isUpdate = resolvedHeaderToApi.values().contains('Id');


        /* === Parse CSV data lines === */
        for (Integer i = 1; i < lines.size(); i++) {
            String line = lines[i].trim();
            if (String.isBlank(line)) continue;

            Integer lineNumber = i + 1;
            List<String> cols = CsvUtils.parseLine(line);

            if (cols.size() != headers.size()) {
                errors.add('Line ' + lineNumber + ' : incorrect number of columns.');
                continue;
            }

            SObject record = sType.newSObject();
            Boolean hasAtLeastOneValue = false;

            for (Integer c = 0; c < headers.size(); c++) {
                String header = headers[c];
                String rawValue = cols[c].trim();
                if(rawValue == null || rawValue == '' || String.isBlank(rawValue)) continue;
                if (!resolvedHeaderToApi.containsKey(header)) {
                    errors.add('Line ' + lineNumber + ' : unknow column "' + header + '"');
                    continue;
                }

                String apiField = resolvedHeaderToApi.get(header);
                /* === special case : ID === */
                if (apiField == 'Id') {
                    try {
                        record.put('Id', (Id) rawValue);
                        hasAtLeastOneValue = true;
                    } catch (Exception e) {
                        errors.add('Line ' + lineNumber + ' : invalid id "' + rawValue + '"');
                    }
                    continue;
                }
                Schema.DescribeFieldResult dfr = fieldMap.get(apiField).getDescribe();
                    
                Boolean canWrite = (isUpdate && dfr.isUpdateable()) || (!isUpdate && dfr.isCreateable());
                    
                if((!canWrite) || String.isBlank(rawValue)) continue;

                try {
                    /* === PICKLIST : strict validation === */
                    if (dfr.getType() == Schema.DisplayType.Picklist || dfr.getType() == Schema.DisplayType.MultiPicklist) {
                        if (!handlePicklist(record, dfr, apiField, rawValue, lineNumber, errors)) {
                            continue;
                        }
                        hasAtLeastOneValue = true;
                        continue;
                    }     

                    /* === Other field types (Boolean included) === */
                    Object typedValue = castToCorrectType(dfr, rawValue);

                    if (typedValue == null) {
                        errors.add('Line ' + lineNumber + ' – field "' + dfr.getLabel() + '" : invalid value "' + rawValue + '"');
                    } else {
                        record.put(apiField, typedValue);
                        hasAtLeastOneValue = true;
                    }

                }
                catch (Exception e) {
                    errors.add('Line ' + lineNumber + ' – field "' + dfr.getLabel() + '" : ' + e.getMessage());
                }
            }
            // Ignore empty rows
            if (hasAtLeastOneValue) {
                Map<String, Object> populated = record.getPopulatedFieldsAsMap();
                // CSV import is strict: all required fields must be provided in the file
                if (!isUpdate) {
                    validateRequiredFields(fieldMap, populated, lineNumber, errors);
                }

                toInsert.add(record);
            } 
        }
        /* === STOP if errors === */
        if (!errors.isEmpty()) {
            return new Map<String, Object>{
                'success' => false,
                'errors' => errors
            };
        }
        if (toInsert.isEmpty()) {
            return new Map<String, Object>{
                'success' => false,
                'errors'  => new List<String>{ 'No valid data rows found.' }
            };
        }
        /* === DML (upsert supports insert or update) === */
        Database.UpsertResult[] results = Database.upsert(toInsert, false);
        Integer success = 0;
        Integer failed = 0;

        for (Database.UpsertResult sr : results) {
            if (sr.isSuccess()) {
                success++;
            } else {
                failed++;
            }
        }

        return new Map<String, Object>{
            'success'  => true,
            'inserted' => toInsert.size()
        };
    }

    /**
     * Convert raw CSV value to the correct Apex type
     */
    public static Object castToCorrectType(Schema.DescribeFieldResult dfr, Object rawValue) {
        if (rawValue == null) return null;

        try {
            Schema.DisplayType type = dfr.getType();
            switch on type {
                when DateTime {
                    if (rawValue instanceof DateTime) return rawValue;
                    if (rawValue instanceof String) return DateTime.valueOf((String)rawValue);
                }
                when Date {
                    if (rawValue instanceof Date) return rawValue;
                    if (rawValue instanceof String) return Date.valueOf((String)rawValue);
                }
                when Boolean {
                    if (rawValue instanceof Boolean) {
                        return rawValue;
                    }
                    if (rawValue instanceof String) {
                        String v = ((String)rawValue).trim().toLowerCase();
                        if (v == 'true' || v == '1' || v == 'yes' || v == 'oui') {
                            return true;
                        }
                        if (v == 'false' || v == '0' || v == 'no' || v == 'non') {
                            return false;
                        }
                        throw new IllegalArgumentException(
                            'Invalid boolean value: ' + rawValue
                        );
                    }
                    throw new IllegalArgumentException(
                        'Invalid boolean value: ' + rawValue
                    );
                }

                when Integer {
                    if (rawValue instanceof Integer) return rawValue;
                    if (rawValue instanceof String) return Integer.valueOf((String)rawValue);
                }
                when Double {
                    if (rawValue instanceof Decimal) return rawValue;
                    if (rawValue instanceof String) return Decimal.valueOf((String)rawValue);
                }
                when Currency, Percent {
                    if (rawValue instanceof Decimal) return rawValue;
                    if (rawValue instanceof String) return Decimal.valueOf((String)rawValue);
                }
                when String, Reference {
                    return String.valueOf(rawValue);
                }
                when else {
                    return String.valueOf(rawValue);
                }
            }
        } catch (Exception e) {
            System.debug('Conversion error for field ' + dfr.getName() + ' : ' + e.getMessage());
        }
        return null;
    }

    public static Map<String, String> resolveHeaders(List<String> headers, Map<String, Schema.SObjectField> fieldMap, Map<String, String> csvToFieldMap, List<String> errors) {
        Map<String, String> autoHeaderToApi = new Map<String, String>();
        /* =========================================================
           Automatic header → API mapping (Label / API)
        ========================================================= */
        for (String api : fieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldMap.get(api).getDescribe();
            autoHeaderToApi.put(api.toLowerCase(), api);
            autoHeaderToApi.put(dfr.getLabel().toLowerCase(), api);
        }

        Map<String, String> normalizedCsvMap = new Map<String, String>();
        if (csvToFieldMap != null) {
            for (String k : csvToFieldMap.keySet()) {
                normalizedCsvMap.put(k.toLowerCase(), csvToFieldMap.get(k));
            }
        }
        /* =========================================================
           FINAL header → API resolution
        ========================================================= */
        Map<String, String> resolved = new Map<String, String>();
        for (String h : headers) {
            String normalized = h.toLowerCase();
            // Explicit UI mapping (PRIORITY)
            if (normalizedCsvMap.containsKey(normalized)) {
                resolved.put(h, normalizedCsvMap.get(normalized));
            } // Automatic fallback
            else if (autoHeaderToApi.containsKey(normalized)) {
                resolved.put(h, autoHeaderToApi.get(normalized));
            } // Blocking error
            else {
                errors.add('Unmapped CSV column: "' + h + '"');
            }
        }
        return resolved;
    }

    public static Boolean handlePicklist(SObject record, Schema.DescribeFieldResult dfr, String apiField, String rawValue, Integer lineNumber, List<String> errors) {
        if (!isValidPicklistValue(dfr, rawValue)) {
            errors.add('Line ' + lineNumber + ' – field "' + dfr.getLabel() + '" : invalid picklist value "' + rawValue + '"');
            return false;
        }
        if (dfr.getType() == Schema.DisplayType.MultiPicklist) {
            record.put(apiField, rawValue.replace(',', ';'));
        } else {
            record.put(apiField, rawValue);
        }
        return true;
    }

    public static void validateRequiredFields(Map<String, Schema.SObjectField> fieldMap, Map<String, Object> populated, Integer lineNumber, List<String> errors) {
        for (Schema.SObjectField sof : fieldMap.values()) {
            Schema.DescribeFieldResult df = sof.getDescribe();
            if (!df.isNillable() && df.isCreateable() && !df.isDefaultedOnCreate() && !populated.containsKey(df.getName())) {
                errors.add('Line ' + lineNumber + ' : required field missing "' + df.getLabel() + '"  (not provided in CSV)');
            }
        }
    }

    /**
     * Validate picklist values (label or value, active only)
     */
    public static Boolean isValidPicklistValue(Schema.DescribeFieldResult dfr, String value) {
        if (String.isBlank(value)) return true;

        for (Schema.PicklistEntry ple : dfr.getPicklistValues()) {
            if (!ple.isActive()) continue;
            if (ple.getValue().equalsIgnoreCase(value) || ple.getLabel().equalsIgnoreCase(value)) {
                return true;
            }
        }
        return false;
    }

    public static List<String> decodeAndSplitCsv(String base64Csv) {
        String csv = EncodingUtil.base64Decode(base64Csv).toString();
        List<String> lines = csv.replace('\r\n', '\n').replace('\r', '\n').split('\n');

        if (lines.isEmpty()) {
            throw new AuraHandledException('Csv file is empty.');
        }
        if (lines.size() - 1 > MAX_LINES) {
            throw new AuraHandledException(
                'CSV import limited to ' + MAX_LINES + ' lines.'
            );
        }
        return lines;
    }

}