public with sharing class CsvImportService {

    private static final Integer MAX_LINES = 5000;

    public static Map<String, Object> importCsv(String objectName, String base64Csv) {
        if (String.isBlank(objectName) || String.isBlank(base64Csv)) {
            throw new AuraHandledException('Object and file required.');
        }

        Boolean isUpdate = false; // INSERT
        

        List<String> errors = new List<String>();
        List<SObject> toInsert = new List<SObject>();

        // Décodage
        String csv = EncodingUtil.base64Decode(base64Csv).toString();

        List<String> lines = csv.replace('\r\n', '\n').replace('\r', '\n').split('\n');

        if (lines.isEmpty()) {
            throw new AuraHandledException('Csv file is empty.');
        }
        if (lines.size() - 1 > MAX_LINES) {
            throw new AuraHandledException(
                'Import limité à ' + MAX_LINES + ' lignes.'
            );
        }
        /* === Objet & describe === */
        Schema.SObjectType sType = Schema.getGlobalDescribe().get(objectName);
        if (sType == null) throw new AuraHandledException('Unknow object: ' + objectName);

        Schema.DescribeSObjectResult dsr = sType.getDescribe();
        Map<String, Schema.SObjectField> fieldMap = dsr.fields.getMap();

        /* === Mapping HEADER (label / api) → API NAME === */
        Map<String, String> headerToApi = new Map<String, String>();
        for (String api : fieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldMap.get(api).getDescribe();
            headerToApi.put(api.toLowerCase(), api);
            headerToApi.put(dfr.getLabel().toLowerCase(), api);
        }

        /* === Headers CSV === */
        List<String> headers = new List<String>();
        for (String h : CsvUtils.parseLine(lines[0])) {
            headers.add(h.replace('"', '').trim().toLowerCase());
        }

        isUpdate = headers.contains('id');

        /* === Lines CSV === */
        for (Integer i = 1; i < lines.size(); i++) {
            String line = lines[i].trim();
            if (String.isBlank(line)) continue;

            Integer lineNumber = i + 1;
            List<String> cols = CsvUtils.parseLine(line);

            //if (cols.size() != headers.size()) continue;
            if (cols.size() != headers.size()) {
                errors.add('Ligne ' + lineNumber + ' : nombre de colonnes incorrect.');
                continue;
            }

            SObject record = sType.newSObject();
            Boolean hasAtLeastOneValue = false;

            for (Integer c = 0; c < headers.size(); c++) {
                String header = headers[c];
                String rawValue = cols[c].trim();
                if(rawValue == null || rawValue == '' || String.isBlank(rawValue)) continue;
                if (!headerToApi.containsKey(header)) {
                    errors.add('Ligne ' + lineNumber + ' : colonne inconnue "' + header + '"');
                    continue;
                }

                String apiField = headerToApi.get(header);
                /* === CAS SPÉCIAL : ID === */
                if (apiField == 'Id') {
                    try {
                        record.put('Id', (Id) rawValue);
                        hasAtLeastOneValue = true;
                    } catch (Exception e) {
                        errors.add('Ligne ' + lineNumber + ' : Id invalide "' + rawValue + '"');
                    }
                    continue;
                }
                Schema.DescribeFieldResult dfr = fieldMap.get(apiField).getDescribe();
                    
                Boolean canWrite = (isUpdate && dfr.isUpdateable()) || (!isUpdate && dfr.isCreateable());
                    
                if((!canWrite) || String.isBlank(rawValue)) continue;

                try {
                    /* === PICKLIST : validation stricte === */
                    if (dfr.getType() == Schema.DisplayType.Picklist || dfr.getType() == Schema.DisplayType.MultiPicklist) {
                        if (!isValidPicklistValue(dfr, rawValue)) {
                            errors.add('Ligne ' + lineNumber + ' – Champ "' + dfr.getLabel() + '" : valeur picklist invalide "' + rawValue + '"');
                            continue;
                        }
                        if (dfr.getType() == Schema.DisplayType.MultiPicklist) {
                            record.put(apiField, rawValue.replace(',', ';'));
                            hasAtLeastOneValue = true;
                            continue;
                        }
                        else {
                            record.put(apiField, rawValue);
                            hasAtLeastOneValue = true;
                            continue;
                        }
                        
                    }

                    /* === AUTRES TYPES (Boolean inclus) === */
                    Object typedValue = castToCorrectType(dfr, rawValue);

                    if (typedValue == null) {
                        errors.add('Ligne ' + lineNumber + ' – Champ "' + dfr.getLabel() + '" : valeur invalide "' + rawValue + '"');
                    } else {
                        record.put(apiField, typedValue);
                        hasAtLeastOneValue = true;
                    }

                }
                catch (Exception e) {
                    errors.add('Ligne ' + lineNumber + ' – Champ "' + dfr.getLabel() + '" : ' + e.getMessage());
                }
            }
            if (hasAtLeastOneValue) {
                toInsert.add(record);
            }
            
        }

        /* === STOP si erreurs === */
        if (!errors.isEmpty()) {
            return new Map<String, Object>{
                'success' => false,
                'errors' => errors
            };
        }

        Database.UpsertResult[] results =
            Database.upsert(toInsert, false);

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
                        // valeur invalide → rejet explicite
                        throw new IllegalArgumentException(
                            'Invalid boolean value: ' + rawValue
                        );
                    }
                    // valeur invalide → rejet explicite
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

}