public with sharing class Import_Export_Data {

    /**
     * Export a single record to CSV
     * - Use it to specify import template
     */
    @AuraEnabled
    public static String exportCsv(String objectName, List<String> fields, String recordId) {
        return CsvExportService.exportCsv(objectName, fields, recordId);
    }

    /**
     * Import CSV data
     */
    @AuraEnabled
    public static Map<String, Object> importCsv(String objectName, String base64Csv) {
        return CsvImportService.importCsv(objectName, base64Csv);
    }

    /**
     * Resolve SObject API name from a record Id
     */
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

    /**
     * List available fields for CSV import/export
     */
    @AuraEnabled(cacheable=true)
    public static List<FieldDescriptor> listFields(String objectName) {

        List<FieldDescriptor> res = new List<FieldDescriptor>();

        if (String.isBlank(objectName)) return null;
        Schema.SObjectType st = Schema.getGlobalDescribe().get(objectName);
        if (st == null) return null;

        /* === Technical fields excluded === */
        Set<String> technicalFields = new Set<String>{
            'IsDeleted','CreatedDate','CreatedById',
            'LastModifiedDate','LastModifiedById',
            'SystemModstamp','LastActivityDate',
            'LastViewedDate','LastReferencedDate'
        };

        Map<String, Schema.SObjectField> fmap = st.getDescribe().fields.getMap();

        for (String apiName : fmap.keySet()) {
            Schema.DescribeFieldResult dfr = fmap.get(apiName).getDescribe();
            /* === Exclude technical and system fields === */
            if (technicalFields.contains(dfr.getName()) || dfr.isCalculated() || dfr.isAutoNumber() || dfr.isHtmlFormatted())   {
                continue;
            } 

            /* === Exclude non CSV-friendly field types === */
            Schema.DisplayType t = dfr.getType();
            if (t == Schema.DisplayType.Location || t == Schema.DisplayType.Address || t == Schema.DisplayType.Base64 || t == Schema.DisplayType.EncryptedString) {
                continue;
            }
            /* === Only accessible fields === */
            if (dfr.isAccessible()) {
                res.add(new FieldDescriptor(apiName, dfr.getLabel()));
            }
        }
        return res;
    }

    /**
     * Field descriptor DTO for LWC/Aura
     */
    public with sharing class FieldDescriptor {
        @AuraEnabled public String api;
        @AuraEnabled public String label;

        public FieldDescriptor(String api, String label) {
            this.api = api;
            this.label = label;
        }
    }
    
}

