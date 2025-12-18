public with sharing class Import_Export_Data {

    @AuraEnabled(cacheable=true)
    public static String getObjectApiNameFromRecordId(String recordId) {
        if (String.isBlank(recordId) || recordId.length() < 3) {
            throw new AuraHandledException('RecordId invalide.');
        }
        String prefix = recordId.substring(0,3);
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
        for (String sName : gd.keySet()) {
            Schema.DescribeSObjectResult dsr = gd.get(sName).getDescribe();
            if (prefix.equals(dsr.getKeyPrefix())) {
                return sName;
            }
        }
        throw new AuraHandledException('Unknow object.');
    }

    @AuraEnabled(cacheable=true)
    public static List<String> listFields(String objectName) {
        if (String.isBlank(objectName)) return new List<String>();
        Schema.SObjectType st = Schema.getGlobalDescribe().get(objectName);
        if (st == null) return new List<String>();

        Map<String, Schema.SObjectField> fmap = st.getDescribe().fields.getMap();
        List<String> res = new List<String>();
        for (String fname : fmap.keySet()) {
            Schema.DescribeFieldResult dfr = fmap.get(fname).getDescribe();
            if (dfr.isAccessible()) res.add(fname);
        }
        res.sort();
        return res;
    }

    private static String escapeForCsv(Object input) {
        if (input == null) return '';
        String s = String.valueOf(input);
        if (s.startsWith('(') && s.endsWith(')')) s = s.substring(1, s.length() - 1);
        s = s.replace('\r', ' ').replace('\n', ' ');
        Boolean needQuotes = s.contains(',') || s.contains('"');
        if (s.contains('"')) s = s.replace('"', '""');
        if (needQuotes) s = '"' + s + '"';
        return s;
    }

    @AuraEnabled
    public static String exportCsv(String objectName, List<String> orderedFields, String recordId) {
        if (String.isBlank(objectName) || orderedFields == null || orderedFields.isEmpty())
            throw new AuraHandledException('Objet et champs requis.');

        Schema.SObjectType sType = Schema.getGlobalDescribe().get(objectName);
        if (sType == null) throw new AuraHandledException('Objet inconnu: ' + objectName);

        Schema.DescribeSObjectResult dsr = sType.getDescribe();
        List<String> safeFields = new List<String>();

        for (String f : orderedFields) {
            if (dsr.fields.getMap().containsKey(f) && dsr.fields.getMap().get(f).getDescribe().isAccessible()) {
                safeFields.add(f);
            }
        }
        if (safeFields.isEmpty()) throw new AuraHandledException('Aucun champ accessible.');

        String soql = 'SELECT ' + String.join(safeFields, ',') +
                      ' FROM ' + String.escapeSingleQuotes(objectName) +
                      ' WHERE Id = :recordId';
        List<SObject> rows = Database.query(soql);

        List<String> lines = new List<String>();
        lines.add(String.join(safeFields, ','));

        for (SObject r : rows) {
            List<String> vals = new List<String>();
            for (String f : safeFields) {
                vals.add(escapeForCsv(r.get(f)));
            }
            lines.add(String.join(vals, ','));
        }

        String csvContent = String.join(lines, '\n');
        return EncodingUtil.base64Encode(Blob.valueOf(csvContent));
    }

    @AuraEnabled
    public static Map<String, Object> importCsv(String objectName, String base64Csv) {
        if (String.isBlank(objectName) || String.isBlank(base64Csv)) {
            throw new AuraHandledException('Object and file required.');
        }

        // Décodage
        String csv = EncodingUtil.base64Decode(base64Csv).toString();

        List<String> lines = csv.split('\n');
        if (lines.isEmpty()) {
            throw new AuraHandledException('Csv file is empty.');
        }

        // Lecture de l’en-tête
        List<String> headers = new List<String>();
        for (String h : lines[0].split(',')) {
            headers.add(h.trim());
        }

        List<SObject> toInsert = new List<SObject>();
        Schema.SObjectType sType = Schema.getGlobalDescribe().get(objectName);
        if (sType == null) throw new AuraHandledException('Unknow object: ' + objectName);

        for (Integer i = 1; i < lines.size(); i++) {
            String line = lines[i].trim();
            if (String.isBlank(line)) continue;

            List<String> cols = line.split(',');
            if (cols.size() != headers.size()) continue;

            SObject record = sType.newSObject();
            for (Integer c = 0; c < headers.size(); c++) {
                String fieldName = headers[c];
                String fieldValue = cols[c].replace('"','').trim();
                if (!String.isBlank(fieldValue)) {
                    try {
                        record.put(fieldName, fieldValue);
                    } catch (Exception e) {

                    }
                }
            }
            toInsert.add(record);
        }

        Database.SaveResult[] results = Database.insert(toInsert, false);
        Integer success = 0, errors = 0;
        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) success++; else errors++;
        }

        return new Map<String, Object>{
            'inserted' => success,
            'failed' => errors
        };
    }

}
