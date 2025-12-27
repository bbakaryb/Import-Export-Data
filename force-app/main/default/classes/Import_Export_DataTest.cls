@isTest
private class Import_Export_DataTest {

/* =========================================================
       Test data setup
       ========================================================= */
    @TestSetup
    static void setupData() {
        Account acc = new Account(
            Name = 'Test Import Export',
            Phone = '0102030405'
        );
        insert acc;
    }

    /* =========================================================
       exportCsv delegation
       ========================================================= */
    @IsTest
    static void testExportCsvDelegation() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        List<String> fields = new List<String>{
            'Name',
            'Phone'
        };

        Test.startTest();
        String result =
            Import_Export_Data.exportCsv(
                'Account',
                fields,
                acc.Id
            );
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    /* =========================================================
       importCsv delegation (success)
       ========================================================= */
    @IsTest
    static void testImportCsvDelegation() {
        String csv =
            'Name\n' +
            'Imported Account';

        String base64 =
            EncodingUtil.base64Encode(
                Blob.valueOf(csv)
            );

        Test.startTest();
        Map<String, Object> res =
            Import_Export_Data.importCsv(
                'Account',
                base64,
                null
            );
        Test.stopTest();

        System.assertEquals(true, res.get('success'));
    }

    /* =========================================================
       getObjectApiNameFromRecordId success
       ========================================================= */
    @IsTest
    static void testGetObjectApiNameFromRecordIdSuccess() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        String apiName =
            Import_Export_Data.getObjectApiNameFromRecordId(
                acc.Id
            );
        Test.stopTest();

        System.assertEquals('account', apiName);
    }

    /* =========================================================
       getObjectApiNameFromRecordId invalid id
       ========================================================= */
    @IsTest
    static void testGetObjectApiNameFromRecordIdInvalid() {
        try {
            Import_Export_Data.getObjectApiNameFromRecordId('12');
            System.assert(false, 'Exception expected');
        } catch (AuraHandledException e) {

        }
    }

    /* =========================================================
       getObjectApiNameFromRecordId unknown prefix
       ========================================================= */
    @IsTest
    static void testGetObjectApiNameFromRecordIdUnknown() {
        try {
            Import_Export_Data.getObjectApiNameFromRecordId('999000000000000');
            System.assert(false, 'Exception expected');
        } catch (AuraHandledException e) {

        }
    }

    /* =========================================================
       listFields nominal case
       ========================================================= */
    @IsTest
    static void testListFields() {
        Test.startTest();
        List<Import_Export_Data.FieldDescriptor> fields =
            Import_Export_Data.listFields('Account');
        Test.stopTest();

        System.assertNotEquals(null, fields);
        System.assert(fields.size() > 0);

    }

    /* =========================================================
       listFields null & invalid object
       ========================================================= */
    @IsTest
    static void testListFieldsInvalidInput() {
        System.assertEquals(
            null,
            Import_Export_Data.listFields(null)
        );

        System.assertEquals(
            null,
            Import_Export_Data.listFields('Unknown__c')
        );
    }

    /* =========================================================
       FieldDescriptor DTO
       ========================================================= */
    @IsTest
    static void testFieldDescriptorConstructor() {
        Import_Export_Data.FieldDescriptor fd =
            new Import_Export_Data.FieldDescriptor(
                'Name',
                'Account Name'
            );

        System.assertEquals('Name', fd.api);
        System.assertEquals('Account Name', fd.label);
    }

}