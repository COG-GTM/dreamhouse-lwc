@isTest
private class TestSampleDataController {
    private static Integer sampleRecordCount(String resourceName) {
        StaticResource resource = [
            SELECT Body
            FROM StaticResource
            WHERE Name = :resourceName
        ];
        return ((List<Object>) JSON.deserializeUntyped(
                resource.Body.toString()
            ))
            .size();
    }

    @isTest
    static void importSampleData() {
        Test.startTest();
        SampleDataController.importSampleData();
        Test.stopTest();

        Integer propertyNumber = [SELECT COUNT() FROM Property__c];
        Integer brokerNumber = [SELECT COUNT() FROM Broker__c];
        Integer contactNumber = [SELECT COUNT() FROM Contact];

        Assert.isTrue(propertyNumber > 0, 'Expected properties were created.');
        Assert.isTrue(brokerNumber > 0, 'Expected brokers were created.');
        Assert.isTrue(contactNumber > 0, 'Expected contacts were created.');
    }

    @isTest
    static void importSampleDataMatchesStaticResources() {
        Test.startTest();
        SampleDataController.importSampleData();
        Test.stopTest();

        Assert.areEqual(
            sampleRecordCount('sample_data_brokers'),
            [SELECT COUNT() FROM Broker__c],
            'Expected one broker per sample_data_brokers entry.'
        );
        Assert.areEqual(
            sampleRecordCount('sample_data_properties'),
            [SELECT COUNT() FROM Property__c],
            'Expected one property per sample_data_properties entry.'
        );
        Assert.areEqual(
            sampleRecordCount('sample_data_contacts'),
            [SELECT COUNT() FROM Contact],
            'Expected one contact per sample_data_contacts entry.'
        );
    }

    @isTest
    static void importSampleDataLinksPropertiesToBrokers() {
        Test.startTest();
        SampleDataController.importSampleData();
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Property__c WHERE Broker__c = NULL],
            'Expected every property to be linked to an imported broker.'
        );
    }

    @isTest
    static void importSampleDataListsPropertiesWithinLast90Days() {
        Date today = System.today();

        Test.startTest();
        SampleDataController.importSampleData();
        Test.stopTest();

        for (Property__c property : [
            SELECT Name, Date_Listed__c
            FROM Property__c
        ]) {
            Assert.isNotNull(
                property.Date_Listed__c,
                'Expected Date_Listed__c to be set on ' + property.Name
            );
            Assert.isTrue(
                property.Date_Listed__c >= today.addDays(-89) &&
                    property.Date_Listed__c <= today,
                'Expected Date_Listed__c within the last 90 days on ' +
                property.Name
            );
        }
    }

    @isTest
    static void importSampleDataReplacesExistingRecords() {
        Contact existingContact = new Contact(LastName = 'Existing');
        insert existingContact;
        Case existingCase = new Case(
            Subject = 'Existing',
            ContactId = existingContact.Id
        );
        insert existingCase;
        Broker__c existingBroker = new Broker__c(Name = 'Existing Broker');
        insert existingBroker;
        Property__c existingProperty = new Property__c(
            Name = 'Existing Property',
            Broker__c = existingBroker.Id
        );
        insert existingProperty;

        Test.startTest();
        SampleDataController.importSampleData();
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Case],
            'Expected existing cases to be deleted.'
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Contact WHERE Id = :existingContact.Id],
            'Expected existing contacts to be deleted.'
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Broker__c WHERE Id = :existingBroker.Id],
            'Expected existing brokers to be deleted.'
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Property__c WHERE Id = :existingProperty.Id],
            'Expected existing properties to be deleted.'
        );
        Assert.areEqual(
            sampleRecordCount('sample_data_properties'),
            [SELECT COUNT() FROM Property__c],
            'Expected only the sample properties after import.'
        );
    }

    @isTest
    static void importSampleDataIsRepeatable() {
        Test.startTest();
        SampleDataController.importSampleData();
        SampleDataController.importSampleData();
        Test.stopTest();

        Assert.areEqual(
            sampleRecordCount('sample_data_brokers'),
            [SELECT COUNT() FROM Broker__c],
            'Expected re-import not to duplicate brokers.'
        );
        Assert.areEqual(
            sampleRecordCount('sample_data_properties'),
            [SELECT COUNT() FROM Property__c],
            'Expected re-import not to duplicate properties.'
        );
        Assert.areEqual(
            sampleRecordCount('sample_data_contacts'),
            [SELECT COUNT() FROM Contact],
            'Expected re-import not to duplicate contacts.'
        );
    }
}
