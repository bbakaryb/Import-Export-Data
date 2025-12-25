public with sharing class CsvExportService {
    
    /**
     * Export a record to CSV (Base64 encoded)
     */
    public static String exportCsv(String objectName, List<String> orderedFields, String recordId){
        if (String.isBlank(objectName) || orderedFields == null || orderedFields.isEmpty()) {
            throw new AuraHandledException('Object and field required.');
        }

        Schema.SObjectType sType = Schema.getGlobalDescribe().get(objectName);
        if (sType == null) {
            throw new AuraHandledException('Unknown object: ' + objectName);
        }

        Schema.DescribeSObjectResult dsr = sType.getDescribe();
        Map<String, Schema.SObjectField> fieldMap = dsr.fields.getMap();

        /* === Allowed field API names === */
        List<String> safeFields = new List<String>();

        /* === CSV headers (field labels) === */
        List<String> headers = new List<String>();

        for (String f : orderedFields) {
            if (fieldMap.containsKey(f)) {
                Schema.DescribeFieldResult dfr = fieldMap.get(f).getDescribe();
                if (dfr.isAccessible()) {
                    safeFields.add(f);
                    // Utilisation du LABEL du champ
                    headers.add(CsvUtils.escape(dfr.getLabel()));
                }
            }
        }

        if (safeFields.isEmpty()) {
            throw new AuraHandledException('No accessible fields');
        }

        String soql =
            'SELECT ' + String.join(safeFields, ',') +
            ' FROM ' + String.escapeSingleQuotes(objectName) +
            ' WHERE Id = :recordId';

        List<SObject> rows = Database.query(soql);

        List<String> lines = new List<String>();

        /* === Header line === */
        lines.add(String.join(headers, ','));
        /* === Data lines === */
        for (SObject r : rows) {
            List<String> vals = new List<String>();
            for (String f : safeFields) {
                vals.add(CsvUtils.escape(r.get(f)));
            }
            lines.add(String.join(vals, ','));
        }

        String csvContent = String.join(lines, '\n');
        return EncodingUtil.base64Encode(Blob.valueOf(csvContent));
    }

}